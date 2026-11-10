require "./spec_helper"

describe NativeDesktop::Power do
  after_each { NativeDesktop::Runtime.detach }

  it "represents a battery snapshot" do
    status = NativeDesktop::BatteryStatus.new(0.5, charging: true, external_power: true, remaining: 45.minutes)
    status.level.should eq(0.5)
    status.charging?.should be_true
    status.external_power?.should be_true
    status.on_battery?.should be_false
    status.remaining.should eq(45.minutes)
  end

  it "validates battery values" do
    expect_raises(ArgumentError) { NativeDesktop::BatteryStatus.new(1.1, false, false) }
    expect_raises(ArgumentError) { NativeDesktop::BatteryStatus.new(0.5, false, false, -1.second) }
  end

  it "reads the current power state" do
    NativeDesktop.power.on_battery?.should be_a(Bool)
    if status = NativeDesktop.power.battery
      status.level.try do |level|
        level.should be >= 0.0
        level.should be <= 1.0
      end
    end
  end

  it "starts and stops through the host background executor" do
    queued = Channel(Proc(Nil)).new(1)
    background = ->(work : Proc(Nil)) { queued.send(work) }
    NativeDesktop::Runtime.attach_to_current_thread(background: background) { |work| work.call }
    monitor = NativeDesktop::PowerMonitor.new

    monitor.start(1.second) { }
    monitor.running?.should be_true
    queued.empty?.should be_false

    monitor.stop
    monitor.running?.should be_false
  end
end
