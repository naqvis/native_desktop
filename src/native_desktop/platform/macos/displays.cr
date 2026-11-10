{% if flag?(:darwin) %}
  require "./objc_runtime"

  module NativeDesktop::Platform::Displays
    extend self
    MAX_DISPLAYS = 64

    @[Link(framework: "CoreGraphics")]
    lib LibCoreGraphicsDisplays
      struct Point
        x : Float64
        y : Float64
      end

      struct Size
        width : Float64
        height : Float64
      end

      struct Rect
        origin : Point
        size : Size
      end

      fun CGGetActiveDisplayList(maximum : UInt32, displays : UInt32*, count : UInt32*) : Int32
      fun CGDisplayBounds(display : UInt32) : Rect
      fun CGDisplayPixelsWide(display : UInt32) : LibC::SizeT
      fun CGMainDisplayID : UInt32
      fun CGEventCreate(source : Void*) : Void*
      fun CGEventGetLocation(event : Void*) : Point
    end

    @[Link(framework: "CoreFoundation")]
    lib LibCoreFoundationDisplays
      fun CFRelease(value : Void*) : Nil
    end

    def all : Array(Display)
      ids = Pointer(UInt32).malloc(MAX_DISPLAYS)
      count = 0_u32
      return fallback unless LibCoreGraphicsDisplays.CGGetActiveDisplayList(MAX_DISPLAYS, ids, pointerof(count)) == 0 && count > 0
      main = LibCoreGraphicsDisplays.CGMainDisplayID

      MacOS::ObjCRuntime.with_autorelease_pool do
        Array(Display).new(count.to_i) do |index|
          id = ids[index]
          frame = LibCoreGraphicsDisplays.CGDisplayBounds(id)
          bounds = Rectangle.new(frame.origin.x.to_i32, frame.origin.y.to_i32, frame.size.width.to_i32, frame.size.height.to_i32)
          work = id == main ? Rectangle.new(bounds.x, bounds.y + 25, bounds.width, bounds.height - 25) : bounds
          name, scale = metadata(id, index, frame.size.width)
          Display.new(bounds, work, id == main, name, scale)
        end
      end
    rescue
      fallback
    end

    def cursor : Point
      event = LibCoreGraphicsDisplays.CGEventCreate(Pointer(Void).null)
      return Point.new if event.null?
      begin
        location = LibCoreGraphicsDisplays.CGEventGetLocation(event)
        Point.new(location.x.to_i32, location.y.to_i32)
      ensure
        LibCoreFoundationDisplays.CFRelease(event)
      end
    end

    private def fallback : Array(Display)
      bounds = Rectangle.new(0, 0, 1920, 1080)
      [Display.new(bounds, Rectangle.new(0, 25, 1920, 1055), true, "Main Display")]
    end

    private def metadata(id : UInt32, index : Int32, logical_width : Float64) : {String, Float64}
      screens = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSScreen"), "screens")
      unless screens.null?
        MacOS::ObjCRuntime.msg_long(screens, "count").times do |screen_index|
          screen = MacOS::ObjCRuntime.msg_object_at(screens, "objectAtIndex:", screen_index.to_u64)
          next if screen.null?
          description = MacOS::ObjCRuntime.msg(screen, "deviceDescription")
          next if description.null?
          number = MacOS::ObjCRuntime.msg(description, "objectForKey:", MacOS::ObjCRuntime.nsstring("NSScreenNumber"))
          next if number.null? || MacOS::ObjCRuntime.msg_long(number, "unsignedIntValue").to_u32 != id
          name = MacOS::ObjCRuntime.nsstring_to_s(MacOS::ObjCRuntime.msg(screen, "localizedName")) || "Display #{index + 1}"
          scale = MacOS::ObjCRuntime.msg_double(screen, "backingScaleFactor")
          return {name, scale} if scale.finite? && scale > 0
        end
      end

      pixels = LibCoreGraphicsDisplays.CGDisplayPixelsWide(id).to_f64
      scale = logical_width > 0 ? pixels / logical_width : 1.0
      scale = 1.0 unless scale.finite? && scale > 0
      {id == LibCoreGraphicsDisplays.CGMainDisplayID ? "Main Display" : "Display #{index + 1}", scale}
    end
  end
{% end %}
