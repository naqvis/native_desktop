{% if flag?(:linux) %}
  module NativeDesktop::Platform::WindowEffects
    extend self

    @[Link("gdk-3", pkg_config: "gdk-3.0")]
    lib LibGDKWindowEffects
      fun gtk_widget_get_window(widget : Void*) : Void*
      fun gdk_x11_window_get_xid(window : Void*) : LibC::ULong
    end

    @[Link("X11", pkg_config: "x11")]
    lib LibX11WindowEffects
      alias Display = Void
      alias Window = LibC::ULong
      alias Atom = LibC::ULong

      fun XOpenDisplay(name : UInt8*) : Display*
      fun XCloseDisplay(display : Display*) : Int32
      fun XInternAtom(display : Display*, name : UInt8*, only_if_exists : Int32) : Atom
      fun XChangeProperty(display : Display*, window : Window, property : Atom, type : Atom, format : Int32, mode : Int32, data : UInt8*, count : Int32) : Int32
      fun XFlush(display : Display*) : Int32
    end

    def apply(window : Void*, effects : NativeDesktop::WindowEffects) : Nil
      return unless effects.blur_behind
      gdk_window = LibGDKWindowEffects.gtk_widget_get_window(window)
      return if gdk_window.null?

      display = LibX11WindowEffects.XOpenDisplay(Pointer(UInt8).null)
      return if display.null?
      begin
        atom = LibX11WindowEffects.XInternAtom(display, "_KDE_NET_WM_BLUR_BEHIND_REGION", 0)
        return if atom == 0
        xid = LibGDKWindowEffects.gdk_x11_window_get_xid(gdk_window)
        LibX11WindowEffects.XChangeProperty(display, xid, atom, atom, 32, 0, Pointer(UInt8).null, 0)
        LibX11WindowEffects.XFlush(display)
      ensure
        LibX11WindowEffects.XCloseDisplay(display)
      end
    end
  end
{% end %}
