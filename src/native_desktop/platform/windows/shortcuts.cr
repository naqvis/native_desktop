require "log"
require "./win32_common"

module NativeDesktop::Platform::Windows
  lib LibUser32
    struct MSG
      hwnd : Void*
      message : UInt32
      w_param : UInt64
      l_param : Int64
      time : UInt32
      pt : Point
    end
  end
end

module NativeDesktop::Platform::Windows::Shortcuts
  extend self
  Log = ::Log.for(self)

  WM_HOTKEY    = 0x0312_u32
  MOD_ALT      = 0x0001_u32
  MOD_CONTROL  = 0x0002_u32
  MOD_SHIFT    = 0x0004_u32
  MOD_WIN      = 0x0008_u32
  MOD_NOREPEAT = 0x4000_u32
  MODIFIER_MAP = {0 => MOD_CONTROL, 1 => MOD_ALT, 2 => MOD_SHIFT, 3 => MOD_WIN}
  VK_MAP       = {
    0 => 0x41_u32, 1 => 0x42_u32, 2 => 0x43_u32, 3 => 0x44_u32, 4 => 0x45_u32, 5 => 0x46_u32,
    6 => 0x47_u32, 7 => 0x48_u32, 8 => 0x49_u32, 9 => 0x4A_u32, 10 => 0x4B_u32, 11 => 0x4C_u32,
    12 => 0x4D_u32, 13 => 0x4E_u32, 14 => 0x4F_u32, 15 => 0x50_u32, 16 => 0x51_u32, 17 => 0x52_u32,
    18 => 0x53_u32, 19 => 0x54_u32, 20 => 0x55_u32, 21 => 0x56_u32, 22 => 0x57_u32, 23 => 0x58_u32,
    24 => 0x59_u32, 25 => 0x5A_u32, 26 => 0x30_u32, 27 => 0x31_u32, 28 => 0x32_u32, 29 => 0x33_u32,
    30 => 0x34_u32, 31 => 0x35_u32, 32 => 0x36_u32, 33 => 0x37_u32, 34 => 0x38_u32, 35 => 0x39_u32,
    36 => 0x70_u32, 37 => 0x71_u32, 38 => 0x72_u32, 39 => 0x73_u32, 40 => 0x74_u32, 41 => 0x75_u32,
    42 => 0x76_u32, 43 => 0x77_u32, 44 => 0x78_u32, 45 => 0x79_u32, 46 => 0x7A_u32, 47 => 0x7B_u32,
    48 => 0x20_u32, 49 => 0x0D_u32, 50 => 0x09_u32, 51 => 0x1B_u32, 52 => 0x08_u32, 53 => 0x2E_u32,
    54 => 0x25_u32, 55 => 0x27_u32, 56 => 0x26_u32, 57 => 0x28_u32, 58 => 0x24_u32, 59 => 0x23_u32,
    60 => 0x21_u32, 61 => 0x22_u32, 62 => 0xBC_u32, 63 => 0xBE_u32, 64 => 0xBA_u32, 65 => 0xDE_u32,
    66 => 0xDB_u32, 67 => 0xDD_u32, 68 => 0xDC_u32, 69 => 0xBF_u32, 70 => 0xBD_u32, 71 => 0xBB_u32,
  }

  @@registered = {} of String => {Int32, Proc(Nil)}
  @@handlers = {} of Int32 => Proc(Nil)
  @@next_id = 1

  def register(identifier : String, modifiers : Array(Int32), key : Int32, handler : Proc(Nil)) : Nil
    flags = modifiers.reduce(MOD_NOREPEAT) { |mask, value| mask | (MODIFIER_MAP[value]? || 0_u32) }
    virtual_key = VK_MAP[key]? || raise Error.new("cannot map key #{key} to a Windows virtual key", :shortcut_register_failed)
    id = @@next_id
    @@next_id += 1
    if LibUser32.RegisterHotKey(Pointer(Void).null, id, flags, virtual_key) == 0
      raise Error.new("could not register shortcut #{identifier.inspect}; it may already be used", :shortcut_register_failed)
    end
    @@registered[identifier] = {id, handler}
    @@handlers[id] = handler
  end

  def unregister(identifier : String) : Nil
    if entry = @@registered.delete(identifier)
      id, _ = entry
      LibUser32.UnregisterHotKey(Pointer(Void).null, id)
      @@handlers.delete(id)
    end
  end

  def start_listening : Nil
  end

  def stop_listening : Nil
  end

  def process_event(event : Void*) : Bool
    msg = event.as(LibUser32::MSG*).value
    return false unless msg.message == WM_HOTKEY
    if handler = @@handlers[msg.w_param.to_i32]?
      begin
        Runtime.spawn_background do
          handler.call
        rescue ex
          Log.error(exception: ex) { "global shortcut handler failed" }
        end
      rescue ex
        Log.error(exception: ex) { "could not dispatch a global shortcut" }
      end
    end
    true
  end
end
