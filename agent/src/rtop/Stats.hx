package rtop;
import rtop.utils.Utils;
import rtop.diskio.DiskIO;
import rtop.format.Intermediary;
import geo.UnixDate;
import geo.units.Seconds;
import haxe.io.Bytes;
import sys.FileSystem.*;

class Stats {
  public var agent(default, null):Agent;
  public var disk(default, null):DiskIO;
  public var net(default, null):Net;
  public var mem(default, null):Mem;
  public var cpu(default, null):Cpu;
  public var processes(default, null):Processes;

  var presetHeader:Bytes;
  var timeOffset:Int;

  var uname:String;

  public function new(agent:Agent) {
    this.agent = agent;
    this.disk = DiskIO.getDiskIO(agent);
    this.net = new Net(agent);
    this.mem = new Mem(agent);
    this.cpu = new Cpu(agent);
    this.processes = new Processes(this);
  }

  public function init() {
    // get net / disks to count how many we have
    this.cpu.init();
    this.mem.init();
    this.uname = try Utils.getSysfsContents( this.agent.procdir + '/version' ) catch(e:Dynamic) null;
    var header:Header = {
      // dataOffset: 0,
      // beatSize: 0,
      // beatSecs: this.agent.beatSecs,

      startTime: Utils.fastNow(),

      net: this.net.init(),
      disks: this.disk.init(),
      diskIsDetailed: this.disk.isDetailed,
      cpus: this.cpu.nCpu,

      totalMemoryBytes: this.mem.memTotal,
      totalSwapBytes: this.mem.swapTotal,

      os: Linux,
      uname: this.uname,
    };

    // var header = new haxe.io.BytesOutput();
    // this.timeOffset = 0;
    // header.writeInt32(0xB347B347);
    // this.timeOffset += 4;
    //
    // header.writeInt16(1); // major version
    // header.writeInt16(0); // major version
    // this.timeOffset += 4;

    this.processes.init();
  }

  public function createBeat(curTime:UnixDate, upTime:Seconds, alsoProcess:Bool) {
    var beat = new Beat();
    this.disk.update();
    this.net.update();
    this.mem.update(beat);
    this.cpu.update();

    if (alsoProcess) {
      this.processes.update();
    }
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
