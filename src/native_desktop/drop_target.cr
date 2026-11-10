module NativeDesktop
  native_desktop_open_id(DropOperation, "drop operation")

  module DropOperations
    Copy = DropOperation["copy"]
    Move = DropOperation["move"]
    Link = DropOperation["link"]
  end

  record DropEvent,
    payloads : Array(DragPayload),
    position : Point = Point.new,
    operation : DropOperation = DropOperations::Copy do
    def initialize(@payloads : Array(DragPayload), @position : Point = Point.new, @operation : DropOperation = DropOperations::Copy)
      raise ArgumentError.new("drop payload cannot be empty") if @payloads.empty?
    end
  end

  abstract class DropTargetAdapter
    abstract def attach(window : Window, kinds : Set(DragKind), &emit : DropEvent -> Bool) : Nil
    abstract def close : Nil
  end

  # Extensible adapter-provider registry. Bundled platform backends register a
  # default provider, while toolkits can temporarily layer their own provider
  # without replacing or naming the native implementation.
  module DropTargets
    extend self

    alias Factory = Proc(DropTargetAdapter)
    private record Provider, id : UInt64, factory : Factory

    @@lock = Mutex.new
    @@providers = [] of Provider
    @@next_id = 0_u64

    def register(&factory : -> DropTargetAdapter) : NativeDesktop::Registration
      id = @@lock.synchronize do
        @@next_id += 1
        @@providers << Provider.new(@@next_id, factory)
        @@next_id
      end
      NativeDesktop::Registration.new { unregister(id) }
    end

    def build : DropTargetAdapter
      provider = @@lock.synchronize { @@providers.last? }
      unless provider
        raise Error.new("no drop-target adapter provider is registered", :drop_target_unavailable)
      end
      provider.factory.call
    end

    protected def unregister(id : UInt64) : Nil
      @@lock.synchronize do
        if index = @@providers.index { |provider| provider.id == id }
          @@providers.delete_at(index)
        end
      end
    end
  end

  # An owned drop target attached through a registered or explicit adapter.
  class DropTarget
    getter window : Window
    getter kinds : Set(DragKind)
    @adapter : DropTargetAdapter
    @closed = false

    def initialize(@window : Window, kinds : Enumerable(DragKind) = DragKind.values, &handler : DropEvent ->)
      initialize(@window, DropTargets.build, kinds, &handler)
    end

    def initialize(@window : Window, @adapter : DropTargetAdapter, kinds : Enumerable(DragKind) = DragKind.values, &handler : DropEvent ->)
      @kinds = kinds.to_set
      raise ArgumentError.new("drop target must accept at least one payload kind") if @kinds.empty?
      @adapter.attach(window, @kinds) do |event|
        accepted = event.payloads.select { |payload| @kinds.includes?(payload.kind) }
        next false if accepted.empty?
        normalized = DropEvent.new(accepted, event.position, event.operation)
        Runtime.dispatch { handler.call(normalized) }
        true
      end
    end

    def close : Nil
      return if @closed
      @adapter.close
      @closed = true
    end

    def closed? : Bool
      @closed
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/drop_target"
{% elsif flag?(:linux) %}
  require "./platform/linux/drop_target"
{% elsif flag?(:windows) %}
  require "./platform/windows/drop_target"
{% end %}
