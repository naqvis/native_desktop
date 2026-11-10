module NativeDesktop
  # A reversible kiosk-style presentation for one host-owned window.
  #
  # This hides ordinary window chrome and fills the display. It is not an
  # operating-system security boundary and cannot suppress privileged OS
  # shortcuts such as secure-attention sequences.
  class Kiosk
    getter window : Void*

    def initialize(@window : Void*)
      raise ArgumentError.new("window handle cannot be null") if @window.null?
      @native = Runtime.dispatch_sync { NativeKiosk.new(@window) }
    end

    # Enters kiosk presentation. Calling it twice is harmless.
    def enter : Nil
      ensure_open
      Runtime.dispatch_sync { @native.enter }
    end

    # Restores the window state captured by `#enter`.
    def exit : Nil
      ensure_open
      Runtime.dispatch_sync { @native.exit }
    end

    # Returns whether this controller currently owns an active presentation.
    def active? : Bool
      return false if @closed
      Runtime.dispatch_sync { @native.active? }
    end

    # Exits kiosk presentation and releases this controller.
    def cleanup : Nil
      return if @closed
      Runtime.dispatch_sync { @native.cleanup }
      @closed = true
    end

    private def ensure_open : Nil
      raise Error.new("kiosk controller has been cleaned up", :kiosk_closed) if @closed
    end

    {% if flag?(:darwin) %}
      private alias NativeKiosk = Platform::MacOS::Kiosk
    {% elsif flag?(:linux) %}
      private alias NativeKiosk = Platform::Linux::Kiosk
    {% elsif flag?(:windows) %}
      private alias NativeKiosk = Platform::Windows::Kiosk
    {% end %}

    @native : NativeKiosk
    @closed = false
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/kiosk"
{% elsif flag?(:linux) %}
  require "./platform/linux/kiosk"
{% elsif flag?(:windows) %}
  require "./platform/windows/kiosk"
{% end %}
