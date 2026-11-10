require "log"

module NativeDesktop
  enum ActivityState
    Active
    Idle
  end

  # A sampled activity state and the time since the last user input.
  struct ActivityChange
    getter state : ActivityState
    getter duration : Time::Span

    def initialize(@state : ActivityState, @duration : Time::Span)
    end

    def idle? : Bool
      state.idle?
    end

    def active? : Bool
      state.active?
    end
  end

  # Reads the time since the operating system last observed user input.
  module Idle
    extend self

    def duration : Time::Span
      Platform::Idle.duration
    end

    def idle?(threshold : Time::Span = 5.minutes) : Bool
      raise ArgumentError.new("idle threshold cannot be negative") if threshold < 0.seconds
      duration >= threshold
    end
  end

  # Polls for transitions between active and idle states.
  class IdleMonitor
    Log = ::Log.for(self)

    @lock = Mutex.new
    @running = false
    @generation = 0_u64

    # Starts monitoring on the host's background executor. The current state
    # is delivered first, followed by state transitions only.
    def start(threshold : Time::Span = 5.minutes, interval : Time::Span = 30.seconds, &changed : ActivityChange ->) : Nil
      raise ArgumentError.new("idle threshold cannot be negative") if threshold < 0.seconds
      raise ArgumentError.new("monitor interval must be positive") unless interval.positive?
      generation = 0_u64
      initial = Idle.duration
      generation = @lock.synchronize do
        return if @running
        @running = true
        @generation &+= 1
      end
      Runtime.spawn_background { poll(generation, initial, threshold, interval, changed) }
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

    private def poll(generation : UInt64, initial : Time::Span, threshold : Time::Span, interval : Time::Span, changed : Proc(ActivityChange, Nil)) : Nil
      idle = initial >= threshold
      notify(generation, ActivityChange.new(state(idle), initial), changed)
      loop do
        sleep interval
        break unless current_generation?(generation)
        begin
          duration = Idle.duration
          current = duration >= threshold
          if current != idle
            idle = current
            notify(generation, ActivityChange.new(state(idle), duration), changed)
          end
        rescue ex
          Log.warn(exception: ex) { "could not poll user activity" }
        end
      end
    ensure
      @lock.synchronize { @running = false if @generation == generation }
    end

    private def notify(generation : UInt64, change : ActivityChange, callback : Proc(ActivityChange, Nil)) : Nil
      callback.call(change) if current_generation?(generation)
    rescue ex
      Log.warn(exception: ex) { "idle monitor callback failed" }
    end

    private def state(idle : Bool) : ActivityState
      idle ? ActivityState::Idle : ActivityState::Active
    end

    private def current_generation?(generation : UInt64) : Bool
      @lock.synchronize { @running && @generation == generation }
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/idle"
{% elsif flag?(:linux) %}
  require "./platform/linux/idle"
{% elsif flag?(:windows) %}
  require "./platform/windows/idle"
{% end %}
