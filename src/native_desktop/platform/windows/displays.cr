{% if flag?(:windows) %}
  require "./win32_common"

  module NativeDesktop::Platform::Displays
    extend self

    def all : Array(Display)
      displays = [] of Display
      boxed = Box.box(displays)
      callback = ->(monitor : Void*, _hdc : Void*, _rect : Windows::LibUser32::Rect*, data : Int64) {
        target = Box(Array(Display)).unbox(Pointer(Void).new(data.to_u64!))
        info = Windows::LibUser32::MonitorInfo.new
        info.size = sizeof(Windows::LibUser32::MonitorInfo).to_u32
        if Windows::LibUser32.GetMonitorInfoW(monitor, pointerof(info)) != 0
          index = target.size + 1
          target << Display.new(
            rectangle(info.monitor),
            rectangle(info.work),
            (info.flags & 1) != 0,
            "Display #{index}",
            scale_factor(monitor),
          )
        end
        1
      }
      result = Windows::LibUser32.EnumDisplayMonitors(
        Pointer(Void).null,
        Pointer(Windows::LibUser32::Rect).null,
        callback,
        boxed.address.to_i64!
      )
      raise Error.new("EnumDisplayMonitors failed", :native_call_failed) if result == 0
      raise Error.new("Windows reported no connected displays", :native_call_failed) if displays.empty?
      displays.sort_by! { |display| display.primary? ? 0 : 1 }
    end

    def cursor : ::NativeDesktop::Point
      point = Windows::LibUser32::Point.new
      Windows::LibUser32.GetCursorPos(pointerof(point)) == 0 ? ::NativeDesktop::Point.new : ::NativeDesktop::Point.new(x: point.x, y: point.y)
    end

    private def rectangle(value : Windows::LibUser32::Rect) : Rectangle
      Rectangle.new(value.left, value.top, value.right - value.left, value.bottom - value.top)
    end

    private def scale_factor(monitor : Void*) : Float64
      x = 96_u32
      y = 96_u32
      return 1.0 unless Windows::LibShcore.GetDpiForMonitor(monitor, 0_u32, pointerof(x), pointerof(y)) == 0
      scale = x.to_f64 / 96.0
      scale.finite? && scale > 0 ? scale : 1.0
    end
  end
{% end %}
