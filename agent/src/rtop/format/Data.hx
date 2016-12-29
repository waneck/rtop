package rtop.format;
import geo.UnixDate;
import geo.units.Seconds;
import rtop.format.Intermediary;

typedef Data = {
  public var version:String;

  public var os:OSString;
  public var uname:String;

  public var hostname:String;

  public var totalMemoryBytes:Float;
  public var totalSwapBytes:Float;

  public var netNames:Array<String>;
  public var diskPaths:Array<String>;
  public var logPaths:Array<String>;

  public var beats:Array<OutBeat>;
}

typedef OutBeat = {
  public var date:UnixDate;
  public var upTime:Seconds;
  @:optional public var processes:Array<OutProcesses>;
  @:optional public var net:Array<OutNet>;
  @:optional public var disks:Array<OutDisk>;
  @:optional public var memory:OutMemory;
  @:optional public var cpu:OutCPU;
  @:optional public var logs:Array<Null<String>>;
}

typedef OutProcesses = {
  public var name:String;
  public var owner:String;
  public var mem:ExportBytes;
  public var cpu:Float; // 0 - 1
};

typedef OutNet = {
  public var r:SmallBytes; // read
  public var w:SmallBytes; // write
  public var delta:Seconds;
}

typedef OutDisk = { > OutNet,
  public var free:ExportBytes;
}

typedef OutMemory = {
  public var freeMem:ExportBytes;
  public var freeSwap:ExportBytes;
}

typedef OutCPU = {
  public var user:Int; // cpuUser * 10000 / cpuTotal
  public var system:Int;
  public var stolen:Int;
  public var ioWait:Int;
}
