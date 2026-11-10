require "log"

module NativeDesktop::Platform::Idle
  extend self

  @[Link("X11", pkg_config: "x11")]
  lib LibX11IdleTime
    fun XOpenDisplay(name : UInt8*) : Void*
    fun XCloseDisplay(display : Void*) : Int32
    fun XDefaultRootWindow(display : Void*) : LibC::ULong
    fun XFree(data : Void*) : Int32
  end

  @[Link("Xss", pkg_config: "xscrnsaver")]
  lib LibXScreenSaverIdleTime
    struct Info
      window : LibC::ULong
      state : Int32
      kind : Int32
      til_or_since : LibC::ULong
      idle : LibC::ULong
      event_mask : LibC::ULong
    end

    fun XScreenSaverAllocInfo : Info*
    fun XScreenSaverQueryInfo(display : Void*, drawable : LibC::ULong, info : Info*) : Int32
  end

  def duration : Time::Span
    display = LibX11IdleTime.XOpenDisplay(Pointer(UInt8).null)
    return 0.seconds if display.null?
    begin
      info = LibXScreenSaverIdleTime.XScreenSaverAllocInfo
      return 0.seconds if info.null?
      begin
        root = LibX11IdleTime.XDefaultRootWindow(display)
        return 0.seconds if LibXScreenSaverIdleTime.XScreenSaverQueryInfo(display, root, info) == 0
        (info.value.idle.to_f64 / 1000.0).seconds
      ensure
        LibX11IdleTime.XFree(info.as(Void*))
      end
    ensure
      LibX11IdleTime.XCloseDisplay(display)
    end
  rescue ex
    Log.warn(exception: ex) { "could not read X11 idle time" }
    0.seconds
  end
end
