require "log"

module NativeDesktop
  # Connects native controls to the GUI loop owned by the host application.
  # The dispatcher must enqueue, rather than immediately execute, work received
  # from another fiber.
  module Runtime
    extend self

    Log = ::Log.for(self)

    alias Dispatcher = Proc(Proc(Nil), Nil)

    @@lock = Mutex.new
    @@gui_thread : Thread?
    @@dispatcher : Dispatcher?
    @@background : Dispatcher?
    @@generation = 0_u64
    @@counter = Atomic(UInt64).new(0_u64)
    @@pending = {} of UInt64 => Proc(Exception, Nil)

    # Attaches the host GUI thread and its dispatchers. The optional background
    # executor is required by services that wait for native events.
    def attach_to_current_thread(background : Dispatcher? = nil, &dispatcher : Proc(Nil) ->) : Nil
      waiters = nil
      @@lock.synchronize do
        raise RuntimeError.new("native desktop runtime is already attached", :already_attached) if @@dispatcher
        @@gui_thread = Thread.current
        @@dispatcher = dispatcher
        @@background = background
        @@generation &+= 1
      end
    end

    def attached? : Bool
      @@lock.synchronize { !@@dispatcher.nil? }
    end

    def gui_thread? : Bool
      thread = @@lock.synchronize { @@gui_thread }
      thread.try(&.same?(Thread.current)) || false
    end

    # Runs *block* on the attached GUI thread, suspending the calling fiber
    # until the result is available. An optional *timeout* raises
    # RuntimeError with code `:dispatch_timeout` when the host does not run
    # the queued work in time; the work is then skipped if it has not started.
    def dispatch_sync(timeout : Time::Span? = nil, &block : -> T) : T forall T
      return block.call if gui_thread?

      dispatcher, generation = @@lock.synchronize do
        {@@dispatcher || raise(RuntimeError.new("native desktop runtime is not attached", :not_attached)), @@generation}
      end

      result = Channel(T?).new(1)
      failure = Channel(Exception).new(1)
      completed = Atomic(Bool).new(false)
      id = @@counter.add(1_u64) + 1_u64
      cancel = ->(error : Exception) { failure.send(error) if completed.compare_and_set(false, true) }
      @@lock.synchronize { @@pending[id] = cancel }

      begin
        dispatcher.call(-> {
          begin
            current = @@lock.synchronize { @@generation }
            raise RuntimeError.new("native desktop runtime was detached", :detached) unless current == generation
            return if completed.get
            value = block.call
            result.send(value) if completed.compare_and_set(false, true)
          rescue ex
            failure.send(ex) if completed.compare_and_set(false, true)
          ensure
            @@lock.synchronize { @@pending.delete(id) }
          end
        })
      rescue ex
        @@lock.synchronize { @@pending.delete(id) }
        failure.send(ex) if completed.compare_and_set(false, true)
      end

      {% if T == NoReturn %}
        raise failure.receive
      {% else %}
        if timeout
          select
          when value = result.receive
            value.as(T)
          when error = failure.receive
            raise error
          when timeout(timeout)
            completed.compare_and_set(false, true)
            @@lock.synchronize { @@pending.delete(id) }
            raise RuntimeError.new("native desktop dispatch timed out", :dispatch_timeout)
          end
        else
          select
          when value = result.receive
            value.as(T)
          when error = failure.receive
            raise error
          end
        end
      {% end %}
    end

    # Queues *block* on the attached GUI thread without waiting. Work queued
    # against a detached or reattached runtime is dropped instead of running
    # against a stale host, and an exception raised by the block on the GUI
    # thread is logged rather than crashing that fiber.
    def dispatch(&block : ->) : Nil
      if gui_thread?
        block.call
      else
        dispatcher, generation = @@lock.synchronize do
          {@@dispatcher || raise(RuntimeError.new("native desktop runtime is not attached", :not_attached)), @@generation}
        end
        dispatcher.call(-> {
          current = @@lock.synchronize { @@generation }
          return unless current == generation
          begin
            block.call
          rescue ex
            Log.error(exception: ex) { "native desktop dispatched callback failed" }
          end
        })
      end
    end

    # Schedules work on the background executor supplied by the GUI host.
    def spawn_background(&block : ->) : Nil
      executor = @@lock.synchronize do
        @@background || raise(RuntimeError.new("native desktop background executor is not attached", :background_executor_missing))
      end
      executor.call(block)
    end

    # Lets a GUI host offer native messages to controls that integrate with
    # the host event loop. Returns `true` when a message was consumed.
    def process_event(event : Void*) : Bool
      {% if flag?(:windows) %}
        ApplicationMenus.process_event(event) ||
          Platform::Windows::Shortcuts.process_event(event) ||
          SessionLifecycle.process_event(event)
      {% else %}
        SessionLifecycle.process_event(event)
      {% end %}
    end

    def detach : Nil
      pending = @@lock.synchronize do
        @@dispatcher = nil
        @@background = nil
        @@gui_thread = nil
        @@generation &+= 1
        requests = @@pending.values
        @@pending.clear
        requests
      end
      error = RuntimeError.new("native desktop runtime was detached", :detached)
      pending.each(&.call(error))
    end
  end
end
