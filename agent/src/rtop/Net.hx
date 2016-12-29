package rtop;
import geo.units.Seconds;
import rtop.format.Intermediary;
import rtop.utils.Utils;
import sys.FileSystem.*;

class Net {
  public var interfaces(default, null):Array<String>;

  var agent:Agent;
  var lastValues:Array<{ stamp:Seconds, read:Int, write:Int }> = [];

  public function new(agent:Agent) {
    this.agent = agent;
  }

  public function init():Array<String> {
    this.interfaces = [];
    for (iface in readDirectory(this.agent.sysdir + '/class/net')) {
      try {
        var flags = Std.parseInt(Utils.getSysfsContents(this.agent.sysdir + '/class/net/$iface/flags'));
        if (flags & NetUp == 0) { // interface is not up
          continue;
        }
        if (flags & NetLoopback != 0) { // interface is loopback
          continue;
        }
        this.interfaces.push(iface);
      }
      catch(e:Dynamic) {
        trace('Warning', 'Error when ccessing inteface $iface: $e');
      }
    }
    this.update();
    return this.interfaces;
  }

  public function update():Array<IoData> {
    var ret:Array<IoData> = [];
    for (i in 0...this.interfaces.length) {
      ret[i] = { deltaTimeMS: 0, read:0, write:0 };
      try {
        var name = this.interfaces[i],
            stamp = Utils.getUptime();
        var readBytes = Std.parseInt(Utils.getSysfsContents( this.agent.sysdir + '/class/net/$name/statistics/rx_bytes' )),
            writeBytes = Std.parseInt(Utils.getSysfsContents(this.agent.sysdir + '/class/net/$name/statistics/tx_bytes' ));
        var lastValue = this.lastValues[i];
        if (lastValue == null) {
          this.lastValues[i] = lastValue = cast { };
        } else {
          ret[i].deltaTimeMS = Std.int(Math.ceil(( (stamp.float() - lastValue.stamp.float()) * 1000 )));
          ret[i].read = readBytes - lastValue.read;
          ret[i].write = writeBytes - lastValue.write;
          trace(name,ret[i].deltaTimeMS,ret[i].read,ret[i].write);
        }
        lastValue.stamp = stamp;
        lastValue.read = readBytes;
        lastValue.write = writeBytes;
      }
      catch(e:Dynamic) {
        trace('Warning', 'Error while accessing the sysfs data: $e');
      }
    }
    return ret;
  }
}

@:enum abstract NetFlags(Int) from Int to Int {
  var NetUp = 1<<0;
  var NetBroadcast = 1<<1;
  var NetDebug = 1<<2;
  var NetLoopback = 1<<3;
  var NetPointopoint = 1<<4;
  var NetNotrailers = 1<<5;
  var NetRunning = 1<<6;
  var NetNoarp = 1<<7;
  var NetPromisc = 1<<8;
  var NetAllmulti = 1<<9;
  var NetMaster = 1<<10;
  var NetSlave = 1<<11;
  var NetMulticast = 1<<12;
  var NetPortsel = 1<<13;
  var NetAutomedia = 1<<14;
  var NetDynamic = 1<<15;
  var NetLower_up = 1<<16;
  var NetDormant = 1<<17;
  var NetEcho = 1<<18;

  inline public function int() {
    return this;
  }

  @:op(A|B) inline public function add(other:NetFlags) {
    return this | other.int();
  }
}
