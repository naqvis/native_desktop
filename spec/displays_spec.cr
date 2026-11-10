require "./spec_helper"

describe NativeDesktop::Displays do
  before_each { NativeDesktop::Runtime.attach_to_current_thread { |work| work.call } }
  after_each { NativeDesktop::Runtime.detach }

  it "reports per-display names and scale factors" do
    displays = NativeDesktop.displays.all
    displays.should_not be_empty
    displays.first.primary?.should be_true
    displays.each do |display|
      display.name.should_not be_empty
      display.scale_factor.should be > 0.0
    end
  end

  it "returns the primary display" do
    NativeDesktop.displays.primary.try(&.primary?).should be_true
  end

  it "rejects a non-positive display monitor interval" do
    expect_raises(ArgumentError) { NativeDesktop::DisplayMonitor.new.start(0.seconds) { |_| } }
  end
end
