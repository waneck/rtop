package rtop;
import geo.UnixDate;
import geo.units.Seconds;
import rtop.utils.Utils;
import rtop.utils.Watcher;
import sys.FileSystem.*;
import cpp.vm.Deque;

using StringTools;

/**
  rtop-agent - remote top agent
 **/
class Agent extends mcli.CommandLine {

  /**
    the sys filesystem mount directory
   **/
  public var sysdir:String = '/sys';

  /**
    the proc filesystem mount directory
   **/
  public var procDir:String = '/proc';

  /**
    The base data dir where the rtopd environment will be setup
   **/
  public var dataDir:String = '/tmp/var/lib/rtopd/data';

  /**
    The amount of interval between beats
   **/
  public var beatSecs:Float = 10.0;

  /**
    Since process beats are much larger in size, it is advised to set a ratio
    between normal beats and process beats. Default is 6 - so
    a process beat will happen once every 6 beats
   **/
  public var processBeatRatio:Int = 6;

  /**
    The amount of wait time between uploads
   **/
  public var uploadIntervalSecs:Int = 60;

  /**
    The target rsync upload target data dir. If remote, might be in the form of username@host:/path/to/dir.
    If not set, the agent will not upload the files
   **/
  public var uploadTarget:String;

  /**
    Bandwidth limit (in KB/s)
   **/
  public var bwlimit:Float = -1;

  /**
    Path to use rsync
   **/
  public var rsyncPath:String = 'rsync';

  /**
    Never compress a file while sending it over (saves cpu)
   **/
  public var skipCompression:Bool = false;

  /**
    The host name used to identify this server
   **/
  public var hostname:String = Utils.getHostName();

  /**
    This timeout in seconds. If 0 or less, no timeout will be set
   **/
  public var timeout:Float = 60;

  var m_toUpload:Deque<{ name:String, final:Bool, compress:Bool }> = new Deque();
  var m_logPaths:Array<{ path:String, ?pattern:EReg }> = [];
  var m_extraRsyncArgs:Array<String> = [];

  /**
    Adds a log dir to be synchronized. If `dir` has a colon, the second part of the string will be a pattern (regex)
   **/
  public function logPath(path:String) {
    var split = path.split(':');
    if (split.length > 1) {
      m_logPaths.push({ path:split[0], pattern:new EReg(split.slice(1).join(':'), '') });
    } else {
      m_logPaths.push({ path:path });
    }
  }

  /**
    If extra rsync arguments are needed, set them here
   **/
  public function rsyncArg(arg:String) {
    m_extraRsyncArgs.push(arg);
  }

  public function runDefault() {
    if (this.processBeatRatio <= 0) {
      trace('ProcessBeatRation must be a non-zero, positive number');
      Sys.exit(1);
    }
    if (this.hostname == null) {
      trace('Error', 'Host name cannot be used');
      Sys.exit(1);
    }

    trace(this.hostname);
    trace(m_logPaths);
    function create(dir:String) {
      if (!exists('$dataDir/$hostname/$dir')) {
        createDirectory('$dataDir/$hostname/$dir');
      }
    }
    create('current'); // current working data
    create('sent');
    // create('');
    // first check if we have data on our current folder that needs to be sent
    if (this.uploadTarget != null) {
      this.startUploading();
    }

    if (m_logPaths.length > 0) {
      this.startWatchingLogs();
    }

    while(true) {
      Sys.sleep(100);
    }
  }

  private function startWatchingLogs() {
    cpp.vm.Thread.create(function() {
      var watcher = new rtop.utils.Watcher();
      for (path in m_logPaths) {
        watcher.add(path.path, Modify | MovedFrom | Delete | DeleteSelf, function(flags, name) {
          trace(path);
          trace(flags);
          trace(name);
          trace(flags.hasAny(Modify));
        });
      }

      while(true) {
        watcher.waitOnce();
      }
    });
  }

  private function startUploading() {
    // first check which files we need to upload
    var cur = Utils.getPathPart( Utils.fastNow(), true );
    for (file in readDirectory('$dataDir/$hostname/current')) {
      // check if we should compress
      var path = '$dataDir/$hostname/current/$file';
      if (isDirectory(path)) {
        return;
      }
      var compress = stat(path).size >= Globals.COMPRESS_SIZE_THRESHOLD;

      if (file.startsWith(cur)) {
        m_toUpload.add({ name:file, final:false, compress:compress });
      } else {
        m_toUpload.add({ name:file, final:true, compress:compress });
      }
    }

    cpp.vm.Thread.create(function() {
      var toUpload = m_toUpload,
          rsync = this.rsyncPath,
          compress = !this.skipCompression,
          extraArgs = m_extraRsyncArgs,
          hostname = this.hostname,
          bwlimit = this.bwlimit,
          timeout = this.timeout,
          uploadInterval = this.uploadIntervalSecs;
      var lastFiles = new List<{ name:String, expiration:UnixDate }>();
      while(true) {
        var cur = toUpload.pop(true);
        var now = Utils.fastNow();
        while (lastFiles.last() != null && lastFiles.last().expiration >= now) {
          lastFiles.pop();
        }

        if (cur == null) {
          trace('Received stop signal. Stopping...');
          return;
        }
        if (cur.name.indexOf('..') >= 0) {
          trace('Error', 'ignoring $cur: contains special characters');
          continue;
        }
        if (!exists('$dataDir/$hostname/current/${cur.name}')) {
          // file already sent, exit
          continue;
        }
        if (!cur.final) {
          var shouldProcess = true;
          for (file in lastFiles) {
            if (file.name == cur.name) {
              // this file was already transferred lately, don't do it again
              shouldProcess = false;
              break;
            }
          }
          if (!shouldProcess) {
            continue;
          }
        }

        trace('uploading $cur');
        var args = ['-qR' + (compress && cur.compress ? 'z' : ''), '--chmod=a+rw'];
        if (bwlimit > 0) {
          args.push('--bwlimit=$bwlimit');
        }
        if (timeout > 0) {
          args.push('--timeout=$timeout');
        }
        if (cur.final) {
          // checksum
          args.push('-c');
        } else {
          // we are sending an append-only file
          args.push('--append');
          // we handle incomplete files
          args.push('--inplace');
        }
        if (extraArgs.length > 0) {
          args = args.concat(extraArgs);
        }
        args.push('$dataDir/./$hostname/current/${cur.name}');
        args.push(uploadTarget);

        var res = Sys.command(rsync, args);
        if (res != 0) {
          trace('Error', 'Rsync command failed for arguments $args');
          if (cur.final) {
            // add this again to the bottom of the queue
            toUpload.add(cur);
          }
          continue;
        }
        if (cur.final) {
          try {
            rename('$dataDir/$hostname/current/${cur.name}', '$dataDir/$hostname/sent/${cur.name}');
          } catch(e:Dynamic) {
            trace('Error', 'Error while renaming to sent: $e');
            toUpload.add(cur);
          }
          continue;
        }
        lastFiles.add({ name:cur.name, expiration: Utils.fastNow() + new Seconds(uploadInterval) });
      }
    });
  }

  static function main() {
    new mcli.Dispatch(Sys.args()).dispatch(new Agent());
  }
}
