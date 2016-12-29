package rtop.diskio;
import rtop.format.Intermediary;
import rtop.utils.Utils;
import cpp.ConstCharStar;
import cpp.UInt64;
import cpp.Int64;
import sys.FileSystem.*;

using StringTools;

class DiskIO {
  public var isDetailed(default, null):Bool;
  var agent:Agent;
  var allFs:Array<{ fsPath:String, dev:String, devName:String }> = [];

  function new(agent:Agent) {
    this.agent = agent;
    this.isDetailed = false;
  }

  public function init():Array<DiskData> {
    var disks:Array<DiskData> = [];
    var mountFile = exists('/etc/mtab') ? '/etc/mtab' : agent.procDir + '/mounts';
    for (data in DiskUtils.getMountData(mountFile)) {
      if (data.fsname.startsWith('/dev/')) {
        var stats = DiskUtils.getFsStats(data.dir);
        disks.push({ path:data.fsname, size: stats.total });
        this.allFs.push({ fsPath:data.dir, dev:data.fsname, devName:data.fsname.split('/').pop() });
      }
    }
    trace(this.allFs);
    return disks;
    update();
  }

  public function update():Array<IoDiskData> {
    var ret:Array<IoDiskData> = [];
    for (fs in this.allFs) {
      var cur:IoDiskData = { read:0, write:0, deltaTimeMS:0 };
      try {
        var stats = DiskUtils.getFsStats(fs.fsPath);
        cur.freeSpaceBytes = stats.free;
      } catch(e:Dynamic) {
      }
      ret.push(cur);
    }

    return ret;
  }

  public static function getDiskIO(agent:Agent):DiskIO {
    trace('here');
    if (exists(agent.sysdir + '/class/block') && isDirectory(agent.sysdir + '/class/block')) {
      trace('sysfs');
      return new SysFS(agent);
    } else {
      trace('whaa');
      return new DiskIO(agent);
    }
  }
}

@:cppFileCode("
#include <stdio.h>
#include <mntent.h>
#include <sys/statvfs.h>
")
private class DiskUtils {
  public static function getMountData(path:String):Array<{ fsname:String, dir:String, type:String, opts:String }> {
    var ret = [];
    var path:ConstCharStar = ConstCharStar.fromString(path);
    untyped __cpp__('FILE *stream = setmntent({0}, "r")', path);
    var isNull = untyped __cpp__('stream == 0');
    if (isNull) {
      throw 'Cannot open mount path: $path';
    }
    untyped __cpp__('struct mntent *ent');
    while (untyped __cpp__("0 != (ent = getmntent(stream))")) {
      var fsname:ConstCharStar = untyped __cpp__("ent->mnt_fsname"),
          dir:ConstCharStar = untyped __cpp__("ent->mnt_dir"),
          type:ConstCharStar = untyped __cpp__("ent->mnt_type"),
          opts:ConstCharStar = untyped __cpp__("ent->mnt_opts");
      ret.push({ fsname:fsname.toString(), dir:dir.toString(), type:type.toString(), opts:opts.toString() });
    }
    untyped __cpp__("endmntent(stream)");
    return ret;
  }

  public static function getFsStats(path:String):{ total:UInt64, free:UInt64 } {
    var path:ConstCharStar = ConstCharStar.fromString(path);
    untyped __cpp__("struct statvfs buf");
    var err = untyped __cpp__("statvfs({0}, &buf)", path);
    Utils.checkError(err);
    var free:UInt64 = untyped __cpp__("(unsigned long long) buf.f_bsize * buf.f_bfree"),
        total:UInt64 = untyped __cpp__("(unsigned long long) buf.f_bsize * buf.f_blocks");
    return { total:total, free:free };
  }
}
