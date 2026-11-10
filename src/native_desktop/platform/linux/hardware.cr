require "log"

module NativeDesktop::Platform::Hardware
  extend self

  @[Link("udev", pkg_config: "libudev")]
  lib LibUDevHardware
    fun udev_new : Void*
    fun udev_unref(udev : Void*) : Void*
    fun udev_enumerate_new(udev : Void*) : Void*
    fun udev_enumerate_add_match_subsystem(enumerate : Void*, subsystem : UInt8*) : Int32
    fun udev_enumerate_scan_devices(enumerate : Void*) : Int32
    fun udev_enumerate_get_list_entry(enumerate : Void*) : Void*
    fun udev_enumerate_unref(enumerate : Void*) : Void*
    fun udev_list_entry_get_next(entry : Void*) : Void*
    fun udev_list_entry_get_name(entry : Void*) : UInt8*
    fun udev_device_new_from_syspath(udev : Void*, syspath : UInt8*) : Void*
    fun udev_device_get_property_value(device : Void*, key : UInt8*) : UInt8*
    fun udev_device_get_devnode(device : Void*) : UInt8*
    fun udev_device_get_sysattr_value(device : Void*, key : UInt8*) : UInt8*
    fun udev_device_unref(device : Void*) : Void*
  end

  def enumerate(kind : HardwareKind) : Array(HardwareDevice)
    case kind
    in .usb?       then enumerate_usb
    in .bluetooth? then enumerate_bluetooth
    in .serial?    then enumerate_serial
    in .hid?       then enumerate_hid
    in .nfc?       then [] of HardwareDevice
    end
  rescue ex
    ::Log.for(self).warn(exception: ex) { "could not enumerate #{kind} devices" }
    [] of HardwareDevice
  end

  private def enumerate_usb : Array(HardwareDevice)
    devices = [] of HardwareDevice
    each_device("usb") do |device, syspath|
      vendor = udev_property(device, "ID_VENDOR_ID")
      product = udev_property(device, "ID_MODEL_ID")
      name = udev_property(device, "ID_MODEL_FROM_DATABASE") || udev_property(device, "ID_MODEL") || "Unknown USB Device"
      devices << HardwareDevice.new("usb-#{syspath}", name, HardwareKind::USB, hex_u16(vendor), hex_u16(product))
    end
    devices
  end

  private def enumerate_bluetooth : Array(HardwareDevice)
    devices = [] of HardwareDevice
    each_device("bluetooth") do |device, syspath|
      name = udev_property(device, "ID_MODEL") || udev_property(device, "NAME") || udev_attribute(device, "name") || "Unknown Bluetooth Device"
      devices << HardwareDevice.new("bluetooth-#{syspath}", name, HardwareKind::Bluetooth)
    end
    devices
  end

  private def enumerate_serial : Array(HardwareDevice)
    devices = [] of HardwareDevice
    each_device("tty") do |device, syspath|
      value = LibUDevHardware.udev_device_get_devnode(device)
      unless value.null?
        path = String.new(value)
        name = File.basename(path)
        devices << HardwareDevice.new("serial-#{syspath}", name, HardwareKind::Serial)
      end
    end

    if devices.empty?
      Dir.glob("/dev/{ttyUSB*,ttyACM*,ttyS*,ttyAMA*,ttyMFD*,rfcomm*}").sort.each do |path|
        devices << HardwareDevice.new("serial-#{path}", File.basename(path), HardwareKind::Serial)
      end
    end
    devices
  end

  private def enumerate_hid : Array(HardwareDevice)
    devices = [] of HardwareDevice
    each_device("hidraw") do |device, syspath|
      name = udev_property(device, "HID_NAME") || udev_attribute(device, "name") || "Unknown HID Device"
      vendor, product = hid_ids(udev_property(device, "HID_ID"))
      devices << HardwareDevice.new("hid-#{syspath}", name, HardwareKind::HID, vendor, product)
    end
    devices
  end

  private def each_device(subsystem : String, &block : Void*, String ->) : Nil
    udev = LibUDevHardware.udev_new
    return if udev.null?
    begin
      enumeration = LibUDevHardware.udev_enumerate_new(udev)
      return if enumeration.null?
      begin
        return if LibUDevHardware.udev_enumerate_add_match_subsystem(enumeration, subsystem) < 0
        return if LibUDevHardware.udev_enumerate_scan_devices(enumeration) < 0

        entry = LibUDevHardware.udev_enumerate_get_list_entry(enumeration)
        until entry.null?
          name = LibUDevHardware.udev_list_entry_get_name(entry)
          unless name.null?
            syspath = String.new(name)
            device = LibUDevHardware.udev_device_new_from_syspath(udev, name)
            unless device.null?
              begin
                yield device, syspath
              ensure
                LibUDevHardware.udev_device_unref(device)
              end
            end
          end
          entry = LibUDevHardware.udev_list_entry_get_next(entry)
        end
      ensure
        LibUDevHardware.udev_enumerate_unref(enumeration)
      end
    ensure
      LibUDevHardware.udev_unref(udev)
    end
  end

  private def udev_property(device : Void*, key : String) : String?
    value = LibUDevHardware.udev_device_get_property_value(device, key)
    value.null? ? nil : String.new(value)
  end

  private def udev_attribute(device : Void*, key : String) : String?
    value = LibUDevHardware.udev_device_get_sysattr_value(device, key)
    value.null? ? nil : String.new(value)
  end

  private def hex_u16(value : String?) : UInt16?
    value.try(&.to_u16?(16))
  end

  private def hid_ids(value : String?) : {UInt16?, UInt16?}
    return {nil, nil} unless value
    parts = value.split(':')
    return {nil, nil} unless parts.size >= 3
    {parts[1].to_u16?(16), parts[2].to_u16?(16)}
  end
end
