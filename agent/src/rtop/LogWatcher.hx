package rtop;
import geo.UnixDate;
import rtop.utils.Glob;
import rtop.utils.Utils;
import rtop.utils.Watcher;
import sys.FileSystem.*;

using StringTools;

class LogWatcher {
  var m_agent:Agent;
  var m_watcher:Watcher;
  var m_registry:Map<String, LiveData>;
  var m_enabled:Bool;
  var m_buf:haxe.io.Bytes;
  var m_outFile:sys.io.FileOutput;
  var m_outPrefix:String;

  public function new(agent:Agent) {
    m_agent = agent;
    m_watcher = new Watcher();
    m_buf = haxe.io.Bytes.alloc(m_agent.bufSize);
    this.loadRegistry();
  }

  public function init() {
    // cleanup registry
    var toDelete = [];
    for (registry in m_registry) {
      var found = false;
      for (logPath in m_agent.m_logPaths) {
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
      m_registry.remove(del);
    }

    // start watching
    var found = false;
    for (logPath in m_agent.m_logPaths) {
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
      wd = m_watcher.add(logPath.path, Modify | MovedFrom | MovedTo | Delete | DeleteSelf, function(flags, name, cookie) {
        if (!isDirectory('$path/$name') && (logPath.pattern == null || logPath.pattern.match(name).exact)) {
          if (flags.hasAny(Modify | MovedTo)) {
            updateFile(Glob.normalizePath('${path}/$name'), flags.hasAny(Delete | MovedFrom));
          } else if (flags.hasAny(Delete | MovedFrom)) {
            updateFile(Glob.normalizePath('${path}/$name'), true);
          }
        }

        if (flags.hasAll(DeleteSelf)) {
          m_watcher.remove(wd);
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
      wd = m_watcher.add(m_agent.dataDir + '/' + m_agent.hostname + '/current', Create, function(_,_,_) {
        trace('new file created');
        this.saveRegistry();
      });
    }

    m_enabled = found;
  }

  private function updateFile(path:String, reset:Bool) {
    var reg = m_registry[path];

    var size = -1;
    var data = reset ? null : try stat(path) catch(e:Dynamic) { trace('Error', 'Stat $path failed: $e'); null; };

    if (reg == null) {
      if (data == null) {
        releaseFile(path);
        return;
      }
      // create a new one
      m_registry[path] = (reg = { source:path, offset:0, inode:data.ino, device:data.dev });
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
    if (m_agent.maxSingleLogKB > 0 && amount > m_agent.maxSingleLogKB * 1024) {
      trace('Warning', 'File $path is bigger than maximum single log update. Capping...');
      amount = Std.int(m_agent.maxSingleLogKB * 1024);
      reg.offset = size - amount;
      isComplete = false;
    }

    trace(amount, reg.offset, size);

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
    trace(nowPath, m_outPrefix);
    if (m_outPrefix == null) {
      m_outPrefix = nowPath;
      m_outFile = m_agent.createFileFromPart(nowPath, '.logs');
    } else if (nowPath != m_outPrefix) {
      m_outFile.close();
      m_outFile = null;
      this.saveRegistry();
      m_agent.uploadFinalFile( m_outPrefix + '.logs', true );
      m_outPrefix = nowPath;
      m_outFile = m_agent.createFileFromPart(nowPath, '.logs');
    }

    // header
    m_outFile.writeByte(0x75);
    m_outFile.writeInt32(Std.int(now.float()));
    m_outFile.writeString(path);
    m_outFile.writeByte(0);
    m_outFile.writeInt32(amount + 1);

    reg.file.seek(reg.offset, SeekBegin);
    reg.offset += amount;
    // contents
    var buf = m_buf;
    while (amount > 0) {
      trace(path, size, amount);
      var read = reg.file.readBytes(buf, 0, (amount < buf.length ? amount : buf.length));
      var pos = 0;
      while (pos < read) {
        pos += m_outFile.writeBytes(buf, pos, read - pos);
      }
      amount -= read;
    }
    m_outFile.writeByte(0);
  }

  private function releaseFile(path:String) {
    var ret = m_registry[path];
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
    if (!m_registry.remove(path)) {
      trace('Warning', 'Trying to release $path but it is not in registry');
    }
  }

  private function loadRegistry() {
    var path = m_agent.dataDir + '/' + m_agent.hostname + '/config/registry';
    m_registry = new Map();
    if (exists(path)) {
      try {
        var registry:{ lastPrefix:String, safeBytes:Int, reg:Array<{ source:String, offset:Int, inode:Int, device:Int }> } = haxe.Json.parse(sys.io.File.getContent(path));
        if (registry.lastPrefix != null) {
          try {
            Utils.truncate(m_agent.dataDir + '/' + m_agent.hostname + '/data/' + registry.lastPrefix + '.logs', registry.safeBytes);
          }
          catch(e:Dynamic) {
            trace('Error', 'Error truncating last file ${registry.lastPrefix}: $e');
          }
        }

        for (data in registry.reg) {
          var src = Glob.normalizePath(data.source);
          m_registry.set(src, { source:src, offset:data.offset, inode:data.inode, device:data.device });
        }
      }
      catch(e:Dynamic) {
        trace('Error', 'Error while getting latest registry: $e');
      }
    }
  }

  public function loop() {
    if (!m_enabled) {
      trace('Error', 'No enabled log path found');
      m_agent.waitClose();
    } else {
      while(!m_agent.isClosing()) {
        m_watcher.waitOnce();
      }
    }
  }

  private function saveRegistry() {
    var path = m_agent.dataDir + '/' + m_agent.hostname + '/config/registry';
    if (m_outFile != null) {
      m_outFile.flush();
    }
    var data = {
      lastPrefix: m_outPrefix,
      safeBytes: m_outFile != null ? m_outFile.tell() : 0,
      reg: [ for (data in m_registry) (data : RegistryData) ]
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
