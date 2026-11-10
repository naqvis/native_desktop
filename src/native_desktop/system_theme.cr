require "log"

module NativeDesktop
  # The operating system's effective light or dark appearance.
  enum ColorScheme
    Light
    Dark
  end

  # Reads the current operating-system appearance.
  module SystemTheme
    extend self

    def current : ColorScheme
      Platform::SystemTheme.current
    end
  end

  # Polls the system appearance on the host's background executor.
  class ThemeMonitor
    Log = ::Log.for(self)

    @lock = Mutex.new
    @running = false
    @generation = 0_u64

    # Starts monitoring. Calling this while already running is a no-op.
    def start(interval : Time::Span = 2.seconds, &changed : ColorScheme ->) : Nil
      raise ArgumentError.new("monitor interval must be positive") unless interval.positive?
      generation = 0_u64
      initial = SystemTheme.current
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

    def running? : Bool
      @lock.synchronize { @running }
    end

    private def poll(generation : UInt64, last : ColorScheme, interval : Time::Span, changed : Proc(ColorScheme, Nil)) : Nil
      loop do
        sleep interval
        break unless current_generation?(generation)
        begin
          current = SystemTheme.current
          if current != last
            last = current
            changed.call(current)
          end
        rescue ex
          Log.warn(exception: ex) { "could not poll the system theme" }
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
  require "./platform/macos/system_theme"
{% elsif flag?(:linux) %}
  require "./platform/linux/system_theme"
{% elsif flag?(:windows) %}
  require "./platform/windows/system_theme"
{% end %}
