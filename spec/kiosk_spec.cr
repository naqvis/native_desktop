require "./spec_helper"

describe NativeDesktop::Kiosk do
  it "rejects a null host window before dispatching" do
    expect_raises(ArgumentError, /window handle/) do
      NativeDesktop::Kiosk.new(Pointer(Void).null)
    end
  end
end
