require "./spec_helper"

describe NativeDesktop::SystemTheme do
  after_each { NativeDesktop::Runtime.detach }

  it "reads the current effective appearance" do
    NativeDesktop.system_theme.current.should be_a(NativeDesktop::ColorScheme)
  end

  it "starts and stops a monitor through the host background executor" do
    queued = Channel(Proc(Nil)).new(1)
    background = ->(work : Proc(Nil)) { queued.send(work) }
    NativeDesktop::Runtime.attach_to_current_thread(background: background) { |work| work.call }
    monitor = NativeDesktop::ThemeMonitor.new

    monitor.start(1.second) { }
    monitor.running?.should be_true
    queued.empty?.should be_false

    monitor.stop
    monitor.running?.should be_false
  end

  it "rejects a non-positive polling interval" do
    expect_raises(ArgumentError) { NativeDesktop::ThemeMonitor.new.start(0.seconds) { } }
  end
end
