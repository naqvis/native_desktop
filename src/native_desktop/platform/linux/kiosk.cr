module NativeDesktop::Platform::Linux
  @[Link("gtk-3", pkg_config: "gtk+-3.0")]
  lib LibGTKTaskbarKiosk
    fun gtk_window_get_decorated(window : Void*) : Int32
    fun gtk_window_set_decorated(window : Void*, setting : Int32) : Nil
    fun gtk_window_fullscreen(window : Void*) : Nil
    fun gtk_window_unfullscreen(window : Void*) : Nil
    fun gtk_widget_get_window(widget : Void*) : Void*
  end

  @[Link("gdk-3", pkg_config: "gdk-3.0")]
  lib LibGDKTaskbarKiosk
    fun gdk_window_get_state(window : Void*) : UInt32
  end

  class Kiosk
    FULLSCREEN_STATE = 1_u32 << 4

    @active = false
    @saved_decorated = true
    @entered_fullscreen = false

    def initialize(@window : Void*)
    end

    def enter : Nil
      return if @active
      @saved_decorated = LibGTKTaskbarKiosk.gtk_window_get_decorated(@window) != 0
      native_window = LibGTKTaskbarKiosk.gtk_widget_get_window(@window)
      fullscreen = !native_window.null? && LibGDKTaskbarKiosk.gdk_window_get_state(native_window) & FULLSCREEN_STATE != 0

      LibGTKTaskbarKiosk.gtk_window_set_decorated(@window, 0)
      unless fullscreen
        LibGTKTaskbarKiosk.gtk_window_fullscreen(@window)
        @entered_fullscreen = true
      end
      @active = true
    end

    def exit : Nil
      return unless @active
      LibGTKTaskbarKiosk.gtk_window_unfullscreen(@window) if @entered_fullscreen
      LibGTKTaskbarKiosk.gtk_window_set_decorated(@window, @saved_decorated ? 1 : 0)
      @entered_fullscreen = false
      @active = false
    end

    def active? : Bool
      @active
    end

    def cleanup : Nil
      exit
    end
  end
end
