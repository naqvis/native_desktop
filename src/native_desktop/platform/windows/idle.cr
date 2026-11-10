require "log"
require "./win32_common"

module NativeDesktop::Platform::Idle
  extend self

  def duration : Time::Span
    info = uninitialized Windows::LibUser32::LastInputInfo
    info.cb_size = sizeof(Windows::LibUser32::LastInputInfo).to_u32
    info.tick = 0_u32
    return 0.seconds if Windows::LibUser32.GetLastInputInfo(pointerof(info)) == 0

    elapsed = Windows::LibKernel32.GetTickCount &- info.tick
    (elapsed.to_f64 / 1000.0).seconds
  rescue ex
    Log.warn(exception: ex) { "could not read Windows idle time" }
    0.seconds
  end
end
