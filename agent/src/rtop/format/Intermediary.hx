package rtop.format;
import geo.UnixDate;
import geo.units.Seconds;
import cpp.Int64;

@:structInit
class Header {
  public var magic:Int64; // 0xB351D35BEA755555

  public var vmajor:Int; // int16
  public var vminor:Int; // int16

  /**
    Starting from `dataOffset`, there will be new data
   **/
  public var dataOffset:Int;
  public var beatSize:Int;
  public var beatSecs:Seconds;

  /**
    The start time where this file started
   **/
  public var startTime:UnixDate;

  public var net:Array<String>;
  public var disks:Array<IoDiskData>;
  public var diskIsDetailed:Bool;

  public var totalMemoryBytes:Int64;
  public var totalSwapBytes:Int64;

  public var os:OSString;
  public var uname:String;
}

@:structInit
class DiskData {
  public var path:String;
  public var size:Int64;
}

@:enum abstract OSString(String) {
  // only supported linux for now
  var Linux = "linux";
}

@:structInit
class Beat {
  public var time:UnixDate;
  public var upTime:Seconds;

  public var net:Array<IoData>;
  public var disks:Array<DiskData>;

  public var freeMemoryBytes:Int64;
  public var freeSwapBytes:Int64;

  public var cpuUser:Int; // int16 - cpuUser * 10000 / cpuTotal
  public var cpuSystem:Int; // int16
  public var cpuStolen:Int; // int16
  public var cpuIOWait:Int; // int16

  public var processOffset:Int;
  public var processLen:Int;

  public var logOffset:Int;
  public var logSize:Int;

}

@:structInit
class IoData {
  public var read:Int;
  public var write:Int;
  public var deltaTimeMS:Int;
}

@:structInit
class IoDiskData extends IoData {
  public var freeSpaceBytes:Int64;
  public var readTicksMS:Int;
  public var writeTicksMS:Int;
}

@:structInit
class ProcessesData {
  public var upTime:Seconds;
  public var maxCpuAmount:Int64;
  public var namesAndOwners:Array<NameAndOwner>;
  public var processesData:Array<ProcessData>;
}

@:structInit
class NameAndOwner {
  public var name:String;
  public var owner:String;
}

@:structInit
class ProcessData {
  public var cpuAmount:Int64;
  public var memoryBytes:Int64;
  public var count:Int; //uint8
  public var mark:Int; //uint8
}

@:structInit
class LogsFragment {
  public var logs:Array<LogFragment>;
}

@:structInit
class LogFragment {
  public var logPath:String;
  public var logs:String;
}
