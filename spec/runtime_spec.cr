require "./spec_helper"

describe NativeDesktop::Runtime do
  after_each { NativeDesktop::Runtime.detach }

  it "tracks attachment on the GUI thread" do
    NativeDesktop::Runtime.attached?.should be_false
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    NativeDesktop::Runtime.attached?.should be_true
    NativeDesktop::Runtime.gui_thread?.should be_true
  end

  it "rejects a second host attachment" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    error = expect_raises(NativeDesktop::RuntimeError) do
      NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    end
    error.code.should eq(:already_attached)
  end

  it "returns values and propagates exceptions inline" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    NativeDesktop::Runtime.dispatch_sync { 42 }.should eq(42)
    expect_raises(ArgumentError, "failure") do
      NativeDesktop::Runtime.dispatch_sync do
        raise ArgumentError.new("failure")
        0
      end
    end
  end

  it "dispatches asynchronous work through the host" do
    queued = Channel(Proc(Nil)).new(1)
    completed = Channel(Bool).new(1)
    NativeDesktop::Runtime.attach_to_current_thread { |work| queued.send(work) }
    workers = Fiber::ExecutionContext::Parallel.new("native-desktop-async", maximum: 1)
    workers.spawn { NativeDesktop::Runtime.dispatch { completed.send(true) } }

    queued.receive.call
    completed.receive.should be_true
  end

  it "uses the background executor supplied by the host" do
    queued = Channel(Proc(Nil)).new(1)
    completed = Channel(Bool).new(1)
    background = ->(work : Proc(Nil)) { queued.send(work) }
    NativeDesktop::Runtime.attach_to_current_thread(background: background) { |work| work.call }

    NativeDesktop::Runtime.spawn_background { completed.send(true) }
    queued.receive.call
    completed.receive.should be_true
  end

  it "rejects background work when the host did not supply an executor" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    error = expect_raises(NativeDesktop::RuntimeError) do
      NativeDesktop::Runtime.spawn_background { }
    end
    error.code.should eq(:background_executor_missing)
  end

  it "propagates dispatcher rejection without leaving a pending request" do
    NativeDesktop::Runtime.attach_to_current_thread do |_work|
      raise IO::Error.new("dispatcher stopped")
    end
    workers = Fiber::ExecutionContext::Parallel.new("native-desktop-dispatcher-error", maximum: 1)
    failure = Channel(Exception).new(1)
    workers.spawn do
      NativeDesktop::Runtime.dispatch_sync { 1 }
    rescue ex
      failure.send(ex)
    end

    failure.receive.should be_a(IO::Error)
    NativeDesktop::Runtime.detach
  end

  it "routes synchronous work from a parallel execution context" do
    queued = Channel(Proc(Nil)).new(1)
    result = Channel(Int32).new(1)
    NativeDesktop::Runtime.attach_to_current_thread { |work| queued.send(work) }
    workers = Fiber::ExecutionContext::Parallel.new("native-desktop-runtime", maximum: 1)
    workers.spawn { result.send(NativeDesktop::Runtime.dispatch_sync { 73 }) }

    queued.receive.call
    result.receive.should eq(73)
  end

  it "propagates NoReturn native-work exceptions to the waiting fiber" do
    queued = Channel(Proc(Nil)).new(1)
    result = Channel(Exception).new(1)
    NativeDesktop::Runtime.attach_to_current_thread { |work| queued.send(work) }
    workers = Fiber::ExecutionContext::Parallel.new("native-desktop-runtime-errors", maximum: 1)
    workers.spawn do
      NativeDesktop::Runtime.dispatch_sync do
        raise IO::Error.new("native failure")
      end
    rescue ex
      result.send(ex)
    end

    queued.receive.call
    result.receive.should be_a(IO::Error)
  end

  it "unblocks every pending caller on detach" do
    queued = Channel(Proc(Nil)).new(4)
    errors = Channel(Exception).new(4)
    NativeDesktop::Runtime.attach_to_current_thread { |work| queued.send(work) }
    workers = Fiber::ExecutionContext::Parallel.new("native-desktop-detach", maximum: 4)
    4.times do
      workers.spawn do
        NativeDesktop::Runtime.dispatch_sync { 1 }
      rescue ex
        errors.send(ex)
      end
    end
    4.times { queued.receive }

    NativeDesktop::Runtime.detach
    4.times do
      error = errors.receive.as(NativeDesktop::RuntimeError)
      error.code.should eq(:detached)
    end
  end

  it "does not execute stale queued work after reattachment" do
    queued = Channel(Proc(Nil)).new(1)
    error = Channel(Exception).new(1)
    ran = Atomic(Bool).new(false)
    NativeDesktop::Runtime.attach_to_current_thread { |work| queued.send(work) }
    workers = Fiber::ExecutionContext::Parallel.new("native-desktop-generation", maximum: 1)
    workers.spawn do
      NativeDesktop::Runtime.dispatch_sync { ran.set(true) }
    rescue ex
      error.send(ex)
    end
    stale = queued.receive
    NativeDesktop::Runtime.detach
    error.receive.should be_a(NativeDesktop::RuntimeError)
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    stale.call
    ran.get.should be_false
  end
end
