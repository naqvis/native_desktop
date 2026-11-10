module NativeDesktop
  # Visual state of a taskbar or Dock progress indicator.
  enum TaskbarProgressState
    NoProgress
    Indeterminate
    Normal
    Error
    Paused
  end

  # Image data used for a taskbar overlay icon.
  struct TaskbarIcon
    getter bytes : Bytes?
    getter name : String?

    def self.bytes(value : Bytes) : self
      raise ArgumentError.new("icon bytes cannot be empty") if value.empty?
      new(value, nil)
    end

    def self.name(value : String) : self
      raise ArgumentError.new("icon name cannot be empty") if value.empty?
      new(nil, value)
    end

    private def initialize(@bytes : Bytes?, @name : String?)
    end
  end

  # Controls the taskbar or Dock representation of a host-owned window.
  class Taskbar
    getter window : Void*
    getter application_id : String?
    @native : NativeTaskbar
    @cleaned = false

    def initialize(@window : Void*, @application_id : String? = nil)
      raise ArgumentError.new("window handle cannot be null") if @window.null?
      if application_id = @application_id
        raise ArgumentError.new("application id cannot be empty") if application_id.empty?
      end
      @native = Runtime.dispatch_sync { NativeTaskbar.new(@window, @application_id) }
    end

    # Sets progress after clamping it to `0.0..1.0`.
    def progress=(value : Float64) : Nil
      ensure_active
      raise ArgumentError.new("progress must be finite") unless value.finite?
      Runtime.dispatch_sync { @native.progress = value.clamp(0.0, 1.0) }
    end

    # Sets the visual progress state.
    def state=(state : TaskbarProgressState) : Nil
      ensure_active
      Runtime.dispatch_sync { @native.state = state }
    end

    # Removes the progress indicator.
    def clear_progress : Nil
      ensure_active
      Runtime.dispatch_sync { @native.clear_progress }
    end

    # Sets a textual badge, or clears it with `nil`.
    def badge=(text : String?) : Nil
      ensure_active
      Runtime.dispatch_sync { @native.badge = text }
    end

    # Sets a taskbar overlay icon, or clears it with `nil`.
    def overlay_icon=(icon : TaskbarIcon?) : Nil
      ensure_active
      Runtime.dispatch_sync { @native.overlay_icon = icon }
    end

    # Releases resources owned by this controller.
    def cleanup : Nil
      return if @cleaned
      Runtime.dispatch_sync { @native.cleanup }
      @cleaned = true
    end

    private def ensure_active : Nil
      raise Error.new("taskbar controller has been cleaned up", :taskbar_closed) if @cleaned
    end

    {% if flag?(:darwin) %}
      private alias NativeTaskbar = Platform::MacOS::Taskbar
    {% elsif flag?(:linux) %}
      private alias NativeTaskbar = Platform::Linux::Taskbar
    {% elsif flag?(:windows) %}
      private alias NativeTaskbar = Platform::Windows::Taskbar
    {% end %}
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/taskbar"
{% elsif flag?(:linux) %}
  require "./platform/linux/taskbar"
{% elsif flag?(:windows) %}
  require "./platform/windows/taskbar"
{% end %}
