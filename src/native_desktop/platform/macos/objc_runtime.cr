require "log"

module NativeDesktop
  module Platform
    # Module-level @[Link] annotations force the linker to add `-framework`
    # flags so AppKit/Foundation/CoreFoundation symbols are actually loaded
    # at runtime. Without these, calls like +[NSString stringWithUTF8String:]
    # SIGSEGV inside objc_msgSend because the framework is not loaded.
    @[Link(framework: "Foundation")]
    @[Link(framework: "AppKit")]
    @[Link(framework: "CoreFoundation")]
    @[Link(framework: "UserNotifications")]
    module MacOS
      @[Link("objc")]
      lib LibNativeDesktopObjCFull
        type Id = Void*
        type Sel = Void*
        type Class = Void*

        # :nodoc:
        struct NSPoint
          x : Float64
          y : Float64
        end

        # :nodoc:
        struct NSSize
          width : Float64
          height : Float64
        end

        # :nodoc:
        struct NSRect
          x : Float64
          y : Float64
          w : Float64
          h : Float64
        end

        # Autorelease pool management — required for any AppKit/Foundation call.
      end

      # ObjC runtime functions for creating classes and manipulating objects.
      # Shared by tray and enhanced_window modules.
      # (no @[Link("objc")] — already provided by LibNativeDesktopObjCFull above)
      lib LibNativeDesktopObjCRuntime
        fun allocate_class_pair = native_desktop_objc_allocate_class_pair(superclass : Void*, name : UInt8*, extra_bytes : LibC::SizeT) : Void*
        fun register_class_pair = native_desktop_objc_register_class_pair(cls : Void*) : Nil
        fun add_method = native_desktop_objc_add_method(cls : Void*, sel : Void*, imp : Void*, types : UInt8*) : Int8
        fun object_get_class = native_desktop_objc_object_get_class(object : Void*) : Void*
        fun object_set_class = native_desktop_objc_object_set_class(object : Void*, cls : Void*) : Void*
      end

      # Resolve `objc_msgSend` via the dynamic linker so we can reinterpret
      # the symbol as differently-typed function pointers per call shape.
      lib LibDl
        RTLD_DEFAULT = Pointer(Void).new(UInt64::MAX - 1)
        fun resolve = dlsym(handle : Void*, symbol : UInt8*) : Void*
      end

      # Convenience helpers. All return Void* so callers can store in Void* variables.
      module ObjCRuntime
        private def self.native_selector(name : String) : LibNativeDesktopObjCFull::Sel
          LibNativeObjC.selector(name).as(LibNativeDesktopObjCFull::Sel)
        end

        # Typed Proc aliases for every objc_msgSend call shape we use.
        # Casting the resolved symbol to one of these forces Crystal to
        # emit a non-variadic call with the exact ABI for the shape.
        alias MsgSendIdNoArgs = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id)
        alias MsgSendLongNoArgs = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibC::Long)
        alias MsgSendPtrNoArgs = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, UInt8*)

        alias MsgSendIdId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id)
        alias MsgSendIdLong = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibC::Long, LibNativeDesktopObjCFull::Id)
        alias MsgSendIdULong = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibC::ULong, LibNativeDesktopObjCFull::Id)
        alias MsgSendIdDouble = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, LibNativeDesktopObjCFull::Id)
        alias MsgSendDoubleNoArgs = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64)
        alias MsgSendVoidDouble = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, Void)
        alias MsgSendFloatNoArgs = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float32)
        alias MsgSendVoidFloat = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float32, Void)
        alias MsgSendCharId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, Int8)
        alias MsgSendCharIdIdPtr = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id*, Int8)

        alias MsgSendIdIdId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id)
        alias MsgSendIdUInt32 = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, UInt32, LibNativeDesktopObjCFull::Id)
        alias MsgSendIdPtrULong = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Void*, LibC::ULong, LibNativeDesktopObjCFull::Id)
        alias MsgSendIdIdSelId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id)
        alias MsgSendVoidIdSelUInt32UInt32 = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, UInt32, UInt32, Void)
        alias MsgSendVoidUInt32UInt32 = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, UInt32, UInt32, Void)
        alias MsgSendVoidNoArgs = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Void)
        alias MsgSendBoolId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibC::Long, LibNativeDesktopObjCFull::Id)
        # Send a message returning BOOL (Int8) with (id, id*, id*) arguments,
        # e.g. NSFileManager trashItemAtURL:resultingItemURL:error:.
        alias MsgSendBoolIdIdPtrIdPtr = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id*, LibNativeDesktopObjCFull::Id*, Int8)

        @@msg_send_addr : Void* = Pointer(Void).null

        def self.msg_send_addr : Void*
          if @@msg_send_addr.null?
            addr = LibDl.resolve(LibDl::RTLD_DEFAULT, "objc_msgSend".to_unsafe)
            raise "Failed to resolve objc_msgSend via dlsym" if addr.null?
            @@msg_send_addr = addr
          end
          @@msg_send_addr
        end

        # Send a message with four Void* (object) arguments.
        def self.msg(recv : Void*, sel : String, a : Void*, b : Void*, c : Void*, d : Void*) : Void*
          fn = MsgSendIdIdIdIdId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), a.as(LibNativeDesktopObjCFull::Id), b.as(LibNativeDesktopObjCFull::Id), c.as(LibNativeDesktopObjCFull::Id), d.as(LibNativeDesktopObjCFull::Id)).as(Void*)
        end

        # Send a message with five Void* (object) arguments.
        def self.msg(recv : Void*, sel : String, a : Void*, b : Void*, c : Void*, d : Void*, e : Void*) : Void*
          fn = MsgSendIdIdIdIdIdId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), a.as(LibNativeDesktopObjCFull::Id), b.as(LibNativeDesktopObjCFull::Id), c.as(LibNativeDesktopObjCFull::Id), d.as(LibNativeDesktopObjCFull::Id), e.as(LibNativeDesktopObjCFull::Id)).as(Void*)
        end

        # Send a message with no arguments (returns object pointer).
        def self.msg(recv : Void*, sel : String) : Void*
          fn = MsgSendIdNoArgs.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel)).as(Void*)
        end

        # Send a message with one Void* (object) argument.
        def self.msg(recv : Void*, sel : String, arg : Void*) : Void*
          fn = MsgSendIdId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), arg.as(LibNativeDesktopObjCFull::Id)).as(Void*)
        end

        # Send a message with two Void* (object) arguments.
        def self.msg(recv : Void*, sel : String, a : Void*, b : Void*) : Void*
          fn = MsgSendIdIdId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), a.as(LibNativeDesktopObjCFull::Id), b.as(LibNativeDesktopObjCFull::Id)).as(Void*)
        end

        # Send a message with one signed integer argument (BOOL/NSInteger).
        def self.msg_bool(recv : Void*, sel : String, arg : Int64) : Void*
          fn = MsgSendIdLong.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), LibC::Long.new(arg)).as(Void*)
        end

        # Send a message with one unsigned integer argument (NSUInteger).
        def self.msg_uint(recv : Void*, sel : String, arg : UInt64) : Void*
          fn = MsgSendIdULong.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), LibC::ULong.new(arg)).as(Void*)
        end

        # Send a message with one fixed-width UInt32 argument (OSType/AEKeyword).
        def self.msg_u32(recv : Void*, sel : String, arg : UInt32) : Void*
          fn = MsgSendIdUInt32.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), arg).as(Void*)
        end

        # NSAppleEventManager handler registration uses an object, selector and
        # two fixed-width four-character codes.
        def self.msg_void(recv : Void*, sel : String, handler : Void*, action : Void*, event_class : UInt32, event_id : UInt32) : Nil
          fn = MsgSendVoidIdSelUInt32UInt32.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            recv.as(LibNativeDesktopObjCFull::Id),
            native_selector(sel),
            handler.as(LibNativeDesktopObjCFull::Id),
            action.as(LibNativeDesktopObjCFull::Sel),
            event_class,
            event_id
          )
        end

        def self.msg_void(recv : Void*, sel : String, event_class : UInt32, event_id : UInt32) : Nil
          fn = MsgSendVoidUInt32UInt32.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), event_class, event_id)
        end

        # Send a message with one Float64 argument (CGFloat on 64-bit Macs).
        def self.msg_float(recv : Void*, sel : String, arg : Float64) : Void*
          fn = MsgSendIdDouble.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), arg).as(Void*)
        end

        # Send a message with one Float64 argument and no return value.
        def self.msg_void(recv : Void*, sel : String, arg : Float64) : Nil
          fn = MsgSendVoidDouble.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), arg)
        end

        # Send an object argument to a method returning Objective-C BOOL.
        def self.msg_bool_object(recv : Void*, sel : String, arg : Void*) : Bool
          fn = MsgSendCharId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), arg.as(LibNativeDesktopObjCFull::Id)) != 0
        end

        # Send two object arguments and an NSError** to a method returning BOOL.
        def self.msg_bool_object_object_error(recv : Void*, sel : String, first : Void*, second : Void*, error : Void**) : Bool
          fn = MsgSendCharIdIdPtr.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            recv.as(LibNativeDesktopObjCFull::Id),
            native_selector(sel),
            first.as(LibNativeDesktopObjCFull::Id),
            second.as(LibNativeDesktopObjCFull::Id),
            error.as(LibNativeDesktopObjCFull::Id*)
          ) != 0
        end

        # Send a message returning a CGFloat (Float64), e.g. `backingScaleFactor`.
        def self.msg_double(recv : Void*, sel : String) : Float64
          fn = MsgSendDoubleNoArgs.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel))
        end

        # Send a message returning an Objective-C `float`.
        def self.msg_float(recv : Void*, sel : String) : Float32
          fn = MsgSendFloatNoArgs.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel))
        end

        # Send an Objective-C `float` argument to a method returning void.
        def self.msg_void_float(recv : Void*, sel : String, arg : Float32) : Nil
          fn = MsgSendVoidFloat.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), arg)
        end

        # Send a message returning NSRect (4 doubles in v0-v3), e.g. `frame`.
        def self.msg_rect(recv : Void*, sel : String) : LibNativeDesktopObjCFull::NSRect
          fn = MsgSendNSRect.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel))
        end

        # Send a message returning NSPoint (2 doubles in v0-v1), e.g. `mouseLocation`.
        def self.msg_point(recv : Void*, sel : String) : LibNativeDesktopObjCFull::NSPoint
          fn = MsgSendNSPoint.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel))
        end

        # Send a message returning a signed integer (NSInteger), e.g. `runModal`,
        # `count`, `length`. Use this instead of casting an Id return through a
        # pointer trick — that worked by accident on x86_64 but is unsound on arm64.
        def self.msg_long(recv : Void*, sel : String) : Int64
          fn = MsgSendLongNoArgs.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel)).to_i64
        end

        # Send a message that returns a raw byte pointer (UTF8String, bytes).
        def self.msg_ptr(recv : Void*, sel : String) : UInt8*
          fn = MsgSendPtrNoArgs.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel))
        end

        # objectAtIndex: takes NSUInteger and returns id.
        def self.msg_object_at(recv : Void*, sel : String, index : UInt64) : Void*
          fn = MsgSendIdULong.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), LibC::ULong.new(index)).as(Void*)
        end

        # initWithTitle:action:keyEquivalent: — three-arg init used by NSMenuItem.
        # Takes (NSString*, SEL, NSString*).
        def self.msg_init_menu_item(recv : Void*, sel : String, title : Void*, action_sel : String, key_equiv : Void*) : Void*
          fn = MsgSendIdIdSelId.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            recv.as(LibNativeDesktopObjCFull::Id),
            native_selector(sel),
            title.as(LibNativeDesktopObjCFull::Id),
            native_selector(action_sel),
            key_equiv.as(LibNativeDesktopObjCFull::Id),
          ).as(Void*)
        end

        # initWithTitle:action:keyEquivalent: with nil action (for menu items without actions)
        # Takes (NSString*, nil, NSString*).
        def self.msg_init_menu_item_no_action(recv : Void*, sel : String, title : Void*, key_equiv : Void*) : Void*
          fn = MsgSendIdIdSelId.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            recv.as(LibNativeDesktopObjCFull::Id),
            native_selector(sel),
            title.as(LibNativeDesktopObjCFull::Id),
            Pointer(Void).null.as(LibNativeDesktopObjCFull::Sel), # nil action
            key_equiv.as(LibNativeDesktopObjCFull::Id),
          ).as(Void*)
        end

        # NSData dataWithBytes:length: — pointer + unsigned length.
        def self.msg_data_with_bytes(recv : Void*, sel : String, bytes : Void*, length : UInt64) : Void*
          fn = MsgSendIdPtrULong.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            recv.as(LibNativeDesktopObjCFull::Id),
            native_selector(sel),
            bytes,
            LibC::ULong.new(length),
          ).as(Void*)
        end

        # Send a message with (UInt64, Void*) arguments - used for requestAuthorizationWithOptions:completionHandler:
        alias MsgSendIdULongPtr = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibC::ULong, Void*, LibNativeDesktopObjCFull::Id)

        def self.msg(recv : Void*, sel : String, options : UInt64, handler : Void*) : Void*
          fn = MsgSendIdULongPtr.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            recv.as(LibNativeDesktopObjCFull::Id),
            native_selector(sel),
            LibC::ULong.new(options),
            handler,
          ).as(Void*)
        end

        # Proc alias for initWithSize: etc (2 doubles → id). NSSize on arm64 is 2 doubles in v0/v1.
        alias MsgSendId2Double = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, Float64, LibNativeDesktopObjCFull::Id)

        # Send a message returning id with (double, double) args, e.g. initWithSize:
        def self.msg(recv : Void*, sel : String, x : Float64, y : Float64) : Void*
          fn = MsgSendId2Double.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), x, y).as(Void*)
        end

        # Proc alias for initWithFrame: etc (4 doubles → id).
        alias MsgSendId4Double = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, Float64, Float64, Float64, LibNativeDesktopObjCFull::Id)

        # Send a message returning id with ((double, double, double, double) args,
        # e.g. colorWithRed:green:blue:alpha:
        def self.msg(recv : Void*, sel : String, x : Float64, y : Float64, z : Float64, w : Float64) : Void*
          fn = MsgSendId4Double.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), x, y, z, w).as(Void*)
        end

        # Send a message returning id with (double,double,double,double, ULong, id, id) args
        # for NSTrackingArea initWithRect:options:owner:userInfo: on arm64.
        # NSRect is an HFA of 4 doubles → passed in v0-v3 registers, not by pointer.
        alias MsgSendId4DoubleULongIdId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, Float64, Float64, Float64, LibC::ULong, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id)

        # Send a message with three Void* (object) arguments.
        alias MsgSendIdIdIdId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id)
        alias MsgSendIdIdIdIdId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id)
        alias MsgSendIdIdIdIdIdId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id)

        def self.msg(recv : Void*, sel : String, a : Void*, b : Void*, c : Void*) : Void*
          fn = MsgSendIdIdIdId.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            recv.as(LibNativeDesktopObjCFull::Id),
            native_selector(sel),
            a.as(LibNativeDesktopObjCFull::Id),
            b.as(LibNativeDesktopObjCFull::Id),
            c.as(LibNativeDesktopObjCFull::Id),
          ).as(Void*)
        end

        # Send a message that returns nothing (void return), e.g. miniaturize, orderOut:
        def self.msg_void(recv : Void*, sel : String) : Nil
          fn = MsgSendVoidNoArgs.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel))
        end

        # Send a message that returns nothing, passing an NSPoint as two doubles,
        # e.g. setFrameOrigin:. On arm64 NSPoint{x,y} is passed in x0/x1 as two
        # consecutive CGFloat values.
        alias MsgSendVoidDoubleDouble = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, Float64, Void)

        def self.msg_void(recv : Void*, sel : String, x : Float64, y : Float64) : Nil
          fn = MsgSendVoidDoubleDouble.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), x, y)
        end

        # Send a message that returns nothing, passing an NSRect (4 doubles) and an id,
        # e.g. setDraggingFrame:contents:. On arm64 NSRect is 4 floats in v0-v3, id in x2.
        alias MsgSendVoid4DoubleId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, Float64, Float64, Float64, LibNativeDesktopObjCFull::Id, Void)

        def self.msg_void(recv : Void*, sel : String, x : Float64, y : Float64, w : Float64, h : Float64, contents : Void*) : Nil
          fn = MsgSendVoid4DoubleId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), x, y, w, h, contents.as(LibNativeDesktopObjCFull::Id))
        end

        # Send a message that returns nothing, passing one Void* argument,
        # e.g. didReceiveResponse:, didReceiveData:, addObject:.
        alias MsgSendVoidId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, Void)

        def self.msg_void(recv : Void*, sel : String, arg : Void*) : Nil
          fn = MsgSendVoidId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), arg.as(LibNativeDesktopObjCFull::Id))
        end

        # Send a message with (Void*, double, double, Void*) args and void return,
        # e.g. popUpMenuPositioningItem:atLocation:inView: on arm64 where NSPoint
        # is passed as two consecutive Float64 values in x3/x4 registers.
        alias MsgSendVoidIdDoubleDoubleId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, Float64, Float64, LibNativeDesktopObjCFull::Id, Void)

        def self.msg_void(recv : Void*, sel : String, a : Void*, x : Float64, y : Float64, b : Void*) : Nil
          fn = MsgSendVoidIdDoubleDoubleId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), a.as(LibNativeDesktopObjCFull::Id), x, y, b.as(LibNativeDesktopObjCFull::Id))
        end

        # Send a message that returns nothing, passing two Void* arguments,
        # e.g. setURLSchemeHandler:forURLScheme:, setObject:forKey:.
        alias MsgSendVoidIdId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, Void)

        def self.msg_void(recv : Void*, sel : String, a : Void*, b : Void*) : Nil
          fn = MsgSendVoidIdId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), a.as(LibNativeDesktopObjCFull::Id), b.as(LibNativeDesktopObjCFull::Id))
        end

        # Send a message that returns nothing, passing a SEL, id, and double,
        # e.g. performSelector:withObject:afterDelay:.
        alias MsgSendVoidSelIdDouble = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, Float64, Void)

        def self.msg_void(recv : Void*, sel : String, a : Void*, b : Void*, delay : Float64) : Nil
          fn = MsgSendVoidSelIdDouble.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), a.as(LibNativeDesktopObjCFull::Sel), b.as(LibNativeDesktopObjCFull::Id), delay)
        end

        # Send a message with one Int64 argument and void return,
        # e.g. setOpaque:, setLevel:, setIgnoresMouseEvents:.
        def self.msg_int(recv : Void*, sel : String, arg : Int64) : Nil
          fn = MsgSendBoolId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), LibC::Long.new(arg))
          nil
        end

        # Send a message returning BOOL (Int8) with (id, id*, id*) arguments,
        # e.g. NSFileManager trashItemAtURL:resultingItemURL:error:.
        # *out_url* and *out_err* are `Void**` out-parameters; pass
        # `Pointer(Void).null` when the result is not needed.
        def self.msg_bool_ptr(recv : Void*, sel : String, arg : Void*, out_url : Void**, out_err : Void**) : Int8
          fn = MsgSendBoolIdIdPtrIdPtr.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            recv.as(LibNativeDesktopObjCFull::Id),
            native_selector(sel),
            arg.as(LibNativeDesktopObjCFull::Id),
            out_url.as(LibNativeDesktopObjCFull::Id*),
            out_err.as(LibNativeDesktopObjCFull::Id*),
          )
        end

        # Send a message that returns a signed integer (NSInteger/BOOL),
        # with one Int64 argument, e.g. setLevel: returning old level.
        alias MsgSendLongLong = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibC::Long, LibC::Long)

        def self.msg_long_ret(recv : Void*, sel : String, arg : Int64) : Int64
          fn = MsgSendLongLong.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), LibC::Long.new(arg))
        end

        # Helper to convert UInt64 to Void* for passing as argument
        def self.void_ptr_from_uint64(val : UInt64) : Void*
          Pointer(Void).new(val)
        end

        # Get an ObjC class by name, returned as Void*.
        def self.get_class(name : String) : Void*
          LibNativeObjC.get_class(name).as(Void*)
        end

        # Create an NSString from a Crystal String. Uses the typed
        # (Class, SEL, char*) form so the arm64 ABI is correct.
        def self.nsstring(s : String) : Void*
          fn = MsgSendIdId.new(msg_send_addr, Pointer(Void).null)
          fn.call(
            LibNativeObjC.get_class("NSString").as(LibNativeDesktopObjCFull::Id),
            native_selector("stringWithUTF8String:"),
            s.to_unsafe.as(LibNativeDesktopObjCFull::Id),
          ).as(Void*)
        end

        # Convert an NSString (Void*) to a Crystal String, or nil.
        def self.nsstring_to_s(ns : Void*) : String?
          return nil if ns.null?
          ptr = msg_ptr(ns, "UTF8String")
          return nil if ptr.null?
          String.new(ptr)
        end

        # Proc aliases for objc_msgSend with NSRect (4 doubles on arm64).
        alias MsgSendNSRect = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::NSRect)
        alias MsgSendVoidNSRect = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::NSRect, Void)
        # Proc alias for NSPoint return (2 doubles on arm64).
        alias MsgSendNSPoint = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::NSPoint)

        # ConvertPoint:toView: — takes NSPoint (2 doubles) + view, returns NSPoint.
        alias MsgSendNSPointDoubleDoubleId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, Float64, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::NSPoint)

        # convertRectToScreen: — takes NSRect (4 doubles), returns NSRect.
        alias MsgSendNSRect4Double = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, Float64, Float64, Float64, Float64, LibNativeDesktopObjCFull::NSRect)

        # popUpContextMenu:withEvent:forView: — class method on NSMenu.
        # (id, SEL, menu, event, view) -> void
        alias MsgSendVoidIdIdId = Proc(LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Sel, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, LibNativeDesktopObjCFull::Id, Void)

        # Convert an NSPoint from one view's coordinate system to another's.
        def self.msg_convert_point(recv : Void*, sel : String, x : Float64, y : Float64, to_view : Void*) : LibNativeDesktopObjCFull::NSPoint
          fn = MsgSendNSPointDoubleDoubleId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), x, y, to_view.as(LibNativeDesktopObjCFull::Id))
        end

        # Convert an NSRect from window coordinates to screen coordinates.
        def self.msg_convert_rect_to_screen(recv : Void*, sel : String, x : Float64, y : Float64, w : Float64, h : Float64) : LibNativeDesktopObjCFull::NSRect
          fn = MsgSendNSRect4Double.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), x, y, w, h)
        end

        # popUpContextMenu:withEvent:forView: — class method on NSMenu.
        def self.msg_popup_context_menu(recv : Void*, sel : String, menu : Void*, event : Void*, view : Void*) : Nil
          fn = MsgSendVoidIdIdId.new(msg_send_addr, Pointer(Void).null)
          fn.call(recv.as(LibNativeDesktopObjCFull::Id), native_selector(sel), menu.as(LibNativeDesktopObjCFull::Id), event.as(LibNativeDesktopObjCFull::Id), view.as(LibNativeDesktopObjCFull::Id))
        end

        # Create an NSMutableArray from an array of Crystal strings.
        def self.nsarray_from_strings(strings : Array(String)) : Void*
          arr = msg(msg(get_class("NSMutableArray"), "alloc"), "init")
          strings.each do |string|
            msg(arr, "addObject:", nsstring(string))
          end
          arr
        end

        # Register a selector and return as Void* (for passing as an argument).
        def self.sel(name : String) : Void*
          native_selector(name).as(Void*)
        end

        # Run a block inside an autorelease pool. Required for any AppKit/Foundation
        # call from a thread that does not already have an active pool (e.g. spec
        # runner). Without this, NSString/NSObject methods crash with SIGSEGV
        # because there is no pool to retain temporary objects.
        def self.with_autorelease_pool(&)
          pool = LibNativeObjC.pool_push
          begin
            yield
          ensure
            LibNativeObjC.pool_pop(pool)
          end
        end
      end
    end
  end
end
