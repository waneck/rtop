package rtop.utils;
import geo.UnixDate;

@:cppFileCode("
#include <unistd.h>
#include <string.h>
#include <errno.h>")
class Utils {
  inline public static function fastNow():UnixDate {
    return untyped __global__.__hxcpp_date_now();
  }

  public static function getPathPart(date:UnixDate, isLocal:Bool) {
    // first normalize
    var normalized = new UnixDate(Math.floor(date.getTime().float() / Globals.FILE_INTERVAL.float()) * Globals.FILE_INTERVAL.float());
    return normalized.withParts(function(year, month, dayMonth, hour, min, sec) {
      var dir = isLocal ? '_' : '/';
      return '$year-${month.toInt()}$dir$dayMonth$dir$hour-$min-$sec';
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
    throw ( untyped __cpp__('strerror({0})', err) : cpp.ConstCharStar ).toString();
  }

  public static function checkRetError(err:Int) {
    if (err >= 0) {
      return;
    }
    throw ( untyped __cpp__('strerror({0})', err) : cpp.ConstCharStar ).toString();
  }

  public static function getHostName() {
    var str:cpp.ConstCharStar = null;
    untyped __cpp__('char buf[256]');
    untyped __cpp__('{0} = buf', str);
    var result:Int = untyped __cpp__('gethostname(buf, 255)');
    checkError(result);
    return str.toString();
  }
}
