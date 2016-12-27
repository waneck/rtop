package rtop;
import geo.UnixDate;
import geo.units.Seconds;
import rtop.utils.Glob;
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

  /**
    Maximum amount of KB a single log can generate before getting capped. Set to -1 to disable cap
   **/
  public var maxSingleLogKB:Float = 1024; // 1MB

  /**
    The log buffer size - 4KB by default
   **/
  public var bufSize:Int = 1024 * 4;

  var m_toUpload:Deque<{ name:String, final:Bool, compress:Bool }> = new Deque();
  @:allow(rtop.LogWatcher)
  var m_logPaths:Array<{ path:String, ?pattern:Glob }> = [];
  var m_extraRsyncArgs:Array<String> = [];
  var m_closing:Deque<Int> = new Deque();

  /**
    Adds a log dir to be synchronized. If `dir` has a colon, the second part of the string will be a pattern (regex)
   **/
  public function logPath(path:String) {
    var split = path.split(':');
    if (split.length > 1) {
      m_logPaths.push({ path:Glob.normalizePath(split[0]), pattern:new Glob(split.slice(1).join(':'), [NoDot, Posix]) });
    } else {
      m_logPaths.push({ path:Glob.normalizePath(path) });
    }
  }

  @:skip public function waitClose() {
    var ret = m_closing.pop(true);
    m_closing.push(ret);
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
    create('data'); // current working data
    create('current');
    create('config');
    // first check if we have data on our current folder that needs to be sent
    if (this.uploadTarget != null) {
      this.startUploading();
    }

    if (m_logPaths.length > 0) {
      this.startWatchingLogs();
    }

    while(!isClosing()) {
      Sys.sleep(100);
    }
  }

  @:skip inline public function isClosing() {
    var ret = m_closing.pop(false);
    if (ret != null) {
      m_closing.push(ret);
      return true;
    } else {
      return false;
    }
  }

  private function startWatchingLogs() {
    createThread(function() {
      var w = new LogWatcher(this);
      w.init();
      w.loop();
    });
  }

  private function createThread(fn:Void->Void) {
    cpp.vm.Thread.create(function() {
      try {
        fn();
        m_closing.add(0);
      }
      catch(e:Dynamic) {
        Sys.stderr().writeString('Error on thread: $e\n${haxe.CallStack.toString(haxe.CallStack.exceptionStack())}\n');
        m_closing.push(1);
      }
    });
  }

  private function startUploading() {
    // first check which files we need to upload
    var cur = Utils.getPathPart( Utils.fastNow() );
    for (file in readDirectory('$dataDir/$hostname/current')) {
      // check if we should compress
      var path = '$dataDir/$hostname/current/$file';
      try {
        var targetPath = Utils.readlink(path);
        if (targetPath == null) {
          continue;
        }

        if (isDirectory(targetPath)) {
          return;
        }
        targetPath = sys.FileSystem.absolutePath(targetPath);
        var dataPath = sys.FileSystem.absolutePath('$dataDir/$hostname/data');
        if (!targetPath.startsWith(dataPath)) {
          trace('Warning', 'File $path is in current path but it does not point to a data path');
          continue;
        }
        var name = targetPath.substr(dataPath.length);
        while (name.charCodeAt(0) == '/'.code) {
          name = name.substr(1);
        }

        var compress = stat(targetPath).size >= Globals.COMPRESS_SIZE_THRESHOLD;

        if (name.startsWith(cur)) {
          m_toUpload.add({ name:name, final:false, compress:compress });
        } else {
          trace('$name does not start with $cur');
          m_toUpload.add({ name:name, final:true, compress:compress });
        }
      }
      catch(e:Dynamic) {
        trace('Error', 'Error while checking path $path: $e');
      }
    }

    createThread(function() {
      var toUpload = m_toUpload,
          rsync = this.rsyncPath,
          compress = !this.skipCompression,
          extraArgs = m_extraRsyncArgs,
          hostname = this.hostname,
          bwlimit = this.bwlimit,
          timeout = this.timeout,
          uploadInterval = this.uploadIntervalSecs;
      var lastFiles = new List<{ name:String, expiration:UnixDate }>();
      while(!isClosing()) {
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
        if (!exists('$dataDir/$hostname/data/${cur.name}')) {
          trace('want to upload ${cur.name}, but it does not exist');
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
          // verify the final version
          args.push('--append-verify');
        } else {
          // we are sending an append-only file
          args.push('--append');
          // we handle incomplete files
          args.push('--inplace');
        }
        if (extraArgs.length > 0) {
          args = args.concat(extraArgs);
        }
        args.push('$dataDir/./$hostname/data/${cur.name}');
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
            deleteFile('$dataDir/$hostname/current/${cur.name.replace('/','_')}');
          } catch(e:Dynamic) {
            trace('Error', 'Error while deleting current ${cur.name}: $e');
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

  @:skip public function createFileFromPart(part:String, suffix:String) {
    var path = '$dataDir/$hostname/data/$part$suffix';
    if (!exists(haxe.io.Path.directory(path))) {
      createDirectory(haxe.io.Path.directory(path));
    }

    var ret = sys.io.File.append(path, true);
    try {
      var target = '$dataDir/$hostname/current/${part.replace('/','_')}$suffix';
      if (!exists(target)) {
        Utils.symlink(path, target);
      }
    } catch(e:Dynamic) {
      trace('Error', 'Symlink failed: $e');
      ret.close();
      throw e;
    }

    return ret;
  }

  @:skip public function uploadFinalFile(name:String, compress:Bool) {
    trace('uploadFinalFile $name');
    m_toUpload.add({ name:name, final:true, compress:compress });
  }
}
