package rtop;
import rtop.utils.Utils;
import rtop.diskio.DiskIO;
import geo.UnixDate;
import geo.units.Seconds;
import haxe.io.Bytes;
import sys.FileSystem.*;

class Stats {
  var agent:Agent;
  var net:Array<String>;
  var disks:Array<String>;

  var presetHeader:Bytes;
  var timeOffset:Int;

  var disk:DiskIO;

  public function new(agent:Agent) {
    this.agent = agent;
    this.disk = DiskIO.getDiskIO(agent);
  }

  public function init() {
    // get net / disks to count how many we have
    this.getNet();
    this.getDisks();

    var header = new haxe.io.BytesOutput();
    this.timeOffset = 0;
    header.writeInt32(0xB347B347);
    this.timeOffset += 4;

    header.writeInt16(1); // major version
    header.writeInt16(0); // major version
    this.timeOffset += 4;
  }

  private function getNet() {
    this.net = [];
    for (iface in readDirectory(this.agent.sysdir + '/class/net')) {
      try {
        var flags = Std.parseInt(Utils.getSysfsContents(this.agent.sysdir + '/class/net/$iface/flags'));
        if (flags & NetUp == 0) { // interface is not up
          continue;
        }
        if (flags & NetLoopback != 0) { // interface is loopback
          continue;
        }
        this.net.push(iface);
      }
      catch(e:Dynamic) {
        trace('Warning', 'Error when ccessing inteface $iface: $e');
      }
    }
  }

  private function getDisks() {
    this.disk.init();
  }

  public function createBeat(curTime:UnixDate, upTime:Seconds, alsoProcess:Bool) {
    this.disk.update();
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

// class Header {
//   public var magic:Int64; // 0xB351D35BEA755555
//
//   public var vmajor:Int; // int16
//   public var vminor:Int; // int16
//
//   /**
//     Starting from `dataOffset`, there will be new data
//    **/
//   public var dataOffset:Int;
//   public var beatSize:Int;
//   public var beatSecs:Seconds;
//
//   /**
//     The start time where this file started
//    **/
//   public var startTime:UnixDate;
//
//   public var net:Array<String>;
//   public var disks:Array<{ path:String, size:Int64 }>;
//
//   public var totalMemoryBytes:Int64;
//   public var totalSwapBytes:Int64;
//
//   public var os:OSString;
//   public var uname:String;
// }
