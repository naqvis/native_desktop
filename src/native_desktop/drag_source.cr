module NativeDesktop
  enum DragKind
    File
    Text
    URL
    Image
  end

  struct DragPayload
    getter kind : DragKind
    getter value : String

    def initialize(@kind : DragKind, @value : String)
      raise ArgumentError.new("drag payload cannot be empty") if @value.empty?
    end

    def self.file(path : Path | String) : self
      new(DragKind::File, Path[path].expand.to_s)
    end

    def self.text(value : String) : self
      new(DragKind::Text, value)
    end

    def self.url(value : String) : self
      new(DragKind::URL, value)
    end

    def self.image(path : Path | String) : self
      new(DragKind::Image, Path[path].expand.to_s)
    end
  end

  # An owned native drag source anchored to a host window.
  class DragSource
    @platform : Platform::DragSource
    @closed = false
    @mutex = Mutex.new

    def initialize(window : Window)
      @platform = Platform::DragSource.new(window.handle)
    end

    # Starts a native drag session. Call this while handling a pointer event.
    def start(payload : DragPayload) : Bool
      @mutex.synchronize do
        raise RuntimeError.new("drag source is closed", :closed) if @closed
        Runtime.dispatch_sync { @platform.start(payload) }
      end
    end

    def close : Nil
      @mutex.synchronize do
        return if @closed
        Runtime.dispatch_sync { @platform.close }
        @closed = true
      end
    end

    def closed? : Bool
      @mutex.synchronize { @closed }
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/drag_source"
{% elsif flag?(:linux) %}
  require "./platform/linux/drag_source"
{% elsif flag?(:windows) %}
  require "./platform/windows/drag_source"
{% end %}
