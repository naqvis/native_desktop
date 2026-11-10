require "log"
require "./objc"

module NativeDesktop::Platform::Hardware
  extend self

  UTF8_ENCODING = 0x08000100_u32
  NUMBER_SINT32 =          3_u32

  @[Link(framework: "IOKit")]
  @[Link(framework: "CoreFoundation")]
  lib LibIOKitHardware
    fun service_matching = IOServiceMatching(name : UInt8*) : Void*
    fun matching_services = IOServiceGetMatchingServices(port : UInt32, matching : Void*, iterator : Void**) : Int32
    fun iterator_next = IOIteratorNext(iterator : Void*) : Void*
    fun object_release = IOObjectRelease(object : Void*) : Int32
    fun registry_id = IORegistryEntryGetRegistryEntryID(entry : Void*, id : UInt64*) : Int32
    fun registry_path = IORegistryEntryGetPath(entry : Void*, plane : UInt8*, path : UInt8*) : Int32
    fun property = IORegistryEntryCreateCFProperty(entry : Void*, key : Void*, allocator : Void*, options : UInt32) : Void*
    fun string_create = CFStringCreateWithCString(allocator : Void*, string : UInt8*, encoding : UInt32) : Void*
    fun string_length = CFStringGetLength(string : Void*) : Int64
    fun string_get = CFStringGetCString(string : Void*, buffer : UInt8*, size : Int64, encoding : UInt32) : UInt8
    fun number_get = CFNumberGetValue(number : Void*, type : UInt32, value : Void*) : Int32
    fun release = CFRelease(value : Void*) : Nil
  end

  def enumerate(kind : HardwareKind) : Array(HardwareDevice)
    case kind
    in .usb?       then enumerate_iokit("IOUSBDevice", HardwareKind::USB)
    in .bluetooth? then enumerate_bluetooth
    in .serial?    then enumerate_serial
    in .hid?       then enumerate_iokit("IOHIDDevice", HardwareKind::HID)
    in .nfc?       then [] of HardwareDevice
    end
  rescue ex
    ::Log.for(self).warn(exception: ex) { "could not enumerate #{kind} devices" }
    [] of HardwareDevice
  end

  private def enumerate_iokit(service_name : String, kind : HardwareKind) : Array(HardwareDevice)
    devices = [] of HardwareDevice
    matching = LibIOKitHardware.service_matching(service_name)
    return devices if matching.null?

    iterator = Pointer(Void).null
    return devices unless LibIOKitHardware.matching_services(0_u32, matching, pointerof(iterator)) == 0
    return devices if iterator.null?
    begin
      loop do
        service = LibIOKitHardware.iterator_next(iterator)
        break if service.null?
        begin
          device = build_iokit_device(service, kind)
          devices << device if device
        ensure
          LibIOKitHardware.object_release(service)
        end
      end
    ensure
      LibIOKitHardware.object_release(iterator)
    end
    devices
  end

  private def build_iokit_device(service : Void*, kind : HardwareKind) : HardwareDevice?
    if kind.usb?
      vendor = safe_u16(number(service, "USB Vendor ID"))
      product = safe_u16(number(service, "USB Product ID"))
      name = string(service, "USB Product Name") || "Unknown USB Device"
      serial = string(service, "USB Serial Number")
      id = serial && !serial.empty? ? "usb-#{serial}" : native_id(service, "usb")
      return nil unless id
      HardwareDevice.new(id, name, kind, vendor, product)
    else
      vendor = safe_u16(number(service, "VendorID"))
      product = safe_u16(number(service, "ProductID"))
      name = string(service, "Product") || string(service, "USB Product Name") || "Unknown HID Device"
      id = native_id(service, "hid")
      return nil unless id
      HardwareDevice.new(id, name, kind, vendor, product)
    end
  end

  private def native_id(service : Void*, prefix : String) : String?
    registry_id = 0_u64
    return "#{prefix}-#{registry_id}" if LibIOKitHardware.registry_id(service, pointerof(registry_id)) == 0

    path = Bytes.new(1024, 0_u8)
    return nil unless LibIOKitHardware.registry_path(service, "IOService", path.to_unsafe) == 0
    "#{prefix}-#{String.new(path.to_unsafe)}"
  end

  private def enumerate_serial : Array(HardwareDevice)
    Dir.glob("/dev/{tty.*,cu.*,tty.usb*,tty.uart*,tty.SLAB*}").sort.map do |path|
      HardwareDevice.new("serial-#{path}", File.basename(path), HardwareKind::Serial)
    end
  end

  private def enumerate_bluetooth : Array(HardwareDevice)
    MacOS::ObjC.pool do
      devices = [] of HardwareDevice
      klass = MacOS::ObjCRuntime.get_class("IOBluetoothDevice")
      next devices if klass.null?
      paired = MacOS::ObjCRuntime.msg(klass, "pairedDevices")
      next devices if paired.null?

      MacOS::ObjCRuntime.msg_long(paired, "count").times do |index|
        device = MacOS::ObjCRuntime.msg_object_at(paired, "objectAtIndex:", index.to_u64)
        next if device.null?
        name = MacOS::ObjCRuntime.nsstring_to_s(MacOS::ObjCRuntime.msg(device, "name"))
        address = MacOS::ObjCRuntime.nsstring_to_s(MacOS::ObjCRuntime.msg(device, "addressString"))
        id = address || name || "paired-device-#{index}"
        devices << HardwareDevice.new("bluetooth-#{id}", name || "Unknown Bluetooth Device", HardwareKind::Bluetooth)
      end
      devices
    end
  end

  private def number(service : Void*, key : String) : Int64?
    with_property(service, key) do |value|
      result = 0_i32
      LibIOKitHardware.number_get(value, NUMBER_SINT32, pointerof(result).as(Void*)) == 0 ? nil : result.to_i64
    end
  end

  private def string(service : Void*, key : String) : String?
    with_property(service, key) do |value|
      length = LibIOKitHardware.string_length(value)
      next nil if length <= 0
      buffer = Bytes.new(length * 4 + 1, 0_u8)
      LibIOKitHardware.string_get(value, buffer.to_unsafe, buffer.size.to_i64, UTF8_ENCODING) == 0 ? nil : String.new(buffer.to_unsafe)
    end
  end

  private def with_property(service : Void*, key : String, &block : Void* -> T) : T? forall T
    cf_key = LibIOKitHardware.string_create(Pointer(Void).null, key, UTF8_ENCODING)
    return nil if cf_key.null?
    begin
      value = LibIOKitHardware.property(service, cf_key, Pointer(Void).null, 0_u32)
      return nil if value.null?
      begin
        yield value
      ensure
        LibIOKitHardware.release(value)
      end
    ensure
      LibIOKitHardware.release(cf_key)
    end
  end

  private def safe_u16(value : Int64?) : UInt16?
    value && value.in?(0_i64..UInt16::MAX.to_i64) ? value.to_u16 : nil
  end
end
