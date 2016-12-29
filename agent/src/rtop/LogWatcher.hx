package rtop;
import geo.UnixDate;
import rtop.utils.Glob;
import rtop.utils.Utils;
import rtop.utils.Watcher;
import sys.FileSystem.*;

using StringTools;

class LogWatcher {
  var agent:Agent;
  var watcher:Watcher;
  var registry:Map<String, LiveData>;
  var enabled:Bool;
  var buf:haxe.io.Bytes;
  var outFile:sys.io.FileOutput;
  var outPrefix:String;

  public function new(agent:Agent) {
    this.agent = agent;
    this.watcher = new Watcher();
    this.buf = haxe.io.Bytes.alloc(this.agent.bufSize);
    this.loadRegistry();
  }

  public function init() {
    // cleanup registry
    var toDelete = [];
    for (registry in this.registry) {
      var found = false;
      for (logPath in this.agent.logPaths) {
        if (registry.source.startsWith(logPath.path)) {
          found = true;
          break;
        }
      }
      if (!found) {
        toDelete.push(registry.source);
      }
    }
    for (del in toDelete) {
      this.registry.remove(del);
    }

    // start watching
    var found = false;
    for (logPath in this.agent.logPaths) {
      if (!exists(logPath.path)) {
        trace('Warning', 'Log path ${logPath.path} does not exist. Skipping');
        continue;
      }
      if (!isDirectory(logPath.path)) {
        trace('Warning', 'Log path ${logPath.path} is not a directory. Skipping');
        continue;
      }
      found = true;
      var wd = 0;
      var path = logPath.path;
      wd = this.watcher.add(logPath.path, Modify | MovedFrom | MovedTo | Delete | DeleteSelf, function(flags, name, cookie) {
        if (!isDirectory('$path/$name') && (logPath.pattern == null || logPath.pattern.match(name).exact)) {
          if (flags.hasAny(Modify | MovedTo)) {
            updateFile(Glob.normalizePath('${path}/$name'), flags.hasAny(Delete | MovedFrom));
          } else if (flags.hasAny(Delete | MovedFrom)) {
            updateFile(Glob.normalizePath('${path}/$name'), true);
          }
        }

        if (flags.hasAll(DeleteSelf)) {
          this.watcher.remove(wd);
        }
      });

      for (file in readDirectory(path)) {
        if (!isDirectory('$path/$file') && (logPath.pattern == null || logPath.pattern.match(file).exact)) {
          updateFile(Glob.normalizePath('${logPath.path}/$file'), false);
        }
      }
    }

    if (found) {
      // watch for new file creation at current
      var wd = 0;
      wd = this.watcher.add(this.agent.dataDir + '/' + this.agent.hostname + '/current', Create, function(_,_,_) {
        trace('new file created');
        this.saveRegistry();
      });
    }

    this.enabled = found;
  }

  private function updateFile(path:String, reset:Bool) {
    var reg = this.registry[path];

    var size = -1;
    var data = reset ? null : try stat(path) catch(e:Dynamic) { trace('Error', 'Stat $path failed: $e'); null; };

    if (reg == null) {
      if (data == null) {
        releaseFile(path);
        return;
      }
      // create a new one
      this.registry[path] = (reg = { source:path, offset:0, inode:data.ino, device:data.dev });
      size = data.size;
    } else {
      if (data != null) {
        if (data.ino != reg.inode || data.dev != reg.device) {
          trace(data.ino, reg.inode);
          trace(data.dev, reg.device);
          trace('Warning', 'Inode/device changed for $path. Reading from the beginning');
          reset = true;
        }
      } else {
        // file was deleted
        reset = true;
      }

      if (reset) {
        if (data != null && reg.file == null) {
          // file hasn't been used for now - just replace with new data
          reg.inode = data.ino;
          reg.device = data.dev;
          reg.offset = 0;
          size = data.size;
        } else if (reg.file != null && data == null) {
          // get rest of data
          try {
            reg.file.seek(0, SeekEnd);
            size = reg.file.tell();
          } catch(e:Dynamic) {
            trace('Warning', 'Error while getting end of file: $e');
            releaseFile(path);
            return;
          }
        } else {
          releaseFile(path);
          return;
        }
      } else {
        if (data != null) {
          size = data.size;
        }
      }
    }
    if (reg.file == null) {
      try {
        reg.file = sys.io.File.read(path, true);
      }
      catch(e:Dynamic) {
        trace('Error', 'Error accessing $path: $e');
        releaseFile(path);
        return;
      }
    }

    var amount = size - reg.offset,
        isComplete = true;
    if (this.agent.maxSingleLogKB > 0 && amount > this.agent.maxSingleLogKB * 1024) {
      trace('Warning', 'File $path is bigger than maximum single log update. Capping...');
      amount = Std.int(this.agent.maxSingleLogKB * 1024);
      reg.offset = size - amount;
      isComplete = false;
    }

    if (reg.offset < 0 || size < 0) {
      // overflow
      trace('Error', 'File overflow $path');
      releaseFile(path);
      return;
    }

    if (amount < 0) {
      trace('Warning', 'Amount is negative for $path: $amount');
      return;
    }
    if (amount == 0) {
      return;
    }

    var out = null;
    var now = Utils.fastNow();
    var nowPath = Utils.getPathPart(now);
    if (this.outPrefix == null) {
      this.outPrefix = nowPath;
      this.outFile = this.agent.createFileFromPart(nowPath, '.logs');
    } else if (nowPath != this.outPrefix) {
      this.outFile.close();
      this.outFile = null;
      this.saveRegistry();
      this.agent.uploadFinalFile( this.outPrefix + '.logs', true );
      this.outPrefix = nowPath;
      this.outFile = this.agent.createFileFromPart(nowPath, '.logs');
    }

    // header
    this.outFile.writeInt32(this.outFile.tell());
    this.outFile.writeInt32(Std.int(now.float()));
    this.outFile.writeByte(0x1);
    var pathBytes = haxe.io.Bytes.ofString(path);
    this.outFile.writeInt32(pathBytes.length + amount + 2);
    this.outFile.writeString(path);
    this.outFile.writeByte(0);

    reg.file.seek(reg.offset, SeekBegin);
    reg.offset += amount;
    // contents
    var buf = this.buf;
    while (amount > 0) {
      var read = reg.file.readBytes(buf, 0, (amount < buf.length ? amount : buf.length));
      var pos = 0;
      while (pos < read) {
        pos += this.outFile.writeBytes(buf, pos, read - pos);
      }
      amount -= read;
    }
    this.outFile.writeByte(0);
  }

  private function releaseFile(path:String) {
    var ret = this.registry[path];
    if (ret != null) {
      if (ret.file != null) {
        try {
          ret.file.close();
        }
        catch(e:Dynamic) {
          trace('Warning', 'Error while closing file read: $e');
        }
      }
    }
    if (!this.registry.remove(path)) {
      trace('Warning', 'Trying to release $path but it is not in registry');
    }
  }

  public static function checkFile(path:String, andFix:Bool):Bool {
    var file = sys.io.File.read(path, true);
    var offset = 0,
        size = stat(path).size,
        lastOffset = 0;
    var hasProblem = false;
    while (offset < size) {
      var curOffset = file.readInt32();
      if (curOffset != offset) {
        hasProblem = true;
        break;
      }
      file.readInt32(); file.readByte();
      lastOffset = offset;
      offset = file.readInt32() + file.tell();
      file.seek(offset, SeekBegin);
    }
    if (offset != size) {
      hasProblem = true;
    }
    file.close();
    if (hasProblem) {
      trace('Warning', 'Found problem at offset $offset from $path');
      if (!andFix) {
        return false;
      }
      var write = @:privateAccess new sys.io.FileOutput(cpp.NativeFile.file_open(path,"rb+"));
      // consider that the rest of the file is corrupt
      write.seek(lastOffset, SeekBegin);
      write.writeInt32(lastOffset);
      write.writeInt32(Std.int(Utils.fastNow().float()));
      write.writeByte(0x0); // recovery code
      write.writeInt32(size - write.tell() - 4);
      write.close();
      return false;
    }
    return true;
  }

  private function loadRegistry() {
    var path = this.agent.dataDir + '/' + this.agent.hostname + '/config/registry';
    this.registry = new Map();
    if (exists(path)) {
      try {
        var registry:{ lastPrefix:String, safeBytes:Int, reg:Array<{ source:String, offset:Int, inode:Int, device:Int }> } = haxe.Json.parse(sys.io.File.getContent(path));
        if (registry.lastPrefix != null) {
          var path = this.agent.dataDir + '/' + this.agent.hostname + '/data/' + registry.lastPrefix + '.logs';
          // check file
          if (exists(path)) {
            try {
              Utils.truncate(path, registry.safeBytes);
            }
            catch(e:Dynamic) {
              trace('Error', 'Error truncating last file ${registry.lastPrefix}: $e');
            }
            try {
              checkFile(path, true);
            }
            catch(e:Dynamic) {
              trace('Error', 'Error while checking/fixing file $path: $e');
            }
          }
        }

        for (data in registry.reg) {
          var src = Glob.normalizePath(data.source);
          this.registry.set(src, { source:src, offset:data.offset, inode:data.inode, device:data.device });
        }
      }
      catch(e:Dynamic) {
        trace('Error', 'Error while getting latest registry: $e');
      }
    }
  }

  public function loop() {
    if (!this.enabled) {
      trace('Error', 'No enabled log path found');
      this.agent.waitClose();
    } else {
      while(!this.agent.isClosing()) {
        this.watcher.waitOnce();
      }
    }
  }

  private function saveRegistry() {
    var path = this.agent.dataDir + '/' + this.agent.hostname + '/config/registry';
    if (this.outFile != null) {
      this.outFile.flush();
    }
    var data = {
      lastPrefix: this.outPrefix,
      safeBytes: this.outFile != null ? this.outFile.tell() : 0,
      reg: [ for (data in this.registry) (data : RegistryData) ]
    };
    sys.io.File.saveContent( path,  tink.Json.stringify(data) );
  }
}

@:structInit
class RegistryData {
  public var source:String;
  public var offset:Int;
  public var inode:Int;
  public var device:Int;
}

@:structInit
class LiveData extends RegistryData {
  @:optional public var file:sys.io.FileInput;
}

// @:cppFileCode("
// #include <sys/types.h>
// #include <sys/stat.h>
// #include <fcntl.h>
// ")
// class NativeHelpers {
//   public static function openRead(path:String):Int {
//   }
// }
