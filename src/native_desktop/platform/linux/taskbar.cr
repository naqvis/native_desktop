module NativeDesktop::Platform::Linux
  # Generic Linux desktops do not expose a portable taskbar progress API.
  # This implementation deliberately preserves the cross-platform no-op
  # contract instead of invoking desktop-specific command-line utilities.
  class Taskbar
    def initialize(@window : Void*, @application_id : String?)
    end

    def progress=(value : Float64) : Nil
    end

    def state=(state : TaskbarProgressState) : Nil
    end

    def clear_progress : Nil
    end

    def badge=(text : String?) : Nil
    end

    def overlay_icon=(icon : TaskbarIcon?) : Nil
    end

    def cleanup : Nil
    end
  end
end

{
  NativeDesktop::Features::TaskbarProgress,
  NativeDesktop::Features::TaskbarBadge,
  NativeDesktop::Features::TaskbarOverlay,
}.each do |feature|
  NativeDesktop::Capabilities.register(
    feature,
    NativeDesktop::CapabilityState::Unsupported,
    "generic Linux desktops have no portable taskbar integration protocol"
  )
end
