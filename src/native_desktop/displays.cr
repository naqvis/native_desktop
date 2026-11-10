{% if flag?(:darwin) %}
  require "./platform/macos/displays"
{% elsif flag?(:linux) %}
  require "./platform/linux/displays"
{% elsif flag?(:windows) %}
  require "./platform/windows/displays"
{% end %}

module NativeDesktop
  record Point, x : Int32 = 0, y : Int32 = 0
  record Rectangle, x : Int32 = 0, y : Int32 = 0, width : Int32 = 0, height : Int32 = 0

  # A connected display and its current desktop geometry.
  struct Display
    def_equals_and_hash @bounds, @work_area, @primary, @name, @scale_factor

    getter bounds : Rectangle
    getter work_area : Rectangle
    getter primary : Bool
    getter name : String
    getter scale_factor : Float64

    def initialize(@bounds : Rectangle, @work_area : Rectangle, @primary : Bool = false, @name : String = "Display", @scale_factor : Float64 = 1.0)
      raise ArgumentError.new("display scale factor must be positive") unless scale_factor.finite? && scale_factor > 0
    end

    def primary? : Bool
      primary
    end
  end

  # Queries the desktop's displays and pointer position.
  module Displays
    extend self

    def all : Array(Display)
      Runtime.dispatch_sync do
        displays = Platform::Displays.all
        displays.sort_by { |display| display.primary? ? 0 : 1 }
      end
    end

    # Returns the primary display, or `nil` when the host reports none.
    def primary : Display?
      displays = all
      displays.find(&.primary?) || displays.first?
    end

    def cursor : Point
      Runtime.dispatch_sync { Platform::Displays.cursor }
    end
  end

  class DisplayMonitor
    @lock = Mutex.new
    @running = false
    @generation = 0_u64

    def start(interval : Time::Span = 2.seconds, &changed : Array(Display) ->) : Nil
      raise ArgumentError.new("monitor interval must be positive") unless interval.positive?
      generation = @lock.synchronize do
        return if @running
        @running = true
        @generation &+= 1
      end
      initial = Displays.all
      Runtime.spawn_background { poll(generation, initial, interval, changed) }
    rescue ex
      @lock.synchronize { @running = false if @generation == generation }
      raise ex
    end

    def stop : Nil
      @lock.synchronize do
        @running = false
        @generation &+= 1
      end
    end

    def running? : Bool
      @lock.synchronize { @running }
    end

    private def poll(generation : UInt64, last : Array(Display), interval : Time::Span, changed : Proc(Array(Display), Nil)) : Nil
      loop do
        sleep interval
        break unless @lock.synchronize { @running && @generation == generation }
        current = Displays.all
        if current != last
          last = current
          changed.call(current)
        end
      end
    ensure
      @lock.synchronize { @running = false if @generation == generation }
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::Displays, NativeDesktop::CapabilityState::Supported)
