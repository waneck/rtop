package rtop;
import rtop.utils.Utils;
import rtop.diskio.DiskIO;
import geo.UnixDate;
import geo.units.Seconds;
import haxe.io.Bytes;
import sys.FileSystem.*;

class Stats {
  var agent:Agent;

  var presetHeader:Bytes;
  var timeOffset:Int;

  var disk:DiskIO;
  var net:Net;

  public function new(agent:Agent) {
    this.agent = agent;
    this.disk = DiskIO.getDiskIO(agent);
    this.net = new Net(agent);
  }

  public function init() {
    // get net / disks to count how many we have
    this.net.init();
    this.disk.init();

    var header = new haxe.io.BytesOutput();
    this.timeOffset = 0;
    header.writeInt32(0xB347B347);
    this.timeOffset += 4;

    header.writeInt16(1); // major version
    header.writeInt16(0); // major version
    this.timeOffset += 4;
  }

  public function createBeat(curTime:UnixDate, upTime:Seconds, alsoProcess:Bool) {
    this.disk.update();
    this.net.update();
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
