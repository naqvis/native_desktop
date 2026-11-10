require "./objc_runtime"

module NativeDesktop::Platform::MacOS
  class Taskbar
    def initialize(@window : Void*, @application_id : String?)
    end

    def progress=(value : Float64) : Nil
      self.badge = "#{(value * 100).round.to_i}%"
    end

    def state=(state : TaskbarProgressState) : Nil
      clear_progress if state.no_progress?
    end

    def clear_progress : Nil
      self.badge = nil
    end

    def badge=(text : String?) : Nil
      ObjCRuntime.with_autorelease_pool do
        label = text && !text.empty? ? ObjCRuntime.nsstring(text) : Pointer(Void).null
        ObjCRuntime.msg(dock_tile, "setBadgeLabel:", label)
      end
    end

    def overlay_icon=(icon : TaskbarIcon?) : Nil
      # NSDockTile has no native overlay-icon facility.
    end

    def cleanup : Nil
      clear_progress
    end

    private def dock_tile : Void*
      application_class = ObjCRuntime.get_class("NSApplication")
      raise Error.new("could not access NSApplication", :taskbar_unavailable) if application_class.null?
      application = ObjCRuntime.msg(application_class, "sharedApplication")
      dock = ObjCRuntime.msg(application, "dockTile") unless application.null?
      raise Error.new("could not access the application Dock tile", :taskbar_unavailable) unless dock && !dock.null?
      dock
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::TaskbarProgress, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Capabilities.register(NativeDesktop::Features::TaskbarBadge, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Capabilities.register(
  NativeDesktop::Features::TaskbarOverlay,
  NativeDesktop::CapabilityState::Unsupported,
  "NSDockTile has no overlay-icon facility"
)
