{% if flag?(:linux) %}
  module NativeDesktop::Platform::Displays
    extend self

    @[Link("gdk-3", pkg_config: "gdk-3.0")]
    lib LibGDKDisplays
      struct Rect
        x : Int32
        y : Int32
        width : Int32
        height : Int32
      end

      fun gdk_display_get_default : Void*
      fun gdk_display_get_n_monitors(display : Void*) : Int32
      fun gdk_display_get_monitor(display : Void*, index : Int32) : Void*
      fun gdk_monitor_get_geometry(monitor : Void*, rectangle : Rect*) : Nil
      fun gdk_monitor_get_workarea(monitor : Void*, rectangle : Rect*) : Nil
      fun gdk_monitor_is_primary(monitor : Void*) : Int32
      fun gdk_monitor_get_scale_factor(monitor : Void*) : Int32
      fun gdk_monitor_get_model(monitor : Void*) : UInt8*
      fun gdk_display_get_default_seat(display : Void*) : Void*
      fun gdk_seat_get_pointer(seat : Void*) : Void*
      fun gdk_device_get_position(device : Void*, screen : Void**, x : Int32*, y : Int32*) : Nil
    end

    def all : Array(Display)
      display = LibGDKDisplays.gdk_display_get_default
      return fallback if display.null?
      count = LibGDKDisplays.gdk_display_get_n_monitors(display)
      return fallback if count <= 0

      Array(Display).new(count) do |index|
        monitor = LibGDKDisplays.gdk_display_get_monitor(display, index)
        geometry = LibGDKDisplays::Rect.new
        work = LibGDKDisplays::Rect.new
        LibGDKDisplays.gdk_monitor_get_geometry(monitor, pointerof(geometry))
        LibGDKDisplays.gdk_monitor_get_workarea(monitor, pointerof(work))
        name_ptr = LibGDKDisplays.gdk_monitor_get_model(monitor)
        name = name_ptr.null? ? "Display #{index + 1}" : String.new(name_ptr)
        scale = LibGDKDisplays.gdk_monitor_get_scale_factor(monitor).to_f64
        scale = 1.0 unless scale.finite? && scale > 0
        Display.new(rectangle(geometry), rectangle(work), LibGDKDisplays.gdk_monitor_is_primary(monitor) != 0, name, scale)
      end
    rescue
      fallback
    end

    def cursor : Point
      display = LibGDKDisplays.gdk_display_get_default
      return Point.new if display.null?
      seat = LibGDKDisplays.gdk_display_get_default_seat(display)
      return Point.new if seat.null?
      device = LibGDKDisplays.gdk_seat_get_pointer(seat)
      return Point.new if device.null?
      x = 0
      y = 0
      LibGDKDisplays.gdk_device_get_position(device, nil, pointerof(x), pointerof(y))
      Point.new(x, y)
    rescue
      Point.new
    end

    private def rectangle(value : LibGDKDisplays::Rect) : Rectangle
      Rectangle.new(value.x, value.y, value.width, value.height)
    end

    private def fallback : Array(Display)
      bounds = Rectangle.new(0, 0, 1920, 1080)
      [Display.new(bounds, bounds, true, "Display 1")]
    end
  end
{% end %}
