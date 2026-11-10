module NativeDesktop::Platform::CPU
  extend self

  PROC_STAT = Path["/proc/stat"]

  def times : CPUTimes
    line = File.open(PROC_STAT) { |file| file.gets }
    raise Error.new("could not read aggregate CPU counters", :cpu_unavailable) unless line
    parts = line.split
    raise Error.new("invalid aggregate CPU counters", :cpu_unavailable) unless parts.first? == "cpu" && parts.size >= 5

    user = counter(parts, 1)
    nice = counter(parts, 2)
    system = counter(parts, 3)
    idle = counter(parts, 4)
    iowait = counter(parts, 5)
    irq = counter(parts, 6)
    softirq = counter(parts, 7)
    steal = counter(parts, 8)
    busy = user + nice + system + irq + softirq + steal
    CPUTimes.new(busy, busy + idle + iowait)
  rescue ex : Error
    raise ex
  rescue ex
    raise Error.new("could not read Linux CPU counters: #{ex.message}", :cpu_unavailable, ex)
  end

  private def counter(parts : Array(String), index : Int32) : UInt64
    return 0_u64 if index >= parts.size
    parts[index].to_u64? || raise Error.new("invalid CPU counter #{parts[index].inspect}", :cpu_unavailable)
  end
end
