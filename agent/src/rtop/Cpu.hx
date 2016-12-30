package rtop;
import geo.units.Seconds;
import rtop.format.Intermediary;
import rtop.utils.Utils;
import sys.FileSystem.*;
import haxe.Int64;

using StringTools;

class Cpu {
  public var nCpu:Int;
  public var totalJiffies(default, null):Int64;
  public var time(default, null):Seconds;
  var stats:Array<CpuStats> = [];
  var agent:Agent;

  public function new(agent:Agent) {
    this.agent = agent;
  }

  public function init() {
    try {
      var first = true;
      var time = Utils.getUptime();
      for (line in Utils.getSysfsContents(this.agent.procdir + '/stat').split('\n')) {
        if (first) {
          first = false;
          continue;
        }
        if (!line.startsWith('cpu')) {
          break;
        }
        trace(line);
        var lineSplit = line.split(' ');
        var user = Int64.parseString(lineSplit[1]) + Int64.parseString(lineSplit[2]),
            system = Int64.parseString(lineSplit[3]),
            idle = Int64.parseString(lineSplit[4]),
            other = Int64.parseString(lineSplit[5]) + Int64.parseString(lineSplit[6]) + Int64.parseString(lineSplit[7]);
        trace({ time:time, user:user, system:system, idle:idle, other:other });
        this.stats.push({ time:time, user:user, system:system, idle:idle, other:other });
      }
    }
    catch(e:Dynamic) {
      trace('Error', 'Error while getting CPU information: $e');
    }
    this.nCpu = this.stats.length;
  }

  public function update():Array<CpuData> {
    var ret:Array<CpuData> = [];
    var time = Utils.getUptime(),
        i = -1;
    try {
      var first = true;
      for (line in Utils.getSysfsContents(this.agent.procdir + '/stat').split('\n')) {
        if (!line.startsWith('cpu')) {
          break;
        }
        var lineSplit = line.split(' ');
        if (first) {
          var total:Int64 = 0;
          for (i in 1...8) {
            total += Int64.parseString(lineSplit[i]);
          }
          this.totalJiffies = total;
          this.time = time;
          trace(totalJiffies);
          first = false;
          continue;
        }
        ++i;
        var lastData = this.stats[i];
        var user = Int64.parseString(lineSplit[1]) + Int64.parseString(lineSplit[2]),
            system = Int64.parseString(lineSplit[3]),
            idle = Int64.parseString(lineSplit[4]),
            other = Int64.parseString(lineSplit[5]) + Int64.parseString(lineSplit[6]) + Int64.parseString(lineSplit[7]);
        ret[i] = {
          deltaTimeMS: Std.int( (time.float() - lastData.time.float()) * 1000 ),
          user: Int64.toInt(user - lastData.user),
          system: Int64.toInt(system - lastData.system),
          idle: Int64.toInt(idle - lastData.idle),
          other: Int64.toInt(other - lastData.other),
        };
        trace({
          deltaTimeMS: Std.int( (time.float() - lastData.time.float()) * 1000 ),
          user: Int64.toInt(user - lastData.user),
          system: Int64.toInt(system - lastData.system),
          idle: Int64.toInt(idle - lastData.idle),
          other: Int64.toInt(other - lastData.other),
        });
        lastData.time = time;
        lastData.user = user;
        lastData.system = system;
        lastData.idle = idle;
        lastData.other = other;
      }
    }
    catch(e:Dynamic) {
      trace('Error', 'Error while getting CPU information: $e');
    }
    return ret;
  }
}

@:structInit
class CpuStats {
  public var time:Seconds;
  public var user:Int64; // jiffies
  public var system:Int64;
  public var idle:Int64;
  public var other:Int64;
}
