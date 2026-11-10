require "./objc_runtime"

module NativeDesktop::Platform::MacOS
  class SessionEventSource < NativeDesktop::SessionEventSource
    NOTIFICATIONS = {
      "NSWorkspaceWillSleepNotification"              => SessionEventTypes::Suspend,
      "NSWorkspaceDidWakeNotification"                => SessionEventTypes::Resume,
      "NSWorkspaceSessionDidResignActiveNotification" => SessionEventTypes::Lock,
      "NSWorkspaceSessionDidBecomeActiveNotification" => SessionEventTypes::Unlock,
      "NSWorkspaceWillPowerOffNotification"           => SessionEventTypes::Shutdown,
    }

    @@emit : Proc(NativeDesktop::SessionEvent, Nil)?
    @@registered = false
    @observer = Pointer(Void).null
    @center = Pointer(Void).null

    def start(&emit : NativeDesktop::SessionEvent ->) : Nil
      @@emit = emit
      ensure_observer_class
      o = ObjCRuntime
      workspace = o.msg(o.get_class("NSWorkspace"), "sharedWorkspace")
      @center = o.msg(workspace, "notificationCenter")
      klass = o.get_class("NativeDesktopSessionObserver")
      @observer = o.msg(o.msg(klass, "alloc"), "init")
      NOTIFICATIONS.each_key do |name|
        o.msg(
          @center,
          "addObserver:selector:name:object:",
          @observer,
          o.sel("nativeDesktopSessionEvent:"),
          o.nsstring(name),
          Pointer(Void).null
        )
      end
    end

    def process_event(event : Void*, &emit : NativeDesktop::SessionEvent ->) : Bool
      false
    end

    def close : Nil
      unless @center.null? || @observer.null?
        ObjCRuntime.msg(@center, "removeObserver:", @observer)
        ObjCRuntime.msg_void(@observer, "release")
      end
      @observer = Pointer(Void).null
      @center = Pointer(Void).null
      @@emit = nil
    end

    private def ensure_observer_class : Nil
      return if @@registered
      superclass = ObjCRuntime.get_class("NSObject")
      klass = LibNativeDesktopObjCRuntime.allocate_class_pair(superclass, "NativeDesktopSessionObserver", 0)
      unless klass.null?
        callback = ->(_self : Void*, _selector : Void*, notification : Void*) {
          name = ObjCRuntime.nsstring_to_s(ObjCRuntime.msg(notification, "name"))
          if type = name.try { |value| NOTIFICATIONS[value]? }
            @@emit.try(&.call(NativeDesktop::SessionEvent.new(type)))
          end
        }
        LibNativeDesktopObjCRuntime.add_method(
          klass,
          ObjCRuntime.sel("nativeDesktopSessionEvent:"),
          callback.pointer,
          "v@:@"
        )
        LibNativeDesktopObjCRuntime.register_class_pair(klass)
      end
      @@registered = true
    end
  end
end

NativeDesktop::SessionLifecycle.install(NativeDesktop::Platform::MacOS::SessionEventSource.new)
