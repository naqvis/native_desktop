require "./objc_runtime"

module NativeDesktop::Platform::MacOS
  class Kiosk
    HIDE_MENU_BAR             = 1_u64 << 3
    HIDE_DOCK                 = 1_u64 << 4
    DISABLE_PROCESS_SWITCHING = 1_u64 << 7
    DISABLE_HIDE_APPLICATION  = 1_u64 << 9
    FULL_SCREEN_STYLE         = 1_i64 << 14

    @@owner : UInt64?

    @active = false
    @entered_fullscreen = false
    @saved_options = 0_u64
    @token : UInt64

    def initialize(@window : Void*)
      @token = object_id
    end

    def enter : Nil
      return if @active
      if owner = @@owner
        raise Error.new("another window already owns kiosk presentation", :kiosk_in_use) unless owner == @token
      end

      ObjCRuntime.with_autorelease_pool do
        application = shared_application
        require_application_bundle
        policy = ObjCRuntime.msg_long(application, "activationPolicy")
        raise Error.new("the application activation policy does not permit kiosk presentation", :kiosk_unavailable) if policy == 2

        @saved_options = ObjCRuntime.msg_long(application, "presentationOptions").to_u64
        options = @saved_options | HIDE_MENU_BAR | HIDE_DOCK | DISABLE_PROCESS_SWITCHING | DISABLE_HIDE_APPLICATION
        ObjCRuntime.msg_uint(application, "setPresentationOptions:", options)

        fullscreen = ObjCRuntime.msg_long(@window, "styleMask") & FULL_SCREEN_STYLE != 0
        unless fullscreen
          ObjCRuntime.msg(@window, "toggleFullScreen:", Pointer(Void).null)
          @entered_fullscreen = true
        end
      end
      @@owner = @token
      @active = true
    end

    def exit : Nil
      return unless @active
      ObjCRuntime.with_autorelease_pool do
        ObjCRuntime.msg_uint(shared_application, "setPresentationOptions:", @saved_options)
        ObjCRuntime.msg(@window, "toggleFullScreen:", Pointer(Void).null) if @entered_fullscreen
      end
      @entered_fullscreen = false
      @active = false
      @@owner = nil if @@owner == @token
    end

    def active? : Bool
      @active
    end

    def cleanup : Nil
      exit
    end

    private def shared_application : Void*
      klass = ObjCRuntime.get_class("NSApplication")
      raise Error.new("could not access NSApplication", :kiosk_unavailable) if klass.null?
      application = ObjCRuntime.msg(klass, "sharedApplication")
      raise Error.new("could not access the shared application", :kiosk_unavailable) if application.null?
      application
    end

    private def require_application_bundle : Nil
      klass = ObjCRuntime.get_class("NSBundle")
      raise Error.new("could not access NSBundle", :kiosk_unavailable) if klass.null?
      bundle = ObjCRuntime.msg(klass, "mainBundle")
      identifier = ObjCRuntime.msg(bundle, "bundleIdentifier") unless bundle.null?
      unless identifier && !identifier.null?
        raise Error.new("kiosk presentation requires a packaged macOS application bundle", :kiosk_unavailable)
      end
    end
  end
end
