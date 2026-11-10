require "./objc_runtime"

module NativeDesktop::Platform
  # Installs a private Objective-C subclass on the host's content view. This
  # keeps the host's delegate untouched and confines AppKit drag callbacks to
  # the lifetime of this adapter.
  class MacOSDropTargetAdapter < NativeDesktop::DropTargetAdapter
    COPY_OPERATION = 1_u64

    @@lock = Mutex.new
    @@instances = {} of UInt64 => MacOSDropTargetAdapter
    @@next_class_id = 0_u64

    @view = Pointer(Void).null
    @original_class = Pointer(Void).null
    @emit : Proc(NativeDesktop::DropEvent, Bool)?
    @kinds = Set(NativeDesktop::DragKind).new

    def attach(window : NativeDesktop::Window, kinds : Set(NativeDesktop::DragKind), &emit : NativeDesktop::DropEvent -> Bool) : Nil
      o = MacOS::ObjCRuntime
      @view = o.msg(window.handle, "contentView")
      if @view.null?
        raise NativeDesktop::Error.new("the macOS window has no content view", :drop_target_unavailable)
      end

      @kinds = kinds
      @emit = emit
      @original_class = MacOS::LibNativeDesktopObjCRuntime.object_get_class(@view)
      subclass = build_subclass(@original_class)
      MacOS::LibNativeDesktopObjCRuntime.object_set_class(@view, subclass)
      @@lock.synchronize { @@instances[@view.address] = self }
      o.msg_void(@view, "registerForDraggedTypes:", pasteboard_types)
    rescue ex : NativeDesktop::Error
      close
      raise ex
    rescue ex
      close
      raise NativeDesktop::Error.new("failed to attach macOS drop target: #{ex.message}", :drop_target_attach_failed)
    end

    def close : Nil
      unless @view.null?
        @@lock.synchronize { @@instances.delete(@view.address) }
        MacOS::ObjCRuntime.msg_void(@view, "unregisterDraggedTypes")
        unless @original_class.null?
          MacOS::LibNativeDesktopObjCRuntime.object_set_class(@view, @original_class)
        end
      end
      @view = Pointer(Void).null
      @original_class = Pointer(Void).null
      @emit = nil
    end

    protected def receive(info : Void*) : Bool
      pasteboard = MacOS::ObjCRuntime.msg(info, "draggingPasteboard")
      payloads = url_payloads(pasteboard)
      if payloads.empty? && @kinds.includes?(NativeDesktop::DragKind::Text)
        if value = pasteboard_string(pasteboard, "public.utf8-plain-text")
          payloads << NativeDesktop::DragPayload.text(value)
        end
      end
      return false if payloads.empty?

      location = MacOS::ObjCRuntime.msg_point(info, "draggingLocation")
      point = MacOS::ObjCRuntime.msg_convert_point(
        @view,
        "convertPoint:fromView:",
        location.x,
        location.y,
        Pointer(Void).null
      )
      event = NativeDesktop::DropEvent.new(
        payloads,
        NativeDesktop::Point.new(point.x.to_i32, point.y.to_i32)
      )
      @emit.try(&.call(event)) || false
    rescue
      false
    end

    def self.entered(view : Void*) : UInt64
      @@lock.synchronize { @@instances.has_key?(view.address) } ? COPY_OPERATION : 0_u64
    end

    def self.perform(view : Void*, info : Void*) : Int8
      adapter = @@lock.synchronize { @@instances[view.address]? }
      adapter.try(&.receive(info)) ? 1_i8 : 0_i8
    end

    private def build_subclass(superclass : Void*) : Void*
      id = @@lock.synchronize do
        @@next_class_id += 1
      end
      name = "NativeDesktopDropTarget#{id}"
      klass = MacOS::LibNativeDesktopObjCRuntime.allocate_class_pair(superclass, name, 0)
      if klass.null?
        raise NativeDesktop::Error.new("could not create a macOS drop-target view class", :drop_target_unavailable)
      end

      entered = ->(view : Void*, _cmd : Void*, _info : Void*) : UInt64 {
        MacOSDropTargetAdapter.entered(view)
      }
      perform = ->(view : Void*, _cmd : Void*, info : Void*) : Int8 {
        MacOSDropTargetAdapter.perform(view, info)
      }
      o = MacOS::ObjCRuntime
      MacOS::LibNativeDesktopObjCRuntime.add_method(
        klass, o.sel("draggingEntered:"), entered.pointer, "Q@:@"
      )
      MacOS::LibNativeDesktopObjCRuntime.add_method(
        klass, o.sel("performDragOperation:"), perform.pointer, "c@:@"
      )
      MacOS::LibNativeDesktopObjCRuntime.register_class_pair(klass)
      klass
    end

    private def pasteboard_types : Void*
      o = MacOS::ObjCRuntime
      types = o.msg(o.get_class("NSMutableArray"), "array")
      if @kinds.includes?(NativeDesktop::DragKind::Text)
        o.msg_void(types, "addObject:", o.nsstring("public.utf8-plain-text"))
      end
      if @kinds.any? { |kind| kind.file? || kind.image? }
        o.msg_void(types, "addObject:", o.nsstring("public.file-url"))
      end
      if @kinds.includes?(NativeDesktop::DragKind::URL)
        o.msg_void(types, "addObject:", o.nsstring("public.url"))
      end
      types
    end

    private def url_payloads(pasteboard : Void*) : Array(NativeDesktop::DragPayload)
      return [] of NativeDesktop::DragPayload unless @kinds.any? { |kind| kind.file? || kind.image? || kind.url? }

      o = MacOS::ObjCRuntime
      classes = o.msg(o.get_class("NSArray"), "arrayWithObject:", o.get_class("NSURL"))
      urls = o.msg(pasteboard, "readObjectsForClasses:options:", classes, Pointer(Void).null)
      count = o.msg_long(urls, "count")
      payloads = [] of NativeDesktop::DragPayload
      count.times do |index|
        url = o.msg_object_at(urls, "objectAtIndex:", index.to_u64)
        if o.msg_long(url, "isFileURL") != 0
          next unless @kinds.any? { |kind| kind.file? || kind.image? }
          path = nsstring(o.msg(url, "path"))
          next unless path
          kind = @kinds.includes?(NativeDesktop::DragKind::File) ? NativeDesktop::DragKind::File : NativeDesktop::DragKind::Image
          payloads << NativeDesktop::DragPayload.new(kind, path)
        elsif @kinds.includes?(NativeDesktop::DragKind::URL)
          value = nsstring(o.msg(url, "absoluteString"))
          payloads << NativeDesktop::DragPayload.url(value) if value
        end
      end
      payloads
    end

    private def pasteboard_string(pasteboard : Void*, type : String) : String?
      nsstring(MacOS::ObjCRuntime.msg(pasteboard, "stringForType:", MacOS::ObjCRuntime.nsstring(type)))
    end

    private def nsstring(value : Void*) : String?
      return nil if value.null?
      bytes = MacOS::ObjCRuntime.msg_ptr(value, "UTF8String")
      bytes.null? ? nil : String.new(bytes)
    end
  end
end

NativeDesktop::DropTargets.register { NativeDesktop::Platform::MacOSDropTargetAdapter.new }
NativeDesktop::Capabilities.register(
  NativeDesktop::Features::DropTarget,
  NativeDesktop::CapabilityState::Supported
)
