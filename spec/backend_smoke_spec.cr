require "./spec_helper"

# Headless-safe backend smoke tests. These exercise real operating-system
# backends that need neither a GUI runtime nor a native window, so they run in
# CI on macOS, Linux, and Windows without a display. GUI-bound and
# permission-gated backends are covered by the contract specs instead.

describe "headless backend smoke" do
  it "reads aggregate CPU counters" do
    times = NativeDesktop.cpu.times
    times.busy.should be <= times.total
    times.total.should be >= 0
  end

  it "samples CPU utilization" do
    sampler = NativeDesktop::CPUSampler.new
    sampler.sample.should be_nil # baseline sample

    value = sampler.sample
    (value.nil? || (value >= 0.0 && value <= 100.0)).should be_true
  end

  it "reads the user idle duration" do
    NativeDesktop.idle.duration.should be_a(Time::Span)
  end

  it "reads the effective system color scheme" do
    scheme = NativeDesktop.system_theme.current
    (scheme.light? || scheme.dark?).should be_true
  end

  it "enumerates hardware without a GUI runtime" do
    NativeDesktop.hardware.available?(NativeDesktop::HardwareKind::NFC).should be_false
    devices = NativeDesktop.hardware.enumerate(NativeDesktop::HardwareKind::USB)
    devices.should be_a(Array(NativeDesktop::HardwareDevice))
  end

  it "acquires and releases a single-instance lock" do
    lock = NativeDesktop.instance_lock("native-desktop-smoke-#{Process.pid}")
    begin
      lock.acquire.should be_true
      lock.acquired?.should be_true
      lock.acquire.should be_true # idempotent on the same object
    ensure
      lock.release
    end
    lock.acquired?.should be_false
  end

  it "reports biometric capability without prompting" do
    NativeDesktop.biometric.info.available?.should be_a(Bool)
  end

  it "exposes a non-empty capability catalog" do
    NativeDesktop.capabilities.all.should_not be_empty
  end

  it "configures application identity and collects diagnostics" do
    NativeDesktop.application.configure(
      NativeDesktop::ApplicationIdentity.new(
        "dev.example.smoke",
        "Smoke Test",
        Path[Process.executable_path.not_nil!].expand
      )
    )

    NativeDesktop.application.diagnostics.should be_a(Array(NativeDesktop::Diagnostic))
  end
end
