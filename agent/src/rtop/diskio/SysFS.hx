package rtop.diskio;
import geo.units.Seconds;
import rtop.format.Intermediary;
import rtop.utils.Utils;
import sys.FileSystem.*;

class SysFS extends DiskIO {
  var lastValues:Array<{ stamp:Seconds, readIOs:Int, readTicks:Int, writeIOs:Int, writeTicks:Int }> = [];

  public function new(agent:Agent) {
    super(agent);
    this.isDetailed = true;
  }

  override public function update():Array<IoDiskData> {
    var ret = super.update();
    var splitRegex = ~/( |\t|\n)+/g;
    for (i in 0...ret.length) {
      try {
        var name = this.allFs[i].devName,
            stamp = Utils.getUptime();
        var contents = Utils.getSysfsContents( this.agent.sysdir + '/class/block/$name/stat' );
        var stats = splitRegex.split(contents).map(Std.parseInt);
        if (stats[0] == null) {
          stats.shift();
        }
        var readIOs = stats[0],
            readTicks = stats[3],
            writeIOs = stats[4],
            writeTicks = stats[7];
        var lastValue = this.lastValues[i];
        if (lastValue == null) {
          this.lastValues[i] = lastValue = cast { };
        } else {
          ret[i].deltaTimeMS = Std.int(Math.ceil(( (stamp.float() - lastValue.stamp.float()) * 1000 )));
          ret[i].read = readIOs - lastValue.readIOs;
          ret[i].readTicksMS = readTicks - lastValue.readTicks;
          ret[i].write = writeIOs - lastValue.writeIOs;
          ret[i].writeTicksMS = writeTicks - lastValue.writeTicks;
          if (name == 'dm-1') {
            trace(stats);
            trace(name, ret[i].deltaTimeMS,ret[i].read,ret[i].readTicksMS);
            trace(name, ret[i].deltaTimeMS,ret[i].write,ret[i].writeTicksMS);
          }
        }
        lastValue.stamp = stamp;
        lastValue.readIOs = readIOs;
        lastValue.readTicks = readTicks;
        lastValue.writeIOs = writeIOs;
        lastValue.writeTicks = writeTicks;
      }
      catch(e:Dynamic) {
        trace('Warning', 'Error while accessing the sysfs data ${this.agent.sysdir}/class/block/${allFs[i].devName}/stat: $e');
      }
    }
    return ret;
  }
}
