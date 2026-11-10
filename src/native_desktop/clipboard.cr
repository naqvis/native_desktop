{% if flag?(:darwin) %}
  require "./platform/macos/clipboard"
{% elsif flag?(:linux) %}
  require "./platform/linux/clipboard"
{% elsif flag?(:windows) %}
  require "./platform/windows/clipboard"
{% else %}
  {% raise "native_desktop does not support this platform" %}
{% end %}

module NativeDesktop
  # Access to text, HTML, RTF, and image data on the system clipboard.
  module Clipboard
    extend self

    def read_text : String
      Runtime.dispatch_sync { Platform::Clipboard.read_text }
    end

    def write_text(text : String) : Nil
      Runtime.dispatch_sync { Platform::Clipboard.write_text(text) }
    end

    def read_html : String?
      Runtime.dispatch_sync { Platform::Clipboard.read_html }
    end

    def write_html(html : String) : Nil
      Runtime.dispatch_sync { Platform::Clipboard.write_html(html) }
    end

    def read_rtf : String?
      Runtime.dispatch_sync { Platform::Clipboard.read_rtf }
    end

    def write_rtf(rtf : String) : Nil
      Runtime.dispatch_sync { Platform::Clipboard.write_rtf(rtf) }
    end

    def read_image : Bytes?
      Runtime.dispatch_sync { Platform::Clipboard.read_image }
    end

    def write_image(data : Bytes) : Nil
      Runtime.dispatch_sync { Platform::Clipboard.write_image(data) }
    end

    def clear : Nil
      Runtime.dispatch_sync { Platform::Clipboard.clear }
    end

    def version : UInt64
      Runtime.dispatch_sync { Platform::Clipboard.version }
    end
  end

  # Polls the clipboard sequence number and emits only content changes.
  class ClipboardMonitor
    @lock = Mutex.new
    @running = false
    @generation = 0_u64

    def start(interval : Time::Span = 500.milliseconds, &changed : UInt64 ->) : Nil
      raise ArgumentError.new("monitor interval must be positive") unless interval.positive?
      generation = @lock.synchronize do
        return if @running
        @running = true
        @generation &+= 1
      end
      initial = Clipboard.version
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

    private def poll(generation : UInt64, last : UInt64, interval : Time::Span, changed : Proc(UInt64, Nil)) : Nil
      loop do
        sleep interval
        break unless @lock.synchronize { @running && @generation == generation }
        current = Clipboard.version
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

NativeDesktop::Capabilities.register(NativeDesktop::Features::Clipboard, NativeDesktop::CapabilityState::Supported)
