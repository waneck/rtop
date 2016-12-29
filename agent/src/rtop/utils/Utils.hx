package rtop.utils;
import geo.UnixDate;
import geo.units.Seconds;
import sys.FileSystem.*;

@:cppFileCode("
#include <unistd.h>
#include <string.h>
#include <linux/limits.h>
#include <errno.h>
#include <time.h>
")
class Utils {
  inline public static function fastNow():UnixDate {
    return untyped __global__.__hxcpp_date_now();
  }

  public static function getUptime():Seconds {
    untyped __cpp__("struct timespec tp");
    var res = untyped __cpp__("clock_gettime(CLOCK_MONOTONIC, &tp)");
    checkError(res);
    var secs:Float = untyped __cpp__("((double) tp.tv_sec) + (((double) tp.tv_nsec) / 1000000000.0)");
    return secs;
  }

  public static function getPathPart(date:UnixDate) {
    // first normalize
    var normalized = new UnixDate(Math.floor(date.getTime().float() / Globals.FILE_INTERVAL.float()) * Globals.FILE_INTERVAL.float());
    return normalized.withParts(function(year, month, dayMonth, hour, min, sec) {
      return '$year-${month.toInt()}/$dayMonth/$hour-$min-$sec';
    });
  }

  public static function getDirPart(date:UnixDate) {
    // first normalize
    var normalized = new UnixDate(Math.floor(date.getTime().float() / Globals.FILE_INTERVAL.float()) * Globals.FILE_INTERVAL.float());
    return normalized.withParts(function(year, month, dayMonth, hour, min, sec) {
      return '$year-${month.toInt()}/$dayMonth';
    });
  }

  public static function getError() {
    return ( untyped __cpp__('strerror(errno)') : cpp.ConstCharStar ).toString();
  }

  public static function checkError(err:Int) {
    if (err == 0) {
      return;
    }
    var curErr = err > 0 ? err : untyped __cpp__("errno");
    throw ( untyped __cpp__('strerror({0})', curErr) : cpp.ConstCharStar ).toString();
  }

  public static function checkRetError(err:Int) {
    if (err >= 0) {
      return;
    }
    throw ( untyped __cpp__('strerror(errno)') : cpp.ConstCharStar ).toString();
  }

  public static function symlink(src:String, dest:String):Void {
    var src = cpp.ConstCharStar.fromString(src),
        dest = cpp.ConstCharStar.fromString(dest);
    var ret = untyped __cpp__("::symlink({0},{1})", src, dest);
    checkError(ret);
  }

  /**
    Reads a link `src`, and returns where it's pointing to. Returns null if target file is not a linu, but exists
   **/
  public static function readlink(src:String):Null<String> {
    var src = cpp.ConstCharStar.fromString(src);

    var ret:cpp.ConstCharStar = null;
    untyped __cpp__('char buf[PATH_MAX + 1]');
    untyped __cpp__('buf[PATH_MAX] = 0');
    untyped __cpp__('{0} = buf', ret);
    var num = untyped __cpp__("::readlink({0}, buf, PATH_MAX)", src);
    if (num < 0) {
      if (untyped __cpp__("errno == EINVAL")) {
        return null;
      }
      checkRetError(num);
    }
    untyped __cpp__('buf[{0}] = 0', num);
    return ret.toString();
  }

  public static function getHostName() {
    var str:cpp.ConstCharStar = null;
    untyped __cpp__('char buf[256]');
    untyped __cpp__('{0} = buf', str);
    var result:Int = untyped __cpp__('gethostname(buf, 255)');
    checkError(result);
    return str.toString();
  }

  public static function truncate(path:String, length:Int) {
    var path = cpp.ConstCharStar.fromString(path);

    var ret = untyped __cpp__("::truncate({0}, {1})", path, length);
    checkError(ret);
  }

  public static function getSysfsContents(path:String):String {
    var file = sys.io.File.read(path, true);
    var ret = file.readAll().toString();
    file.close();
    return ret;
  }
}
