require "log"
require "./lib_x11"

module NativeDesktop::Platform::Linux::Shortcuts
  extend self
  Log = ::Log.for(self)

  KEY_PRESS_MASK =  1_i64
  KEY_PRESS      =      2
  CONTROL_MASK   =  4_u32
  ALT_MASK       =  8_u32
  SHIFT_MASK     =  1_u32
  META_MASK      = 64_u32
  LOCK_MASKS     = [0_u32, 2_u32, 16_u32, 18_u32]
  MODIFIER_MAP   = {0 => CONTROL_MASK, 1 => ALT_MASK, 2 => SHIFT_MASK, 3 => META_MASK}
  KEY_SYMS       = {
    0 => "a", 1 => "b", 2 => "c", 3 => "d", 4 => "e", 5 => "f", 6 => "g", 7 => "h", 8 => "i", 9 => "j",
    10 => "k", 11 => "l", 12 => "m", 13 => "n", 14 => "o", 15 => "p", 16 => "q", 17 => "r", 18 => "s", 19 => "t",
    20 => "u", 21 => "v", 22 => "w", 23 => "x", 24 => "y", 25 => "z",
    26 => "0", 27 => "1", 28 => "2", 29 => "3", 30 => "4", 31 => "5", 32 => "6", 33 => "7", 34 => "8", 35 => "9",
    36 => "F1", 37 => "F2", 38 => "F3", 39 => "F4", 40 => "F5", 41 => "F6", 42 => "F7", 43 => "F8",
    44 => "F9", 45 => "F10", 46 => "F11", 47 => "F12", 48 => "space", 49 => "Return", 50 => "Tab",
    51 => "Escape", 52 => "BackSpace", 53 => "Delete", 54 => "Left", 55 => "Right", 56 => "Up", 57 => "Down",
    58 => "Home", 59 => "End", 60 => "Prior", 61 => "Next", 62 => "comma", 63 => "period", 64 => "semicolon",
    65 => "apostrophe", 66 => "bracketleft", 67 => "bracketright", 68 => "backslash", 69 => "slash", 70 => "minus", 71 => "equal",
  }

  @@lock = Mutex.new
  @@display = Pointer(Void).null
  @@root = 0_u64
  @@registered = {} of String => {UInt32, UInt8, Proc(Nil)}
  @@running = false
  @@generation = 0_u64

  def register(identifier : String, modifiers : Array(Int32), key : Int32, handler : Proc(Nil)) : Nil
    @@lock.synchronize do
      ensure_display
      mask = modifiers.reduce(0_u32) { |value, modifier| value | (MODIFIER_MAP[modifier]? || 0_u32) }
      name = KEY_SYMS[key]? || raise Error.new("cannot map key #{key} to an X11 keysym", :shortcut_register_failed)
      keycode = LibX11.XKeysymToKeycode(@@display, LibX11.XStringToKeysym(name))
      raise Error.new("cannot map key #{key} to an X11 keycode", :shortcut_register_failed) if keycode == 0
      LOCK_MASKS.each { |extra| LibX11.XGrabKey(@@display, keycode.to_i32, mask | extra, @@root, 0, 1, 1) }
      LibX11.XSync(@@display, 0)
      @@registered[identifier] = {mask, keycode, handler}
    end
  end

  def unregister(identifier : String) : Nil
    @@lock.synchronize do
      if entry = @@registered.delete(identifier)
        mask, keycode, _ = entry
        LOCK_MASKS.each { |extra| LibX11.XUngrabKey(@@display, keycode.to_i32, mask | extra, @@root) }
        LibX11.XSync(@@display, 0)
      end
    end
  end

  def start_listening : Nil
    generation = @@lock.synchronize do
      return if @@running
      ensure_display
      @@running = true
      @@generation &+= 1
    end
    Runtime.spawn_background { poll(generation) }
  rescue ex
    @@lock.synchronize { @@running = false }
    raise ex
  end

  def stop_listening : Nil
    @@lock.synchronize do
      return unless @@running
      @@running = false
      @@generation &+= 1
    end
  end

  private def ensure_display : Nil
    return unless @@display.null?
    Log.warn { "global shortcuts require XWayland when running under Wayland" } if ENV["WAYLAND_DISPLAY"]? && !ENV["DISPLAY"]?
    LibX11.XInitThreads
    @@display = LibX11.XOpenDisplay(Pointer(UInt8).null)
    raise Error.new("cannot open the X11 display", :shortcut_display_failed) if @@display.null?
    @@root = LibX11.XDefaultRootWindow(@@display)
    LibX11.XSelectInput(@@display, @@root, KEY_PRESS_MASK)
  end

  private def poll(generation : UInt64) : Nil
    event_buffer = Bytes.new(192, 0_u8)
    loop do
      running, action = @@lock.synchronize do
        if @@running && @@generation == generation
          handler = nil
          if LibX11.XCheckMaskEvent(@@display, KEY_PRESS_MASK, event_buffer.to_unsafe) != 0
            event = Pointer(LibX11::XKeyEvent).new(event_buffer.to_unsafe.address).value
            if event.type == KEY_PRESS
              state = event.state & ~(2_u32 | 16_u32)
              handler = @@registered.values.find { |mask, keycode, _| mask == state && keycode == event.keycode }.try(&.[2])
            end
          end
          {true, handler}
        else
          {false, nil}
        end
      end
      break unless running
      if action
        begin
          action.call
        rescue ex
          Log.error(exception: ex) { "global shortcut handler failed" }
        end
      else
        sleep 10.milliseconds
      end
    end
  end
end
