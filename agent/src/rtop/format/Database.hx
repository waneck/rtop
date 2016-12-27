package rtop.format;

class Database {

  public function new() {
  }

  public function query(select:Array<Select>, filter:Array<Filter>) {
  }
}

enum Select {
  Process(?id:{ name:String, owner:String });
  Net(?name:String);
  Disk(?name:String);
  Memory;
  CPU;
  Logs;
}

enum Filter {
  Time(?start:UnixDate, ?end:UnixDate);
  Limit(offset:Int, nBeats:Int);
}
