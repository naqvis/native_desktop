require "log"
require "./objc_runtime"

module NativeDesktop::Platform
  # Receives the standard URL and open-document Apple events without replacing
  # the application's NSApplicationDelegate.
  class MacOSActivationSource < NativeDesktop::ActivationSource
    Log = ::Log.for("NativeDesktop::Activations[macOS]")

    GET_URL_EVENT_CLASS = 0x4755524c_u32 # "GURL"
    GET_URL_EVENT_ID    = 0x4755524c_u32 # "GURL"
    CORE_EVENT_CLASS    = 0x61657674_u32 # "aevt"
    OPEN_DOCUMENTS_ID   = 0x6f646f63_u32 # "odoc"
    DIRECT_OBJECT       = 0x2d2d2d2d_u32 # "----"

    @@registered = false
    @@target = Pointer(Void).null
    @@emit : Proc(NativeDesktop::Activation, Nil)? = nil

    def start(&emit : NativeDesktop::Activation ->) : Nil
      @@emit = emit
      register_target
      manager = apple_event_manager
      o = MacOS::ObjCRuntime
      o.msg_void(manager, "setEventHandler:andSelector:forEventClass:andEventID:",
        @@target, o.sel("nativeDesktopHandleURL:withReplyEvent:"), GET_URL_EVENT_CLASS, GET_URL_EVENT_ID)
      o.msg_void(manager, "setEventHandler:andSelector:forEventClass:andEventID:",
        @@target, o.sel("nativeDesktopHandleDocuments:withReplyEvent:"), CORE_EVENT_CLASS, OPEN_DOCUMENTS_ID)
    end

    def stop : Nil
      manager = apple_event_manager
      o = MacOS::ObjCRuntime
      o.msg_void(manager, "removeEventHandlerForEventClass:andEventID:", GET_URL_EVENT_CLASS, GET_URL_EVENT_ID)
      o.msg_void(manager, "removeEventHandlerForEventClass:andEventID:", CORE_EVENT_CLASS, OPEN_DOCUMENTS_ID)
      @@emit = nil
    end

    private def apple_event_manager : Void*
      MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSAppleEventManager"), "sharedAppleEventManager")
    end

    private def register_target : Nil
      unless @@registered
        o = MacOS::ObjCRuntime
        superclass = o.get_class("NSObject")
        klass = MacOS::LibNativeDesktopObjCRuntime.allocate_class_pair(superclass, "NativeDesktopActivationTarget", 0)
        unless klass.null?
          url_callback = ->(_self : Void*, _cmd : Void*, event : Void*, _reply : Void*) {
            MacOSActivationSource.receive_url(event)
          }
          documents_callback = ->(_self : Void*, _cmd : Void*, event : Void*, _reply : Void*) {
            MacOSActivationSource.receive_documents(event)
          }
          MacOS::LibNativeDesktopObjCRuntime.add_method(
            klass, o.sel("nativeDesktopHandleURL:withReplyEvent:"), url_callback.pointer, "v@:@@"
          )
          MacOS::LibNativeDesktopObjCRuntime.add_method(
            klass, o.sel("nativeDesktopHandleDocuments:withReplyEvent:"), documents_callback.pointer, "v@:@@"
          )
          MacOS::LibNativeDesktopObjCRuntime.register_class_pair(klass)
        end
        @@registered = true
      end

      if @@target.null?
        klass = MacOS::ObjCRuntime.get_class("NativeDesktopActivationTarget")
        @@target = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.msg(klass, "alloc"), "init") unless klass.null?
      end
    end

    def self.receive_url(event : Void*) : Nil
      descriptor = MacOS::ObjCRuntime.msg_u32(event, "paramDescriptorForKeyword:", DIRECT_OBJECT)
      value = nsstring(MacOS::ObjCRuntime.msg(descriptor, "stringValue"))
      @@emit.try(&.call(NativeDesktop::Activation.url(value))) unless value.nil?
    rescue ex
      Log.error(exception: ex) { "macOS URL activation failed" }
    end

    def self.receive_documents(event : Void*) : Nil
      descriptor = MacOS::ObjCRuntime.msg_u32(event, "paramDescriptorForKeyword:", DIRECT_OBJECT)
      return if descriptor.null?

      files = [] of String
      count = MacOS::ObjCRuntime.msg_long(descriptor, "numberOfItems")
      count.times do |offset|
        item = MacOS::ObjCRuntime.msg_object_at(descriptor, "descriptorAtIndex:", offset.to_u64 + 1)
        url = MacOS::ObjCRuntime.msg(item, "fileURLValue")
        path = nsstring(MacOS::ObjCRuntime.msg(url, "path"))
        files << path if path
      end
      @@emit.try(&.call(NativeDesktop::Activation.files(files))) unless files.empty?
    rescue ex
      Log.error(exception: ex) { "macOS file activation failed" }
    end

    private def self.nsstring(object : Void*) : String?
      return nil if object.null?
      bytes = MacOS::ObjCRuntime.msg_ptr(object, "UTF8String")
      bytes.null? ? nil : String.new(bytes)
    end
  end
end

NativeDesktop::Activations.install(NativeDesktop::Platform::MacOSActivationSource.new)
