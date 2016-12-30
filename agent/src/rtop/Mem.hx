package rtop;
import cpp.Int64;
import geo.units.Seconds;
import rtop.format.Intermediary;
import rtop.utils.Utils;
import sys.FileSystem.*;

using StringTools;

class Mem {
  public var memTotal:Int64;
  public var swapTotal:Int64;
  var agent:Agent;

  public function new(agent:Agent) {
    this.agent = agent;
  }

  public function init() {
    try {
      var digits = ~/(\d+)/;
      for (data in Utils.getSysfsContents(this.agent.procdir + '/meminfo').split('\n')) {
        if (data.startsWith('MemTotal:') && digits.match(data)) {
          this.memTotal = cast haxe.Int64.parseString( digits.matched(1) ) * (1024);
        } else if (data.startsWith('SwapTotal:') && digits.match(data)) {
          this.swapTotal = cast haxe.Int64.parseString( digits.matched(1) ) * (1024);
        }
      }
    }
    catch(e:Dynamic) {
      trace('Error', 'Error while getting memory info: $e');
    }
  }

  public function update(beat:Beat) {
    try {
      var digits = ~/(\d+)/;
      for (data in Utils.getSysfsContents(this.agent.procdir + '/meminfo').split('\n')) {
        if (data.startsWith('MemFree:') && digits.match(data)) {
          beat.freeMemoryBytes = cast haxe.Int64.parseString( digits.matched(1) ) * (1024);
        } else if (data.startsWith('SwapFree:') && digits.match(data)) {
          beat.freeSwapBytes = cast haxe.Int64.parseString( digits.matched(1) ) * (1024);
          trace(beat.freeSwapBytes);
        }
      }
    }
    catch(e:Dynamic) {
      trace('Error', 'Error while getting memory info: $e');
    }
  }
}
