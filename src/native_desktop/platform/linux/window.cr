{% if flag?(:linux) %}
  module NativeDesktop::Platform::Window
    extend self

    @[Link("gtk-3", pkg_config: "gtk+-3.0")]
    lib LibGTK
      fun gtk_window_set_keep_above(window : Void*, setting : Int32) : Nil
      fun gtk_window_set_decorated(window : Void*, setting : Int32) : Nil
      fun gtk_window_move(window : Void*, x : Int32, y : Int32) : Nil
      fun gtk_window_get_position(window : Void*, x : Int32*, y : Int32*) : Nil
      fun gtk_window_present(window : Void*) : Nil
      fun gtk_window_set_opacity(window : Void*, opacity : Float64) : Nil
      fun gtk_window_set_modal(window : Void*, setting : Int32) : Nil
      fun gtk_window_iconify(window : Void*) : Nil
      fun gtk_window_deiconify(window : Void*) : Nil
      fun gtk_window_maximize(window : Void*) : Nil
      fun gtk_window_unmaximize(window : Void*) : Nil
      fun gtk_window_fullscreen(window : Void*) : Nil
      fun gtk_window_unfullscreen(window : Void*) : Nil
      fun gtk_window_is_maximized(window : Void*) : Int32
    end

    lib LibGTKWidget
      fun gtk_widget_show_all(widget : Void*) : Nil
      fun gtk_widget_hide(widget : Void*) : Nil
      fun gtk_widget_get_visible(widget : Void*) : Int32
    end

    def set_titlebar_overlay(handle : Void*, enabled : Bool) : Nil
      LibGTK.gtk_window_set_decorated(handle, enabled ? 0 : 1)
    end

    def set_always_on_top(handle : Void*, enabled : Bool) : Nil
      LibGTK.gtk_window_set_keep_above(handle, enabled ? 1 : 0)
    end

    def move(handle : Void*, x : Int32, y : Int32) : Nil
      LibGTK.gtk_window_move(handle, x, y)
    end

    def position(handle : Void*) : {Int32, Int32}
      x = uninitialized Int32
      y = uninitialized Int32
      LibGTK.gtk_window_get_position(handle, pointerof(x), pointerof(y))
      {x, y}
    end

    def focus(handle : Void*) : Nil
      LibGTK.gtk_window_present(handle)
    end

    def show(handle : Void*) : Nil
      LibGTKWidget.gtk_widget_show_all(handle)
    end

    def hide(handle : Void*) : Nil
      LibGTKWidget.gtk_widget_hide(handle)
    end

    def minimize(handle : Void*) : Nil
      LibGTK.gtk_window_iconify(handle)
    end

    def maximize(handle : Void*) : Nil
      LibGTK.gtk_window_maximize(handle)
    end

    def restore(handle : Void*) : Nil
      LibGTK.gtk_window_deiconify(handle)
      LibGTK.gtk_window_unmaximize(handle)
    end

    def minimized?(handle : Void*) : Bool
      LibGTK.gtk_window_is_maximized(handle) == 0
    end

    def maximized?(handle : Void*) : Bool
      LibGTK.gtk_window_is_maximized(handle) != 0
    end

    def set_fullscreen(handle : Void*, value : Bool) : Nil
      if value
        LibGTK.gtk_window_fullscreen(handle)
      else
        LibGTK.gtk_window_unfullscreen(handle)
      end
    end

    def set_frameless(handle : Void*, value : Bool) : Nil
      was_visible = LibGTKWidget.gtk_widget_get_visible(handle)
      if was_visible != 0
        LibGTKWidget.gtk_widget_hide(handle)
      end
      LibGTK.gtk_window_set_decorated(handle, value ? 0 : 1)
      if was_visible != 0
        LibGTKWidget.gtk_widget_show_all(handle)
      end
    end

    def set_transparent(handle : Void*, value : Bool) : Nil
      LibGTK.gtk_window_set_opacity(handle, value ? 0.0 : 1.0)
    end

    def set_opacity(handle : Void*, value : Float64) : Nil
      LibGTK.gtk_window_set_opacity(handle, value)
    end

    def set_modal(parent : Void*, child : Void*, value : Bool) : Nil
      return if child.null?
      LibGTK.gtk_window_set_modal(child, value ? 1 : 0)
    end
  end
{% end %}
