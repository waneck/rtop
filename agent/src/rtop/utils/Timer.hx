package rtop.utils;

@:cppFileCode("
#include <sys/timerfd.h>
#include <unistd.h>
#include <stdint.h>
")
class Timer {
  var fd:Int;

  public function new(realTime:Bool) {
    this.fd = untyped __cpp__("timerfd_create({0} ? CLOCK_REALTIME : CLOCK_MONOTONIC, TFD_CLOEXEC)", realTime);
    Utils.checkRetError(this.fd);
  }

  public function set(seconds:Int, nanoSeconds:Int, ?initialSeconds:Int, ?initialNanoSeconds:Int, absolute:Bool) {
    if (this.fd <= 0) {
      throw 'Timer is closed';
    }
    var initialSeconds = initialSeconds == null ? seconds : initialSeconds;
    var initialNanoSeconds = initialNanoSeconds == null ? nanoSeconds : initialNanoSeconds;

    untyped __cpp__("struct itimerspec spec");
    untyped __cpp__("spec.it_interval.tv_sec = {0}", seconds);
    untyped __cpp__("spec.it_interval.tv_nsec = {0}", nanoSeconds);
    untyped __cpp__("spec.it_value.tv_sec = {0}", initialSeconds);
    untyped __cpp__("spec.it_value.tv_nsec = {0}", initialNanoSeconds);
    var res = untyped __cpp__("timerfd_settime({0}, {1} ? TFD_TIMER_ABSTIME : 0, &spec, 0)", this.fd, absolute);
    Utils.checkError(res);
  }

  public function wait():Int {
    if (this.fd <= 0) {
      throw 'Timer is closed';
    }

    var exp:cpp.UInt64 = 0;
    cpp.vm.Gc.enterGCFreeZone();
    var s = untyped __cpp__("read({0}, &{1}, sizeof(uint64_t))", this.fd, exp);
    cpp.vm.Gc.exitGCFreeZone();
    if (s != untyped __cpp__("sizeof(uint64_t)")) {
      throw 'read failure: ' + Utils.getError();
    }
    return untyped __cpp__("((int) {0})", exp);
  }

  public function close() {
    if (this.fd <= 0) {
      return;
    }

    Utils.checkError(untyped __cpp__('::close({0})', this.fd));
    this.fd = -1;
  }
}
