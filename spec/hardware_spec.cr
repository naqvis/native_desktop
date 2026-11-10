require "./spec_helper"

describe NativeDesktop::HardwareDevice do
  it "describes a device without exposing platform handles" do
    device = NativeDesktop::HardwareDevice.new(
      "usb-device-1",
      "Test Device",
      NativeDesktop::HardwareKind::USB,
      0x1234_u16,
      0xabcd_u16,
    )

    device.id.should eq("usb-device-1")
    device.kind.usb?.should be_true
    device.vendor_id.should eq(0x1234_u16)
    device.product_id.should eq(0xabcd_u16)
  end

  it "rejects empty identifiers and names" do
    expect_raises(ArgumentError) do
      NativeDesktop::HardwareDevice.new("", "Device", NativeDesktop::HardwareKind::USB)
    end
    expect_raises(ArgumentError) do
      NativeDesktop::HardwareDevice.new("device", "", NativeDesktop::HardwareKind::USB)
    end
  end

  it "accepts extension-defined hardware event types" do
    NativeDesktop::HardwareEventType["extension.hardware"].value.should eq("extension.hardware")
  end
end

describe NativeDesktop::Hardware do
  it "reports the supported hardware families" do
    NativeDesktop.hardware.available?(NativeDesktop::HardwareKind::USB).should be_true
    NativeDesktop.hardware.available?(NativeDesktop::HardwareKind::Bluetooth).should be_true
    NativeDesktop.hardware.available?(NativeDesktop::HardwareKind::Serial).should be_true
    NativeDesktop.hardware.available?(NativeDesktop::HardwareKind::HID).should be_true
    NativeDesktop.hardware.available?(NativeDesktop::HardwareKind::NFC).should be_false
  end

  it "returns well-formed, uniquely identified snapshots" do
    NativeDesktop::HardwareKind.each do |kind|
      devices = NativeDesktop.hardware.enumerate(kind)
      devices.each do |device|
        device.kind.should eq(kind)
        device.id.empty?.should be_false
        device.name.empty?.should be_false
      end
      devices.map(&.id).uniq.size.should eq(devices.size)
    end
  end

  it "rejects a non-positive hardware monitor interval" do
    expect_raises(ArgumentError) { NativeDesktop::HardwareMonitor.new.start(interval: 0.seconds) { |_| } }
  end
end
