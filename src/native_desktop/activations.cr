module NativeDesktop
  native_desktop_open_id(ActivationType, "activation type")

  module ActivationTypes
    URL            = ActivationType["url"]
    Files          = ActivationType["files"]
    SecondInstance = ActivationType["second-instance"]
  end

  struct Activation
    getter type : ActivationType
    getter values : Array(String)
    getter timestamp : Time

    def initialize(@type : ActivationType, values : Enumerable(String), @timestamp : Time = Time.utc)
      @values = values.to_a
      raise ArgumentError.new("activation payload cannot be empty") if @values.empty?
      raise ArgumentError.new("activation values cannot be empty") if @values.any?(&.empty?)
    end

    def self.url(value : String) : self
      new(ActivationTypes::URL, [value])
    end

    def self.files(values : Enumerable(Path | String)) : self
      new(ActivationTypes::Files, values.map { |value| Path[value].expand.to_s })
    end

    def self.second_instance(payload : String) : self
      new(ActivationTypes::SecondInstance, [payload])
    end
  end

  abstract class ActivationSource
    abstract def start(&emit : Activation ->) : Nil

    def stop : Nil
    end
  end

  # Queues OS activations until a handler is installed. Native hosts should call
  # `emit` from their URL/file-open callbacks; this preserves cold-start events.
  module Activations
    extend self
    @@lock = Mutex.new
    @@pending = [] of Activation
    @@handlers = [] of Proc(Activation, Nil)
    private record Source, id : UInt64, value : ActivationSource
    @@sources = [] of Source
    @@next_source_id = 0_u64

    def install(source : ActivationSource) : Registration
      source.start { |event| emit(event) }
      id = @@lock.synchronize do
        @@next_source_id += 1
        @@sources << Source.new(@@next_source_id, source)
        @@next_source_id
      end
      Registration.new { remove_source(id) }
    end

    def on_event(replay_pending : Bool = true, &handler : Activation ->) : Registration
      pending = @@lock.synchronize do
        @@handlers << handler
        replay_pending ? @@pending.shift(@@pending.size) : [] of Activation
      end
      pending.each { |event| deliver(handler, event) }
      Registration.new { remove_handler(handler) }
    end

    def emit(event : Activation) : Nil
      handlers = @@lock.synchronize do
        if @@handlers.empty?
          @@pending << event
          [] of Proc(Activation, Nil)
        else
          @@handlers.dup
        end
      end
      handlers.each { |handler| deliver(handler, event) }
    end

    # Parses command-line arguments through an application-owned classifier.
    # Returning nil ignores an argument.
    def capture_arguments(arguments : Enumerable(String), &classify : String -> Activation?) : Nil
      arguments.each do |argument|
        if event = classify.call(argument)
          emit(event)
        end
      end
    end

    def pending : Array(Activation)
      @@lock.synchronize { @@pending.dup }
    end

    def source_installed? : Bool
      @@lock.synchronize { !@@sources.empty? }
    end

    def clear : Nil
      sources = @@lock.synchronize do
        @@pending.clear
        @@handlers.clear
        values = @@sources.map(&.value)
        @@sources = [] of Source
        values
      end
      sources.each(&.stop)
    end

    def clear_handlers : Nil
      @@lock.synchronize { @@handlers.clear }
    end

    def clear_pending : Nil
      @@lock.synchronize { @@pending.clear }
    end

    protected def remove_source(id : UInt64) : Nil
      source = @@lock.synchronize do
        index = @@sources.index { |registered| registered.id == id }
        index ? @@sources.delete_at(index).value : nil
      end
      source.try(&.stop)
    end

    protected def remove_handler(handler : Proc(Activation, Nil)) : Nil
      @@lock.synchronize { @@handlers.delete(handler) }
    end

    private def deliver(handler : Proc(Activation, Nil), event : Activation) : Nil
      if Runtime.attached?
        Runtime.dispatch { handler.call(event) }
      else
        handler.call(event)
      end
    rescue ex
      Log.error(exception: ex) { "activation handler failed" }
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/activation_source"
{% elsif flag?(:linux) || flag?(:windows) %}
  require "./platform/argument_activation_source"
{% end %}

{
  NativeDesktop::Features::URLActivations,
  NativeDesktop::Features::FileActivations,
}.each do |registered_feature|
  NativeDesktop::Capabilities.register(registered_feature) do |feature|
    if NativeDesktop::Activations.source_installed?
      NativeDesktop::Capability.new(feature, NativeDesktop::CapabilityState::Supported)
    else
      NativeDesktop::Capability.new(
        feature,
        NativeDesktop::CapabilityState::HostIntegrationRequired,
        "install an activation source for the GUI host"
      )
    end
  end
end
