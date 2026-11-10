{% if flag?(:darwin) %}
  require "./objc"

  @[Link(ldflags: "#{__DIR__}/macos_window.m -framework Cocoa")]
  lib LibNativeWindow
    fun nd_window_move(handle : Void*, x : Float64, y : Float64) : Nil
    fun nd_window_position_x(handle : Void*) : Float64
    fun nd_window_position_y(handle : Void*) : Float64
    fun nd_window_set_alpha(handle : Void*, value : Float64) : Nil
    fun nd_window_order_front(handle : Void*) : Nil
    fun nd_window_show(handle : Void*) : Nil
    fun nd_window_hide(handle : Void*) : Nil
    fun nd_window_minimize(handle : Void*) : Nil
    fun nd_window_maximize(handle : Void*) : Nil
    fun nd_window_restore(handle : Void*) : Nil
    fun nd_window_is_minimized(handle : Void*) : Int32
    fun nd_window_is_maximized(handle : Void*) : Int32
    fun nd_window_is_fullscreen(handle : Void*) : Int32
    fun nd_window_toggle_fullscreen(handle : Void*) : Nil
    fun nd_window_set_fullscreen(handle : Void*, fullscreen : Int32) : Nil
    fun nd_window_set_frameless(handle : Void*, frameless : Int32) : Nil
    fun nd_window_is_frameless(handle : Void*) : Int32
    fun nd_window_set_transparent(handle : Void*, transparent : Int32) : Nil
    fun nd_window_set_modal(parent : Void*, child : Void*, modal : Int32) : Nil
    fun nd_window_set_accepts_mouse_events(handle : Void*, accepts : Int32) : Nil
  end

  module NativeDesktop::Platform::Window
    extend self

    NS_NORMAL_WINDOW_LEVEL    =     0_i64
    NS_FLOATING_WINDOW_LEVEL  =     3_i64
    NS_FULL_SIZE_CONTENT_VIEW = 32768_i64

    def set_always_on_top(handle : Void*, enabled : Bool) : Nil
      level = enabled ? NS_FLOATING_WINDOW_LEVEL : NS_NORMAL_WINDOW_LEVEL
      MacOS::ObjC.msg_long(handle, "setLevel:", level)
    end

    def set_titlebar_overlay(handle : Void*, enabled : Bool) : Nil
      mask = MacOS::ObjC.long(handle, "styleMask")
      mask = enabled ? mask | NS_FULL_SIZE_CONTENT_VIEW : mask & ~NS_FULL_SIZE_CONTENT_VIEW
      MacOS::ObjC.msg_long(handle, "setStyleMask:", mask)
    end

    def move(handle : Void*, x : Int32, y : Int32) : Nil
      LibNativeWindow.nd_window_move(handle, x.to_f64, y.to_f64)
    end

    def position(handle : Void*) : {Int32, Int32}
      x = LibNativeWindow.nd_window_position_x(handle).to_i32
      y = LibNativeWindow.nd_window_position_y(handle).to_i32
      {x, y}
    end

    def focus(handle : Void*) : Nil
      LibNativeWindow.nd_window_order_front(handle)
    end

    def show(handle : Void*) : Nil
      LibNativeWindow.nd_window_show(handle)
    end

    def hide(handle : Void*) : Nil
      LibNativeWindow.nd_window_hide(handle)
    end

    def minimize(handle : Void*) : Nil
      LibNativeWindow.nd_window_minimize(handle)
    end

    def maximize(handle : Void*) : Nil
      LibNativeWindow.nd_window_maximize(handle)
    end

    def restore(handle : Void*) : Nil
      LibNativeWindow.nd_window_restore(handle)
    end

    def minimized?(handle : Void*) : Bool
      LibNativeWindow.nd_window_is_minimized(handle) != 0
    end

    def maximized?(handle : Void*) : Bool
      LibNativeWindow.nd_window_is_maximized(handle) != 0
    end

    def fullscreen?(handle : Void*) : Bool
      LibNativeWindow.nd_window_is_fullscreen(handle) != 0
    end

    def set_fullscreen(handle : Void*, value : Bool) : Nil
      LibNativeWindow.nd_window_set_fullscreen(handle, value ? 1 : 0)
    end

    def set_frameless(handle : Void*, value : Bool) : Nil
      LibNativeWindow.nd_window_set_frameless(handle, value ? 1 : 0)
    end

    def frameless?(handle : Void*) : Bool
      LibNativeWindow.nd_window_is_frameless(handle) != 0
    end

    def set_transparent(handle : Void*, value : Bool) : Nil
      LibNativeWindow.nd_window_set_transparent(handle, value ? 1 : 0)
    end

    def set_opacity(handle : Void*, value : Float64) : Nil
      LibNativeWindow.nd_window_set_alpha(handle, value)
    end

    def set_modal(parent : Void*, child : Void*, value : Bool) : Nil
      LibNativeWindow.nd_window_set_modal(parent, child, value ? 1 : 0)
    end
  end
{% end %}
