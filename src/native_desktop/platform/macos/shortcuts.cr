require "log"
require "./objc_runtime"

module NativeDesktop::Platform::MacOS::Shortcuts
  extend self
  Log = ::Log.for(self)

  @[Link(framework: "CoreGraphics")]
  lib LibCGShortcuts
    type EventTap = Void*
    CGEventKeyDown          = 10_u32
    CGHIDEventTap           =  0_u32
    CGHeadInsertEventTap    =  0_u32
    CGEventTapOptionDefault =  0_u32
    fun CGEventTapCreate(tap : UInt32, place : UInt32, options : UInt32, events : UInt64, callback : Void*, info : Void*) : EventTap
    fun CGEventTapEnable(tap : EventTap, enable : Int32) : Nil
    fun CGEventGetIntegerValueField(event : Void*, field : Int32) : Int64
    fun CGEventGetFlags(event : Void*) : UInt64
  end

  @[Link(framework: "ApplicationServices")]
  lib LibAXShortcuts
    fun AXIsProcessTrusted : Int32
  end

  @[Link(framework: "CoreFoundation")]
  lib LibCFShortcuts
    fun CFMachPortCreateRunLoopSource(allocator : Void*, port : Void*, order : Int64) : Void*
    fun CFMachPortInvalidate(port : Void*) : Nil
    fun CFRunLoopGetCurrent : Void*
    fun CFRunLoopAddSource(run_loop : Void*, source : Void*, mode : Void*) : Nil
    fun CFRunLoopRun : Nil
    fun CFRunLoopStop(run_loop : Void*) : Nil
    fun CFRunLoopWakeUp(run_loop : Void*) : Nil
    fun CFStringCreateWithCString(allocator : Void*, string : UInt8*, encoding : UInt32) : Void*
    fun CFRetain(object : Void*) : Void*
    fun CFRelease(object : Void*) : Nil
  end

  SHIFT_FLAG     = 0x00020000_u64
  CTRL_FLAG      = 0x00040000_u64
  ALT_FLAG       = 0x00080000_u64
  CMD_FLAG       = 0x00100000_u64
  RELEVANT_FLAGS = SHIFT_FLAG | CTRL_FLAG | ALT_FLAG | CMD_FLAG
  MODIFIER_FLAGS = {0 => CTRL_FLAG, 1 => ALT_FLAG, 2 => SHIFT_FLAG, 3 => CMD_FLAG}
  KEY_CODES      = {
    0 => 0, 1 => 11, 2 => 8, 3 => 2, 4 => 14, 5 => 3, 6 => 5, 7 => 4, 8 => 34, 9 => 38,
    10 => 40, 11 => 37, 12 => 46, 13 => 45, 14 => 31, 15 => 35, 16 => 12, 17 => 15, 18 => 1,
    19 => 17, 20 => 32, 21 => 9, 22 => 13, 23 => 7, 24 => 16, 25 => 6,
    26 => 29, 27 => 18, 28 => 19, 29 => 20, 30 => 21, 31 => 23, 32 => 22, 33 => 26, 34 => 28, 35 => 25,
    36 => 122, 37 => 120, 38 => 99, 39 => 118, 40 => 96, 41 => 97, 42 => 98, 43 => 100,
    44 => 101, 45 => 109, 46 => 103, 47 => 111, 48 => 49, 49 => 36, 50 => 48, 51 => 53,
    52 => 51, 53 => 117, 54 => 123, 55 => 124, 56 => 126, 57 => 125, 58 => 115, 59 => 119, 60 => 116, 61 => 121,
    62 => 43, 63 => 47, 64 => 41, 65 => 39, 66 => 33, 67 => 30, 68 => 42, 69 => 44, 70 => 27, 71 => 24,
  }

  @@lock = Mutex.new
  @@registered = {} of String => {UInt64, Int64, Proc(Nil)}
  @@tap = Pointer(Void).null
  @@run_loop = Pointer(Void).null
  @@thread : Thread?
  @@listening = false

  EVENT_CALLBACK = ->(_proxy : Void*, type : UInt32, event : Void*, _info : Void*) {
    Shortcuts.handle_event(type, event)
    event
  }

  def register(identifier : String, modifiers : Array(Int32), key : Int32, handler : Proc(Nil)) : Nil
    flags = modifiers.reduce(0_u64) { |mask, value| mask | (MODIFIER_FLAGS[value]? || 0_u64) }
    keycode = KEY_CODES[key]?.try(&.to_i64) || raise Error.new("cannot map key #{key} to a macOS keycode", :shortcut_register_failed)
    @@lock.synchronize { @@registered[identifier] = {flags, keycode, handler} }
  end

  def unregister(identifier : String) : Nil
    @@lock.synchronize { @@registered.delete(identifier) }
  end

  def start_listening : Nil
    return if @@listening
    raise Error.new("accessibility permission is required for global shortcuts", :shortcut_listen_failed) if LibAXShortcuts.AXIsProcessTrusted == 0
    tap = LibCGShortcuts.CGEventTapCreate(0, 0, 0, 1_u64 << LibCGShortcuts::CGEventKeyDown, EVENT_CALLBACK.pointer.as(Void*), Pointer(Void).null)
    raise Error.new("could not create the macOS keyboard event tap", :shortcut_listen_failed) if tap.null?

    ready = Channel(Void*).new(1)
    @@tap = tap.as(Void*)
    @@listening = true
    @@thread = Thread.new do
      source = LibCFShortcuts.CFMachPortCreateRunLoopSource(Pointer(Void).null, tap.as(Void*), 0_i64)
      mode = LibCFShortcuts.CFStringCreateWithCString(Pointer(Void).null, "kCFRunLoopDefaultMode", 0x08000100_u32)
      run_loop = LibCFShortcuts.CFRunLoopGetCurrent
      # CFRunLoopGetCurrent follows the Get Rule. Retain the loop while its
      # pointer is shared with the controlling thread; invalidating the event
      # tap can otherwise let CFRunLoopRun return and destroy the loop before
      # stop_listening reaches CFRunLoopStop.
      LibCFShortcuts.CFRetain(run_loop)
      LibCFShortcuts.CFRunLoopAddSource(run_loop, source, mode)
      ready.send(run_loop)
      LibCFShortcuts.CFRunLoopRun
      LibCFShortcuts.CFRelease(mode)
      LibCFShortcuts.CFRelease(source)
    end
    @@run_loop = ready.receive
    LibCGShortcuts.CGEventTapEnable(tap, 1)
  rescue ex
    @@listening = false
    LibCFShortcuts.CFRelease(tap.as(Void*)) if tap && !tap.null?
    @@tap = Pointer(Void).null
    raise ex
  end

  def stop_listening : Nil
    return unless @@listening
    @@listening = false
    LibCGShortcuts.CGEventTapEnable(@@tap.as(LibCGShortcuts::EventTap), 0) unless @@tap.null?
    unless @@run_loop.null?
      LibCFShortcuts.CFRunLoopStop(@@run_loop)
      LibCFShortcuts.CFRunLoopWakeUp(@@run_loop)
    end
    @@thread.try(&.join)
    LibCFShortcuts.CFMachPortInvalidate(@@tap) unless @@tap.null?
    LibCFShortcuts.CFRelease(@@tap) unless @@tap.null?
    LibCFShortcuts.CFRelease(@@run_loop) unless @@run_loop.null?
    @@thread = nil
    @@tap = Pointer(Void).null
    @@run_loop = Pointer(Void).null
  end

  def handle_event(type : UInt32, event : Void*) : Nil
    return unless type == LibCGShortcuts::CGEventKeyDown
    keycode = LibCGShortcuts.CGEventGetIntegerValueField(event, 9_i32)
    flags = LibCGShortcuts.CGEventGetFlags(event) & RELEVANT_FLAGS
    actions = @@lock.synchronize do
      @@registered.values.compact_map { |required_flags, required_keycode, handler| handler if required_keycode == keycode && required_flags == flags }
    end
    actions.each do |action|
      Runtime.spawn_background do
        action.call
      rescue ex
        Log.error(exception: ex) { "global shortcut handler failed" }
      end
    end
  rescue ex
    Log.error(exception: ex) { "could not dispatch a global shortcut" }
  end
end
