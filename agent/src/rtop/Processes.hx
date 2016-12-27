package rtop;
import cpp.UInt8;

class Processes {
  public var curCpuUnits(default, null):Int = 0;
  public var lastCpuUnits(default, null):Int = 0;
  var m_current:Map<String, ProcessData> = new Map();
  var m_mark:UInt8;

  public function new() {
  }

  public function update() {
    var mark = ++m_mark;
    this.lastCpuUnits = this.curCpuUnits;
  }
}

@:structInit
class ProcessData {
  public var cpuAmount:Int64;
  public var memoryBytes:Int64;
  public var name:String;
  public var owner:String;
  public var count:UInt8;
  public var mark:UInt8;
}
