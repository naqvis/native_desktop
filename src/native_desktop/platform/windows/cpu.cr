require "./win32_common"

module NativeDesktop::Platform::CPU
  extend self

  def times : CPUTimes
    idle = uninitialized Windows::LibKernel32::FileTime
    kernel = uninitialized Windows::LibKernel32::FileTime
    user = uninitialized Windows::LibKernel32::FileTime
    result = Windows::LibKernel32.GetSystemTimes(pointerof(idle), pointerof(kernel), pointerof(user))
    raise Error.new("GetSystemTimes failed", :cpu_unavailable) if result == 0

    idle_ticks = ticks(idle)
    kernel_ticks = ticks(kernel)
    user_ticks = ticks(user)
    busy = user_ticks + kernel_ticks - idle_ticks
    CPUTimes.new(busy, user_ticks + kernel_ticks)
  end

  private def ticks(value : Windows::LibKernel32::FileTime) : UInt64
    (value.high.to_u64 << 32) | value.low
  end
end
