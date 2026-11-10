module NativeDesktop::Platform::CPU
  extend self

  @[Link(framework: "CoreFoundation")]
  lib LibMachCPUTime
    fun mach_host_self : UInt32
    fun host_statistics(host : UInt32, flavor : UInt32, info : Void*, count : UInt32*) : Int32
  end

  HOST_CPU_LOAD_INFO       = 3_u32
  HOST_CPU_LOAD_INFO_COUNT = 4_u32

  def times : CPUTimes
    count = HOST_CPU_LOAD_INFO_COUNT
    values = Slice(UInt32).new(HOST_CPU_LOAD_INFO_COUNT.to_i, 0_u32)
    result = LibMachCPUTime.host_statistics(
      LibMachCPUTime.mach_host_self,
      HOST_CPU_LOAD_INFO,
      values.to_unsafe.as(Void*),
      pointerof(count),
    )
    raise Error.new("host_statistics failed (#{result})", :cpu_unavailable) unless result == 0

    user = values[0].to_u64
    system = values[1].to_u64
    idle = values[2].to_u64
    nice = values[3].to_u64
    busy = user + system + nice
    CPUTimes.new(busy, busy + idle)
  end
end
