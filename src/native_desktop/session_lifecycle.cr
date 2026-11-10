module NativeDesktop
  native_desktop_open_id(SessionEventType, "session event type")

  module SessionEventTypes
    Suspend  = SessionEventType["suspend"]
    Resume   = SessionEventType["resume"]
    Lock     = SessionEventType["lock"]
    Unlock   = SessionEventType["unlock"]
    Shutdown = SessionEventType["shutdown"]
  end

  record SessionEvent, type : SessionEventType, timestamp : Time = Time.utc

  abstract class SessionEventSource
    def start(&emit : SessionEvent ->) : Nil
    end

    abstract def process_event(event : Void*, &emit : SessionEvent ->) : Bool

    def close : Nil
    end
  end

  module SessionLifecycle
    extend self
    Log = ::Log.for(self)
    @@lock = Mutex.new
    @@handlers = [] of Proc(SessionEvent, Nil)
    private record Source, id : UInt64, value : SessionEventSource
    @@sources = [] of Source
    @@next_source_id = 0_u64

    def install(source : SessionEventSource) : Registration
      source.start { |event| emit(event) }
      id = @@lock.synchronize do
        @@next_source_id += 1
        @@sources << Source.new(@@next_source_id, source)
        @@next_source_id
      end
      Registration.new { remove_source(id) }
    end

    def on_event(&handler : SessionEvent ->) : Registration
      @@lock.synchronize { @@handlers << handler }
      Registration.new { remove_handler(handler) }
    end

    def emit(type : SessionEventType) : Nil
      emit(SessionEvent.new(type))
    end

    def emit(event : SessionEvent) : Nil
      handlers = @@lock.synchronize { @@handlers.dup }
      handlers.each do |handler|
        begin
          Runtime.spawn_background { handler.call(event) }
        rescue ex : RuntimeError
          handler.call(event)
        rescue ex
          Log.error(exception: ex) { "session lifecycle handler failed" }
        end
      end
    end

    def process_event(event : Void*) : Bool
      sources = @@lock.synchronize { @@sources.map(&.value) }
      sources.any? { |source| source.process_event(event) { |value| emit(value) } }
    end

    def source_installed? : Bool
      @@lock.synchronize { !@@sources.empty? }
    end

    def clear : Nil
      @@lock.synchronize { @@handlers.clear }
    end

    def remove_sources : Nil
      sources = @@lock.synchronize do
        values = @@sources.map(&.value)
        @@sources = [] of Source
        values
      end
      sources.each(&.close)
    end

    protected def remove_source(id : UInt64) : Nil
      source = @@lock.synchronize do
        index = @@sources.index { |registered| registered.id == id }
        index ? @@sources.delete_at(index).value : nil
      end
      source.try(&.close)
    end

    protected def remove_handler(handler : Proc(SessionEvent, Nil)) : Nil
      @@lock.synchronize { @@handlers.delete(handler) }
    end
  end
end

{% if flag?(:windows) %}
  require "./platform/windows/session_lifecycle"
{% elsif flag?(:darwin) %}
  require "./platform/macos/session_lifecycle"
{% elsif flag?(:linux) %}
  require "./platform/linux/session_lifecycle"
{% end %}

NativeDesktop::Capabilities.register(NativeDesktop::Features::SessionLifecycle) do |feature|
  if NativeDesktop::SessionLifecycle.source_installed?
    NativeDesktop::Capability.new(feature, NativeDesktop::CapabilityState::Supported)
  else
    NativeDesktop::Capability.new(
      feature,
      NativeDesktop::CapabilityState::HostIntegrationRequired,
      "install a session event source for the GUI host"
    )
  end
end
