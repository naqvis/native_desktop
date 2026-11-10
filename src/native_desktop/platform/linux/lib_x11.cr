# Shared X11 C bindings for Linux.
# Consolidates all X11 functions from across the platform into one
# canonical lib block. Every platform file requiring this avoids
# duplicate C function declarations.

@[Link("X11", pkg_config: "x11")]
lib LibX11
  # :nodoc:
  struct XKeyEvent
    type : Int32
    serial : UInt64
    send_event : Int32
    display : Void*
    window : UInt64
    root : UInt64
    subwindow : UInt64
    time : UInt64
    x : Int32
    y : Int32
    x_root : Int32
    y_root : Int32
    state : UInt32
    keycode : UInt32
    same_screen : Int32
  end

  # ── Core display / connection ──
  fun XOpenDisplay(display_name : UInt8*) : Void*
  fun XInitThreads : Int32
  fun XCloseDisplay(display : Void*) : Int32
  fun XFlush(display : Void*) : Int32
  fun XSync(display : Void*, discard : Int32) : Int32
  fun XDefaultRootWindow(display : Void*) : UInt64

  # ── Atoms / Properties ──
  fun XInternAtom(display : Void*, name : UInt8*, only_if_exists : Int32) : UInt64
  fun XChangeProperty(display : Void*, w : UInt64, property : UInt64, type : UInt64, format : Int32, mode : Int32, data : UInt8*, nelements : Int32) : Int32

  # ── Input / Events ──
  fun XGrabKey(display : Void*, keycode : Int32, modifiers : UInt32, grab_window : UInt64, owner_events : Int32, pointer_mode : Int32, keyboard_mode : Int32) : Nil
  fun XUngrabKey(display : Void*, keycode : Int32, modifiers : UInt32, grab_window : UInt64) : Int32
  fun XKeysymToKeycode(display : Void*, keysym : UInt64) : UInt8
  fun XStringToKeysym(string : UInt8*) : UInt64
  fun XCheckMaskEvent(display : Void*, event_mask : Int64, event_return : Void*) : Int32
  fun XSelectInput(display : Void*, window : UInt64, event_mask : Int64) : Int32
  fun XQueryPointer(display : Void*, window : UInt64, root : UInt64*, child : UInt64*, root_x : Int32*, root_y : Int32*, win_x : Int32*, win_y : Int32*, mask : UInt32*) : Int32

  # ── Screen / Display info ──
  fun XDefaultScreenOfDisplay(display : Void*) : Void*
  fun XWidthOfScreen(screen : Void*) : Int32
  fun XHeightOfScreen(screen : Void*) : Int32
  fun XWidthMMOfScreen(screen : Void*) : Int32
  fun XHeightMMOfScreen(screen : Void*) : Int32
end
