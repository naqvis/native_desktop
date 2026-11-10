{% if flag?(:windows) %}
  require "./win32_common"

  module NativeDesktop::Platform::Window
    extend self

    HWND_TOPMOST             = Pointer(Void).new(UInt64::MAX)
    HWND_NOTOPMOST           = Pointer(Void).new(UInt64::MAX - 1)
    SWP_NOSIZE               =     0x0001_u32
    SWP_NOMOVE               =     0x0002_u32
    SWP_NOACTIVATE           =     0x0010_u32
    SWP_NOZORDER             =     0x0004_u32
    SWP_FRAMECHANGED         =     0x0020_u32
    SWP_SHOWWINDOW           =     0x0040_u32
    GWL_STYLE                =            -16
    GWL_EXSTYLE              =            -20
    WS_CAPTION               = 0x00C00000_i64
    WS_THICKFRAME            = 0x00040000_i64
    WS_SYSMENU               = 0x00080000_i64
    SW_HIDE                  =              0
    SW_SHOW                  =              5
    SW_MINIMIZE              =              6
    SW_MAXIMIZE              =              3
    SW_RESTORE               =              9
    WS_EX_LAYERED            = 0x00080000_u32
    LWA_ALPHA                = 0x00000002_u32
    MONITOR_DEFAULTTONEAREST =          2_u32

    private record FullscreenState,
      style : Int64,
      placement : Windows::LibUser32::WindowPlacement

    @@fullscreen_states = {} of UInt64 => FullscreenState

    def set_always_on_top(handle : Void*, enabled : Bool) : Nil
      after = enabled ? HWND_TOPMOST : HWND_NOTOPMOST
      result = Windows::LibUser32.SetWindowPos(handle, after, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
      raise Error.new("SetWindowPos failed", :native_call_failed) if result == 0
    end

    def set_titlebar_overlay(handle : Void*, enabled : Bool) : Nil
      style = Windows::LibUser32.GetWindowLongPtrW(handle, GWL_STYLE)
      frame = WS_CAPTION | WS_THICKFRAME | WS_SYSMENU
      updated = enabled ? style & ~frame : style | frame
      Windows::LibUser32.SetWindowLongPtrW(handle, GWL_STYLE, updated)
      result = Windows::LibUser32.SetWindowPos(handle, Pointer(Void).null, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)
      raise Error.new("SetWindowPos failed", :native_call_failed) if result == 0
    end

    def move(handle : Void*, x : Int32, y : Int32) : Nil
      Windows::LibUser32.SetWindowPos(handle, Pointer(Void).null, x, y, 0, 0,
        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE)
    end

    def position(handle : Void*) : {Int32, Int32}
      rect = Windows::LibUser32::Rect.new
      Windows::LibUser32.GetWindowRect(handle, pointerof(rect))
      {rect.left, rect.top}
    end

    def focus(handle : Void*) : Nil
      Windows::LibUser32.SetForegroundWindow(handle)
    end

    def show(handle : Void*) : Nil
      Windows::LibUser32.ShowWindow(handle, SW_SHOW)
      Windows::LibUser32.SetForegroundWindow(handle)
    end

    def hide(handle : Void*) : Nil
      Windows::LibUser32.ShowWindow(handle, SW_HIDE)
    end

    def minimize(handle : Void*) : Nil
      Windows::LibUser32.ShowWindow(handle, SW_MINIMIZE)
    end

    def maximize(handle : Void*) : Nil
      Windows::LibUser32.ShowWindow(handle, SW_MAXIMIZE)
    end

    def restore(handle : Void*) : Nil
      Windows::LibUser32.ShowWindow(handle, SW_RESTORE)
    end

    def set_fullscreen(handle : Void*, value : Bool) : Nil
      if value
        return if @@fullscreen_states.has_key?(handle.address)
        style = Windows::LibUser32.GetWindowLongPtrW(handle, GWL_STYLE)
        placement = Windows::LibUser32::WindowPlacement.new
        placement.length = sizeof(Windows::LibUser32::WindowPlacement).to_u32
        raise Error.new("GetWindowPlacement failed", :native_call_failed) if Windows::LibUser32.GetWindowPlacement(handle, pointerof(placement)) == 0

        monitor = Windows::LibUser32.MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST)
        raise Error.new("MonitorFromWindow failed", :native_call_failed) if monitor.null?
        info = Windows::LibUser32::MonitorInfo.new
        info.size = sizeof(Windows::LibUser32::MonitorInfo).to_u32
        raise Error.new("GetMonitorInfoW failed", :native_call_failed) if Windows::LibUser32.GetMonitorInfoW(monitor, pointerof(info)) == 0

        @@fullscreen_states[handle.address] = FullscreenState.new(style, placement)
        frame = WS_CAPTION | WS_THICKFRAME | WS_SYSMENU
        Windows::LibUser32.SetWindowLongPtrW(handle, GWL_STYLE, style & ~frame)
        bounds = info.monitor
        result = Windows::LibUser32.SetWindowPos(
          handle, Pointer(Void).null,
          bounds.left, bounds.top, bounds.right - bounds.left, bounds.bottom - bounds.top,
          SWP_NOZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW
        )
        raise Error.new("SetWindowPos failed", :native_call_failed) if result == 0
      else
        return unless state = @@fullscreen_states.delete(handle.address)
        Windows::LibUser32.SetWindowLongPtrW(handle, GWL_STYLE, state.style)
        placement = state.placement
        raise Error.new("SetWindowPlacement failed", :native_call_failed) if Windows::LibUser32.SetWindowPlacement(handle, pointerof(placement)) == 0
        result = Windows::LibUser32.SetWindowPos(
          handle, Pointer(Void).null, 0, 0, 0, 0,
          SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW
        )
        raise Error.new("SetWindowPos failed", :native_call_failed) if result == 0
      end
    end

    def set_frameless(handle : Void*, value : Bool) : Nil
      style = Windows::LibUser32.GetWindowLongPtrW(handle, GWL_STYLE)
      frame = WS_CAPTION | WS_THICKFRAME | WS_SYSMENU
      updated = value ? style & ~frame : style | frame
      Windows::LibUser32.SetWindowLongPtrW(handle, GWL_STYLE, updated)
      Windows::LibUser32.SetWindowPos(handle, Pointer(Void).null, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)
    end

    def set_transparent(handle : Void*, value : Bool) : Nil
      style = Windows::LibUser32.GetWindowLongPtrW(handle, GWL_EXSTYLE)
      if value
        Windows::LibUser32.SetWindowLongPtrW(handle, GWL_EXSTYLE, style | WS_EX_LAYERED.to_i64)
        Windows::LibUser32.SetLayeredWindowAttributes(handle, 0, 255, LWA_ALPHA)
      else
        Windows::LibUser32.SetWindowLongPtrW(handle, GWL_EXSTYLE, style & ~WS_EX_LAYERED.to_i64)
      end
    end

    def set_opacity(handle : Void*, value : Float64) : Nil
      style = Windows::LibUser32.GetWindowLongPtrW(handle, GWL_EXSTYLE)
      Windows::LibUser32.SetWindowLongPtrW(handle, GWL_EXSTYLE, style | WS_EX_LAYERED.to_i64)
      Windows::LibUser32.SetLayeredWindowAttributes(handle, 0, (value.clamp(0.0, 1.0) * 255).to_u8, LWA_ALPHA)
    end

    def set_modal(handle : Void*, child : Void*, value : Bool) : Nil
      Windows::LibUser32.EnableWindow(handle, value ? 0 : 1)
    end
  end
{% end %}
