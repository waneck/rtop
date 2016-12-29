package rtop;
import geo.UnixDate;
import geo.units.Seconds;
import rtop.utils.Glob;
import rtop.utils.Timer;
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
    the base data dir where the rtopd environment will be setup
   **/
  public var dataDir:String = '/tmp/var/lib/rtopd/data';

  /**
    the amount of interval between beats
   **/
  public var beatSecs:Float = 10.0;

  /**
    since process beats are much larger in size, it is advised to set a ratio
    between normal beats and process beats. Default is 6 - so
    a process beat will happen once every 6 beats
   **/
  public var processBeatRatio:Int = 6;

  /**
    the amount of wait time between uploads
   **/
  public var uploadIntervalSecs:Int = 60;

  /**
    the target rsync upload target data dir. If remote, might be in the form of username@host:/path/to/dir.
    If not set, the agent will not upload the files
   **/
  public var uploadTarget:String;

  /**
    bandwidth limit (in KB/s)
   **/
  public var bwlimit:Float = -1;

  /**
    path to use rsync
   **/
  public var rsyncPath:String = 'rsync';

  /**
    never compress a file while sending it over (saves cpu)
   **/
  public var skipCompression:Bool = false;

  /**
    the host name used to identify this server
   **/
  public var hostname:String = Utils.getHostName();

  /**
    this timeout in seconds. If 0 or less, no timeout will be set
   **/
  public var timeout:Float = 60;

  /**
    maximum amount of KB a single log can generate before getting capped. Set to -1 to disable cap
   **/
  public var maxSingleLogKB:Float = 1024; // 1MB

  /**
    the log buffer size - 4KB by default
   **/
  public var bufSize:Int = 1024 * 4;

  var toUpload:Deque<{ name:String, final:Bool, compress:Bool }> = new Deque();
  @:allow(rtop.LogWatcher)
  var logPaths:Array<{ path:String, ?pattern:Glob }> = [];
  var extraRsyncArgs:Array<String> = [];
  var closing:Deque<Int> = new Deque();

  /**
    adds a log dir to be synchronized. If `dir` has a colon, the second part of the string will be a pattern (regex)
   **/
  public function logPath(path:String) {
    var split = path.split(':');
    if (split.length > 1) {
      this.logPaths.push({ path:Glob.normalizePath(split[0]), pattern:new Glob(split.slice(1).join(':'), [NoDot, Posix]) });
    } else {
      this.logPaths.push({ path:Glob.normalizePath(path) });
    }
  }

  @:skip public function waitClose() {
    var ret = this.closing.pop(true);
    this.closing.push(ret);
  }

  /**
    if extra rsync arguments are needed, set them here
   **/
  public function rsyncArg(arg:String) {
    this.extraRsyncArgs.push(arg);
  }

  /**
    start processing
   **/
  public function start() {
    if (this.processBeatRatio <= 0) {
      trace('ProcessBeatRation must be a non-zero, positive number');
      Sys.exit(1);
    }
    if (this.hostname == null) {
      trace('Error', 'Host name cannot be used');
      Sys.exit(1);
    }

    trace(this.hostname);
    trace(this.logPaths);
    function create(dir:String) {
      if (!exists('$dataDir/$hostname/$dir')) {
        createDirectory('$dataDir/$hostname/$dir');
      }
    }
    create('data');
    create('current');
    create('config');
    // first check if we have data on our current folder that needs to be sent
    if (this.uploadTarget != null) {
      this.startUploading();
    }

    if (this.logPaths.length > 0) {
      this.startWatchingLogs();
    }

    var timer = new Timer(false);
    timer.set(Std.int(beatSecs), Std.int((beatSecs - Std.int(beatSecs)) * 1000000000.0), false);
    var timesSinceProcesses = 0,
        first = true;
    var lastUpload = 0.0,
        stats = new Stats(this);
    stats.init();
    while(!isClosing()) {
      var shouldCheckProcesses = first;
      first = false;

      var times = timer.wait();
      if (times > 1) {
        trace('Warning', 'Timer is not keeping up with the interval $beatSecs: $times');
      }
      timesSinceProcesses += times;
      shouldCheckProcesses = shouldCheckProcesses || timesSinceProcesses >= processBeatRatio;
      if (shouldCheckProcesses) {
        timesSinceProcesses = 0;
      }
      var curTime = Utils.fastNow(),
          upTime = Utils.getUptime();

      stats.createBeat(curTime, upTime, shouldCheckProcesses);

      if (upTime.float() - lastUpload >= this.uploadIntervalSecs) {
        var base = Utils.getPathPart(curTime);
        this.toUpload.add({ name:base + '.beats', final:false, compress:false });
        this.toUpload.add({ name:base + '.logs', final:false, compress:true });
        this.toUpload.add({ name:base + '.proc', final:false, compress:false });
        lastUpload = upTime.float();
      }
    }
  }

  @:skip inline public function isClosing() {
    var ret = this.closing.pop(false);
    if (ret != null) {
      this.closing.push(ret);
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
        this.closing.add(0);
      }
      catch(e:Dynamic) {
        Sys.stderr().writeString('Error on thread: $e\n${haxe.CallStack.toString(haxe.CallStack.exceptionStack())}\n');
        this.closing.push(1);
      }
    });
  }

  /**
    check and fix the target log file
   **/
  public function checkLogs(path:String) {
    LogWatcher.checkFile(path, true);
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
          this.toUpload.add({ name:name, final:false, compress:compress });
        } else {
          trace('$name does not start with $cur');
          this.toUpload.add({ name:name, final:true, compress:compress });
        }
      }
      catch(e:Dynamic) {
        trace('Error', 'Error while checking path $path: $e');
      }
    }

    createThread(function() {
      var toUpload = this.toUpload,
          rsync = this.rsyncPath,
          compress = !this.skipCompression,
          extraArgs = this.extraRsyncArgs,
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
        lastFiles.add({ name:cur.name, expiration: Utils.fastNow() + new Seconds(uploadInterval / 2) });
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
    this.toUpload.add({ name:name, final:true, compress:compress });
  }
}
