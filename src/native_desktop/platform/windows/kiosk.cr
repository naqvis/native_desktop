require "./win32_common"

module NativeDesktop::Platform::Windows
  class Kiosk
    GWL_STYLE                =            -16
    GWL_EXSTYLE              =            -20
    WS_CAPTION               = 0x00C00000_i64
    WS_THICKFRAME            = 0x00040000_i64
    WS_SYSMENU               = 0x00080000_i64
    WS_MINIMIZEBOX           = 0x00020000_i64
    WS_MAXIMIZEBOX           = 0x00010000_i64
    WS_EX_TOPMOST            = 0x00000008_i64
    WS_EX_DLGMODALFRAME      = 0x00000001_i64
    WS_EX_WINDOWEDGE         = 0x00000100_i64
    WS_EX_CLIENTEDGE         = 0x00000200_i64
    WS_EX_STATICEDGE         = 0x00020000_i64
    MONITOR_DEFAULTTONEAREST =          2_u32
    SWP_NOSIZE               =     0x0001_u32
    SWP_NOMOVE               =     0x0002_u32
    SWP_FRAMECHANGED         =     0x0020_u32
    SWP_SHOWWINDOW           =     0x0040_u32
    HWND_TOPMOST             = Pointer(Void).new(UInt64::MAX)
    HWND_NOTOPMOST           = Pointer(Void).new(UInt64::MAX - 1)

    @active = false
    @saved = false
    @saved_style = 0_i64
    @saved_ex_style = 0_i64
    @placement = LibUser32::WindowPlacement.new

    def initialize(@window : Void*)
    end

    def enter : Nil
      return if @active
      capture_window_state
      monitor = LibUser32.MonitorFromWindow(@window, MONITOR_DEFAULTTONEAREST)
      raise Error.new("could not find the window monitor", :kiosk_unavailable) if monitor.null?
      info = LibUser32::MonitorInfo.new
      info.size = sizeof(LibUser32::MonitorInfo).to_u32
      check(LibUser32.GetMonitorInfoW(monitor, pointerof(info)), "read monitor geometry")

      frame = WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX
      edge = WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE
      LibUser32.SetWindowLongPtrW(@window, GWL_STYLE, @saved_style & ~frame)
      LibUser32.SetWindowLongPtrW(@window, GWL_EXSTYLE, @saved_ex_style & ~edge)
      rect = info.monitor
      check(LibUser32.SetWindowPos(
        @window, HWND_TOPMOST, rect.left, rect.top,
        rect.right - rect.left, rect.bottom - rect.top,
        SWP_FRAMECHANGED | SWP_SHOWWINDOW
      ), "enter kiosk presentation")
      @active = true
    rescue ex
      restore_window_state if @saved
      raise ex
    end

    def exit : Nil
      return unless @active
      restore_window_state
      @active = false
      @saved = false
    end

    def active? : Bool
      @active
    end

    def cleanup : Nil
      exit
    end

    private def capture_window_state : Nil
      @saved_style = LibUser32.GetWindowLongPtrW(@window, GWL_STYLE)
      @saved_ex_style = LibUser32.GetWindowLongPtrW(@window, GWL_EXSTYLE)
      @placement = LibUser32::WindowPlacement.new
      @placement.length = sizeof(LibUser32::WindowPlacement).to_u32
      check(LibUser32.GetWindowPlacement(@window, pointerof(@placement)), "capture window placement")
      @saved = true
    end

    private def restore_window_state : Nil
      LibUser32.SetWindowLongPtrW(@window, GWL_STYLE, @saved_style)
      LibUser32.SetWindowLongPtrW(@window, GWL_EXSTYLE, @saved_ex_style)
      check(LibUser32.SetWindowPlacement(@window, pointerof(@placement)), "restore window placement")
      z_order = @saved_ex_style & WS_EX_TOPMOST != 0 ? HWND_TOPMOST : HWND_NOTOPMOST
      check(LibUser32.SetWindowPos(
        @window, z_order, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_SHOWWINDOW
      ), "restore window frame")
    end

    private def check(result : Int32, operation : String) : Nil
      raise Error.new("could not #{operation}", :kiosk_failed) if result == 0
    end
  end
end
