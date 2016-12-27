package rtop;
import geo.units.Seconds;
import geo.units.Minutes;

class Globals {
  public static var FILE_INTERVAL:Seconds = new Minutes(10); // we have one new file every 10 minutes
  public static inline var COMPRESS_SIZE_THRESHOLD = 1 * 1024 * 1024; // 1MB
}
