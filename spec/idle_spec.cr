require "./spec_helper"

describe NativeDesktop::Idle do
  after_each { NativeDesktop::Runtime.detach }

  it "reads a non-negative idle duration" do
    NativeDesktop.idle.duration.should be >= 0.seconds
  end

  it "evaluates a custom threshold" do
    NativeDesktop.idle.idle?(0.seconds).should be_true
    expect_raises(ArgumentError) { NativeDesktop.idle.idle?(-1.second) }
  end

  it "represents activity changes" do
    change = NativeDesktop::ActivityChange.new(NativeDesktop::ActivityState::Idle, 5.minutes)
    change.idle?.should be_true
    change.active?.should be_false
    change.duration.should eq(5.minutes)
  end

  it "starts and stops through the host background executor" do
    queued = Channel(Proc(Nil)).new(1)
    background = ->(work : Proc(Nil)) { queued.send(work) }
    NativeDesktop::Runtime.attach_to_current_thread(background: background) { |work| work.call }
    monitor = NativeDesktop::IdleMonitor.new

    monitor.start { }
    monitor.running?.should be_true
    queued.empty?.should be_false

    monitor.stop
    monitor.running?.should be_false
  end
end
