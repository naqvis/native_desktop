require "log"
require "./string_helpers"
require "./win32_common"

module NativeDesktop::Platform::Hardware
  extend self

  @[Link("setupapi")]
  lib LibSetupAPIHardware
    struct Guid
      data1 : UInt32
      data2 : UInt16
      data3 : UInt16
      data4 : StaticArray(UInt8, 8)
    end

    struct DeviceInfoData
      cb_size : UInt32
      class_guid : Guid
      dev_inst : UInt32
      reserved : UInt64
    end

    fun get_class_devices = SetupDiGetClassDevsW(class_guid : Void*, enumerator : UInt16*, parent : Void*, flags : UInt32) : Void*
    fun destroy_device_list = SetupDiDestroyDeviceInfoList(device_info_set : Void*) : Int32
    fun next_device = SetupDiEnumDeviceInfo(device_info_set : Void*, index : UInt32, data : DeviceInfoData*) : Int32
    fun property = SetupDiGetDeviceRegistryPropertyW(device_info_set : Void*, data : DeviceInfoData*, property : UInt32, data_type : UInt32*, buffer : UInt8*, buffer_size : UInt32, required_size : UInt32*) : Int32
    fun instance_id = SetupDiGetDeviceInstanceIdW(device_info_set : Void*, data : DeviceInfoData*, buffer : UInt16*, buffer_size : UInt32, required_size : UInt32*) : Int32
  end

  PRESENT            = 0x00000002_u32
  ALL_CLASSES        = 0x00000004_u32
  FRIENDLY           =         10_u32
  DESCRIPTION        =          0_u32
  HARDWARE_ID        =          1_u32
  INVALID_HANDLE     = Pointer(Void).new(UInt64::MAX)
  HKEY_LOCAL_MACHINE = Pointer(Void).new(0x80000002_u64).as(LibC::HKEY)
  SUCCESS            = 0_u32
  REG_SZ             = 1_u32

  def enumerate(kind : HardwareKind) : Array(HardwareDevice)
    case kind
    in .usb?       then enumerate_setup("USB", kind, "USB")
    in .bluetooth? then enumerate_setup("BTHENUM", kind, "Bluetooth")
    in .serial?    then enumerate_serial
    in .hid?       then enumerate_setup("HID", kind, "HID")
    in .nfc?       then [] of HardwareDevice
    end
  rescue ex
    ::Log.for(self).warn(exception: ex) { "could not enumerate #{kind} devices" }
    [] of HardwareDevice
  end

  private def enumerate_setup(enumerator : String, kind : HardwareKind, label : String) : Array(HardwareDevice)
    devices = [] of HardwareDevice
    encoded = Windows::StringHelpers.to_utf16(enumerator)
    set = LibSetupAPIHardware.get_class_devices(Pointer(Void).null, encoded.to_unsafe, Pointer(Void).null, PRESENT | ALL_CLASSES)
    return devices if set.null? || set == INVALID_HANDLE

    begin
      index = 0_u32
      loop do
        data = LibSetupAPIHardware::DeviceInfoData.new
        data.cb_size = sizeof(LibSetupAPIHardware::DeviceInfoData).to_u32
        break if LibSetupAPIHardware.next_device(set, index, pointerof(data)) == 0

        name = read_property(set, pointerof(data), FRIENDLY) ||
               read_property(set, pointerof(data), DESCRIPTION) ||
               "#{label} Device"
        hardware_id = read_property(set, pointerof(data), HARDWARE_ID)
        id = read_instance_id(set, pointerof(data)) || hardware_id || "#{label.downcase}-#{name}-#{index}"
        vendor, product = usb_ids(hardware_id)
        devices << HardwareDevice.new(id, name, kind, vendor, product)
        index += 1
      end
    ensure
      LibSetupAPIHardware.destroy_device_list(set)
    end
    devices
  end

  private def read_property(set : Void*, data : LibSetupAPIHardware::DeviceInfoData*, property : UInt32) : String?
    required = 0_u32
    LibSetupAPIHardware.property(set, data, property, Pointer(UInt32).null, Pointer(UInt8).null, 0_u32, pointerof(required))
    return nil if required < 2

    buffer = Bytes.new(required.to_i, 0_u8)
    return nil if LibSetupAPIHardware.property(set, data, property, Pointer(UInt32).null, buffer.to_unsafe, required, pointerof(required)) == 0
    value = Windows::StringHelpers.from_utf16(buffer.to_unsafe.as(UInt16*))
    value.empty? ? nil : value
  end

  private def read_instance_id(set : Void*, data : LibSetupAPIHardware::DeviceInfoData*) : String?
    required = 0_u32
    LibSetupAPIHardware.instance_id(set, data, Pointer(UInt16).null, 0_u32, pointerof(required))
    return nil if required < 2

    buffer = Pointer(UInt16).malloc(required.to_i)
    return nil if LibSetupAPIHardware.instance_id(set, data, buffer, required, pointerof(required)) == 0
    value = Windows::StringHelpers.from_utf16(buffer)
    value.empty? ? nil : value
  end

  private def enumerate_serial : Array(HardwareDevice)
    devices = [] of HardwareDevice
    path = Windows::StringHelpers.to_utf16("HARDWARE\\DEVICEMAP\\SERIALCOMM")
    result = LibC.RegOpenKeyExW(HKEY_LOCAL_MACHINE, path.to_unsafe, 0_u32, LibC::REGSAM::READ, out key)
    return devices if result != SUCCESS || key.null?

    begin
      index = 0_u32
      loop do
        value_name = Pointer(UInt16).malloc(256)
        value_name_size = 256_u32
        data = Bytes.new(512, 0_u8)
        data_size = data.size.to_u32
        type = 0_u32
        error = Windows::LibAdvApi32.RegEnumValueW(key.as(Void*), index, value_name, pointerof(value_name_size), Pointer(Void).null, pointerof(type), data.to_unsafe, pointerof(data_size))
        break unless error == SUCCESS

        if type == REG_SZ && data_size >= 2
          port = Windows::StringHelpers.from_utf16(data.to_unsafe.as(UInt16*)).strip
          devices << HardwareDevice.new("serial-#{port}", port, HardwareKind::Serial) unless port.empty?
        end
        index += 1
      end
    ensure
      LibC.RegCloseKey(key)
    end
    devices
  end

  private def usb_ids(hardware_id : String?) : {UInt16?, UInt16?}
    return {nil, nil} unless hardware_id
    vendor = hardware_id.match(/VID_([0-9A-F]{4})/i).try { |match| match[1].to_u16?(16) }
    product = hardware_id.match(/PID_([0-9A-F]{4})/i).try { |match| match[1].to_u16?(16) }
    {vendor, product}
  end
end
