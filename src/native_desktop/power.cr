require "log"

module NativeDesktop
  # A snapshot of the system battery.
  struct BatteryStatus
    # Charge level from `0.0` to `1.0`, or `nil` when unavailable.
    getter level : Float64?

    # Estimated time until empty or full, depending on whether the battery is
    # discharging or charging.
    getter remaining : Time::Span?

    # Whether the battery is actively charging.
    getter? charging : Bool

    # Whether the system is connected to an external power source.
    getter? external_power : Bool

    def initialize(@level : Float64?, @charging : Bool, @external_power : Bool, @remaining : Time::Span? = nil)
      if level = @level
        raise ArgumentError.new("battery level must be finite") unless level.finite?
        raise ArgumentError.new("battery level must be between 0 and 1") unless level.in?(0.0..1.0)
      end
      if remaining = @remaining
        raise ArgumentError.new("remaining time cannot be negative") if remaining < 0.seconds
      end
    end

    # Returns `true` when external power is disconnected.
    def on_battery? : Bool
      !external_power?
    end
  end

  # Reads the current battery and power-source state.
  module Power
    extend self

    # Returns `nil` when the system has no battery.
    def battery : BatteryStatus?
      Platform::Power.battery
    end

    # Returns `true` when a battery is present and external power is disconnected.
    def on_battery? : Bool
      battery.try(&.on_battery?) || false
    end
  end

  # Polls battery state on the host's background executor.
  class PowerMonitor
    Log = ::Log.for(self)

    @lock = Mutex.new
    @running = false
    @generation = 0_u64

    # Starts monitoring battery changes. Calling this while already running is
    # a no-op. The callback also receives `nil` if a battery disappears.
    def start(interval : Time::Span = 30.seconds, &changed : BatteryStatus? ->) : Nil
      raise ArgumentError.new("monitor interval must be positive") unless interval.positive?
      generation = 0_u64
      initial = Power.battery
      generation = @lock.synchronize do
        return if @running
        @running = true
        @generation &+= 1
      end
      Runtime.spawn_background { poll(generation, initial, interval, changed) }
    rescue ex
      @lock.synchronize { @running = false if @generation == generation }
      raise ex
    end

    # Stops monitoring. A sleeping worker exits when it next wakes.
    def stop : Nil
      @lock.synchronize do
        @running = false
        @generation &+= 1
      end
    end

    # Returns `true` while this monitor owns an active polling worker.
    def running? : Bool
      @lock.synchronize { @running }
    end

    private def poll(generation : UInt64, last : BatteryStatus?, interval : Time::Span, changed : Proc(BatteryStatus?, Nil)) : Nil
      loop do
        sleep interval
        break unless current_generation?(generation)
        begin
          current = Power.battery
          if current != last
            last = current
            changed.call(current)
          end
        rescue ex
          Log.warn(exception: ex) { "could not poll battery state" }
        end
      end
    ensure
      @lock.synchronize { @running = false if @generation == generation }
    end

    private def current_generation?(generation : UInt64) : Bool
      @lock.synchronize { @running && @generation == generation }
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/power"
{% elsif flag?(:linux) %}
  require "./platform/linux/power"
{% elsif flag?(:windows) %}
  require "./platform/windows/power"
{% end %}
