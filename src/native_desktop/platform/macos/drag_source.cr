require "./objc_runtime"

module NativeDesktop::Platform
  class DragSource
    @@registered = false
    @source = Pointer(Void).null

    def initialize(@window : Void*)
    end

    def start(payload : NativeDesktop::DragPayload) : Bool
      MacOS::ObjCRuntime.with_autorelease_pool do
        writer, owned = writer(payload)
        return false if writer.null?
        begin
          app = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSApplication"), "sharedApplication")
          event = MacOS::ObjCRuntime.msg(app, "currentEvent")
          return false if event.null?
          item = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSDraggingItem"), "alloc"), "initWithPasteboardWriter:", writer)
          return false if item.null?
          begin
            view = MacOS::ObjCRuntime.msg(@window, "contentView")
            return false if view.null?
            location = MacOS::ObjCRuntime.msg_point(event, "locationInWindow")
            point = MacOS::ObjCRuntime.msg_convert_point(view, "convertPoint:fromView:", location.x, location.y, Pointer(Void).null)
            MacOS::ObjCRuntime.msg_void(item, "setDraggingFrame:contents:", point.x, point.y, 100.0, 20.0, Pointer(Void).null)
            items = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSArray"), "arrayWithObject:", item)
            session = MacOS::ObjCRuntime.msg(view, "beginDraggingSessionWithItems:event:source:", items, event, source)
            !session.null?
          ensure
            MacOS::ObjCRuntime.msg_void(item, "release")
          end
        ensure
          MacOS::ObjCRuntime.msg_void(writer, "release") if owned
        end
      end
    end

    def close : Nil
      unless @source.null?
        MacOS::ObjCRuntime.msg_void(@source, "release")
        @source = Pointer(Void).null
      end
      @window = Pointer(Void).null
    end

    private def writer(payload : NativeDesktop::DragPayload) : {Void*, Bool}
      o = MacOS::ObjCRuntime
      case payload.kind
      in .text?
        {o.nsstring(payload.value), false}
      in .file?, .image?
        object = o.msg(o.msg(o.get_class("NSURL"), "alloc"), "initFileURLWithPath:", o.nsstring(payload.value))
        {object, true}
      in .url?
        object = o.msg(o.msg(o.get_class("NSURL"), "alloc"), "initWithString:", o.nsstring(payload.value))
        {object, true}
      end
    end

    private def source : Void*
      unless @@registered
        superclass = MacOS::ObjCRuntime.get_class("NSObject")
        klass = MacOS::LibNativeDesktopObjCRuntime.allocate_class_pair(superclass, "NativeDesktopDragSource", 0)
        unless klass.null?
          selector = MacOS::ObjCRuntime.sel("draggingSession:sourceOperationMaskForDraggingContext:")
          callback = ->(_self : Void*, _cmd : Void*, _session : Void*, _context : Int64) : UInt64 { 1_u64 }
          MacOS::LibNativeDesktopObjCRuntime.add_method(klass, selector, callback.pointer, "Q@:@q")
          MacOS::LibNativeDesktopObjCRuntime.register_class_pair(klass)
        end
        @@registered = true
      end
      if @source.null?
        klass = MacOS::ObjCRuntime.get_class("NativeDesktopDragSource")
        @source = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.msg(klass, "alloc"), "init") unless klass.null?
      end
      @source
    end
  end
end
