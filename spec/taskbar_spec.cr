require "./spec_helper"

describe NativeDesktop::TaskbarIcon do
  it "accepts bytes and names" do
    bytes = Bytes[1, 2, 3]
    NativeDesktop::TaskbarIcon.bytes(bytes).bytes.should eq(bytes)
    NativeDesktop::TaskbarIcon.name("information").name.should eq("information")
  end

  it "rejects empty values" do
    expect_raises(ArgumentError) { NativeDesktop::TaskbarIcon.bytes(Bytes.empty) }
    expect_raises(ArgumentError) { NativeDesktop::TaskbarIcon.name("") }
  end
end

describe NativeDesktop::Taskbar do
  it "rejects a null window before dispatching" do
    expect_raises(ArgumentError, /window handle/) do
      NativeDesktop::Taskbar.new(Pointer(Void).null)
    end
  end

  it "rejects an empty application id before dispatching" do
    expect_raises(ArgumentError, /application id/) do
      NativeDesktop::Taskbar.new(Pointer(Void).new(1_u64), "")
    end
  end
end
