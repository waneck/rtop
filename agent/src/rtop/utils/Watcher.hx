package rtop.utils;

@:cppFileCode("
#include <unistd.h>
#include <linux/limits.h>
#include <sys/inotify.h>

#define BUF_LEN (10 * (sizeof(struct inotify_event) + NAME_MAX + 1))
")
class Watcher {
  var fd:Int;
  var wds:Map<Int, WatchFlags->String->Int->Void>;

  public function new() {
    this.fd = untyped __cpp__("inotify_init()");
    Utils.checkRetError(this.fd);
    this.wds = new Map();
  }

  public function add(path:String, flags:WatchFlags, cb:WatchFlags->String->Int->Void):Int {
    if (this.fd <= 0) {
      throw 'Watcher is closed';
    }

    var path = cpp.ConstCharStar.fromString(path);
    var wd:Int = untyped __cpp__('inotify_add_watch( {0}, {1}, {2} )', this.fd, path, flagsToInotify(flags));
    Utils.checkRetError(this.fd);
    this.wds[wd] = cb;
    return wd;
  }

  public function remove(wd:Int) {
    if (this.fd <= 0) {
      throw 'Watcher is closed';
    }

    var ret = untyped __cpp__('inotify_rm_watch({0}, {1})', this.fd, wd);
    Utils.checkError(ret);
    this.wds.remove(wd);
  }

  public function close() {
    if (this.fd <= 0) {
      return;
    }

    Utils.checkError(untyped __cpp__('::close({0})', this.fd));
    this.fd = -1;
  }

  public function waitOnce() {
    if (this.fd <= 0) {
      throw 'Watcher is closed';
    }

    untyped __cpp__('char buf[BUF_LEN]');
    cpp.vm.Gc.enterGCFreeZone();
    var numRead = untyped __cpp__('read({0}, buf, BUF_LEN)', this.fd);
    cpp.vm.Gc.exitGCFreeZone();
    if (numRead == 0) {
      throw 'inotify returned 0';
    }
    Utils.checkRetError(numRead);

    var lastError = null;
    untyped __cpp__('char *p = buf');
    while (untyped __cpp__('p < buf + {0}', numRead)) {
      untyped __cpp__('struct inotify_event *event = (struct inotify_event *) p');
      var flags = inotifyToFlags(untyped __cpp__('event->mask'));
      var name = ( untyped __cpp__('event->name') : cpp.ConstCharStar ).toString();
      var wd = untyped __cpp__('event->wd');
      var cookie = untyped __cpp__('event->cookie');
      var fn = this.wds[wd];
      if (fn != null) {
        try {
          fn(flags, name, cookie);
        }
        catch(e:Dynamic) {
          trace('Error', 'Error while executing callback for $name: $e');
          lastError = e;
        }
      } else {
        trace('Warning', 'WD $wd was not found for $name');
      }

      untyped __cpp__('p += sizeof(struct inotify_event) + event->len');
    }
  }

  private function flagsToInotify(flags:WatchFlags):Int {
    var ret:Int = 0;
    if (flags.hasAll(Access)) {
      ret |= untyped __cpp__('IN_ACCESS');
    }
    if (flags.hasAll(Attrib)) {
      ret |= untyped __cpp__('IN_ATTRIB');
    }
    if (flags.hasAll(CloseWrite)) {
      ret |= untyped __cpp__('IN_CLOSE_WRITE');
    }
    if (flags.hasAll(CloseNoWrite)) {
      ret |= untyped __cpp__('IN_CLOSE_NOWRITE');
    }
    if (flags.hasAll(Create)) {
      ret |= untyped __cpp__('IN_CREATE');
    }
    if (flags.hasAll(Delete)) {
      ret |= untyped __cpp__('IN_DELETE');
    }
    if (flags.hasAll(DeleteSelf)) {
      ret |= untyped __cpp__('IN_DELETE_SELF');
    }
    if (flags.hasAll(Modify)) {
      ret |= untyped __cpp__('IN_MODIFY');
    }
    if (flags.hasAll(MoveSelf)) {
      ret |= untyped __cpp__('IN_MOVE_SELF');
    }
    if (flags.hasAll(MovedFrom)) {
      ret |= untyped __cpp__('IN_MOVED_FROM');
    }
    if (flags.hasAll(MovedTo)) {
      ret |= untyped __cpp__('IN_MOVED_TO');
    }
    if (flags.hasAll(Open)) {
      ret |= untyped __cpp__('IN_OPEN');
    }
    if (flags.hasAll(OneShot)) {
      ret |= untyped __cpp__('IN_ONESHOT');
    }
    if (flags.hasAll(OnlyDir)) {
      ret |= untyped __cpp__('IN_ONLYDIR');
    }
    if (flags.hasAll(QueueOverflow)) {
      ret |= untyped __cpp__('IN_Q_OVERFLOW');
    }
    if (flags.hasAll(Unmount)) {
      ret |= untyped __cpp__('IN_UNMOUNT');
    }
    return ret;
  }

  private function inotifyToFlags(flags:Int):WatchFlags {
    var ret:WatchFlags = 0;
    if ((flags & untyped __cpp__('IN_ACCESS')) == untyped __cpp__('IN_ACCESS')) {
      ret |= Access;
    }
    if ((flags & untyped __cpp__('IN_ATTRIB')) == untyped __cpp__('IN_ATTRIB')) {
      ret |= Attrib;
    }
    if ((flags & untyped __cpp__('IN_CLOSE_WRITE')) == untyped __cpp__('IN_CLOSE_WRITE')) {
      ret |= CloseWrite;
    }
    if ((flags & untyped __cpp__('IN_CLOSE_NOWRITE')) == untyped __cpp__('IN_CLOSE_NOWRITE')) {
      ret |= CloseNoWrite;
    }
    if ((flags & untyped __cpp__('IN_CREATE')) == untyped __cpp__('IN_CREATE')) {
      ret |= Create;
    }
    if ((flags & untyped __cpp__('IN_DELETE')) == untyped __cpp__('IN_DELETE')) {
      ret |= Delete;
    }
    if ((flags & untyped __cpp__('IN_DELETE_SELF')) == untyped __cpp__('IN_DELETE_SELF')) {
      ret |= DeleteSelf;
    }
    if ((flags & untyped __cpp__('IN_MODIFY')) == untyped __cpp__('IN_MODIFY')) {
      ret |= Modify;
    }
    if ((flags & untyped __cpp__('IN_MOVE_SELF')) == untyped __cpp__('IN_MOVE_SELF')) {
      ret |= MoveSelf;
    }
    if ((flags & untyped __cpp__('IN_MOVED_FROM')) == untyped __cpp__('IN_MOVED_FROM')) {
      ret |= MovedFrom;
    }
    if ((flags & untyped __cpp__('IN_MOVED_TO')) == untyped __cpp__('IN_MOVED_TO')) {
      ret |= MovedTo;
    }
    if ((flags & untyped __cpp__('IN_OPEN')) == untyped __cpp__('IN_OPEN')) {
      ret |= Open;
    }
    if ((flags & untyped __cpp__('IN_ONESHOT')) == untyped __cpp__('IN_ONESHOT')) {
      ret |= OneShot;
    }
    if ((flags & untyped __cpp__('IN_ONLYDIR')) == untyped __cpp__('IN_ONLYDIR')) {
      ret |= OnlyDir;
    }
    if ((flags & untyped __cpp__('IN_Q_OVERFLOW')) == untyped __cpp__('IN_Q_OVERFLOW')) {
      ret |= QueueOverflow;
    }
    if ((flags & untyped __cpp__('IN_UNMOUNT')) == untyped __cpp__('IN_UNMOUNT')) {
      ret |= Unmount;
    }
    return ret;
  }
}


@:enum abstract WatchFlags(Int) from Int {
  var Access = 0x1;
  var Attrib = 0x2;
  var CloseWrite = 0x4;
  var CloseNoWrite = 0x8;
  var Create = 0x10;
  var Delete = 0x20;
  var DeleteSelf = 0x40;
  var Modify = 0x80;
  var MoveSelf = 0x100;
  var MovedFrom = 0x200;
  var MovedTo = 0x400;
  var Open = 0x800;

  var OneShot = 0x1000;
  var OnlyDir = 0x2000;

  var QueueOverflow = 0x4000;
  var Unmount = 0x8000;

  inline private function t() {
    return this;
  }

  @:op(A|B) inline public function add(f:WatchFlags):WatchFlags {
    return this | f.t();
  }

  inline public function hasAll(flag:WatchFlags):Bool {
    return this & flag.t() == flag.t();
  }

  inline public function hasAny(flag:WatchFlags):Bool {
    return this & flag.t() != 0;
  }
}
