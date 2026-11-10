module NativeDesktop
  # Aggregate cumulative CPU counters in platform-defined tick units.
  struct CPUTimes
    getter busy : UInt64
    getter total : UInt64

    def initialize(@busy : UInt64, @total : UInt64)
      raise ArgumentError.new("busy CPU time cannot exceed total CPU time") if busy > total
    end
  end

  # Reads aggregate CPU counters.
  module CPU
    extend self

    def times : CPUTimes
      Platform::CPU.times
    end
  end

  # Calculates aggregate CPU utilization between successive samples.
  class CPUSampler
    @lock = Mutex.new
    @previous : CPUTimes?

    # Returns a percentage from `0.0` to `100.0`. The first sample and a
    # sample following a counter reset return `nil` because no interval exists.
    def sample : Float64?
      @lock.synchronize do
        current = CPU.times
        previous = @previous
        @previous = current
        return nil unless previous
        return nil if current.total <= previous.total || current.busy < previous.busy

        total = current.total - previous.total
        busy = current.busy - previous.busy
        return nil if total == 0
        (busy.to_f64 / total * 100.0).clamp(0.0, 100.0)
      end
    end

    # Discards the baseline so the next sample returns `nil`.
    def reset : Nil
      @lock.synchronize { @previous = nil }
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/cpu"
{% elsif flag?(:linux) %}
  require "./platform/linux/cpu"
{% elsif flag?(:windows) %}
  require "./platform/windows/cpu"
{% end %}
