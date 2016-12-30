package rtop;
import geo.units.Seconds;
import rtop.format.Intermediary;
import rtop.utils.Utils;
import sys.FileSystem.*;
import haxe.Int64;

class Processes {
  var agent:Agent;
  var cpu:Cpu;

  var lastProcesses:Map<String, ProcessStats> = new Map();
  var owners:Map<Int, String> = new Map();
  var mark:Int = 0;

  var lastStamp:Seconds;
  var lastJiffies:Int64;
  var currentMark = 0;

  public function new(stats:Stats) {
    this.agent = stats.agent;
    this.cpu = stats.cpu;
  }

  public function init() {
    this.lastJiffies = this.cpu.totalJiffies;
    this.lastStamp = this.cpu.time;
  }

  public function update():ProcessesData {
    var upTime = Utils.getUptime();
    var ret:ProcessesData = {
      upTime:upTime,
      namesAndOwners:[],
      processesData:[],
    };

    var regex = ~/\((.*)\) /;
    try {
      var mark = ++this.mark;
      var procdir = this.agent.procdir;
      for (file in readDirectory(procdir)) {
        var path = '$procdir/$file';
        if (isDirectory(path) && Std.string(Std.parseInt(file)) == file && exists('$path/stat')) {
          var all = Utils.getSysfsContents('$path/stat');
          if (!regex.match(all)) {
            trace('Error', 'Cannot find process name at: $all');
            continue;
          }
          var procName = regex.matched(1),
              data = regex.matchedRight().split(' ');
          var utime = Int64.parseString(data[11]),
              stime = Int64.parseString(data[12]),
              numThreads = Std.parseInt(data[17]),
              state = data[0];
        }
      }
    }
    catch(e:Dynamic) {
      trace('Error', 'Error while updating processes: $e');
    }
    return ret;
  }

  private function getOwner(uid:Int):String {
    var ret = owners[uid];
    if (ret != null) {
      return ret;
    }
    ret = ProcessHelpers.getUserName(uid);
    owners[uid] = ret;
    return ret;
  }
}

@:structInit
class ProcessStats {
  public var name:String;
  public var owner:String;
  public var userJiffies:Int64;
  public var systemJiffies:Int64;
  public var memoryBytes:Int64;
  public var count:Int; //uint8
  public var threads:Int;
  public var mark:Int;

  public function checkMark(mark:Int) {
    if (mark != this.mark) {
      this.mark = mark;
      this.userJiffies = 0;
      this.systemJiffies = 0;
      this.memoryBytes = 0;
      this.count = 0;
      this.threads = 0;
    }
  }
}

@:cppFileCode("
#include <stdlib.h>
#include <pwd.h>
")
private class ProcessHelpers {
  public static function getUserName(uid:Int):String {
    untyped __cpp__("struct passwd *pw = getpwuid({0})", uid);
    if (untyped __cpp__("pw == 0")) { return null; }
    return ( untyped __cpp__("pw->pw_name") : cpp.ConstCharStar ).toString();
  }
}
