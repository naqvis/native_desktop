require "./spec_helper"

describe NativeDesktop::CPU do
  it "validates aggregate counters" do
    times = NativeDesktop::CPUTimes.new(25_u64, 100_u64)
    times.busy.should eq(25_u64)
    times.total.should eq(100_u64)
    expect_raises(ArgumentError) { NativeDesktop::CPUTimes.new(2_u64, 1_u64) }
  end

  it "reads valid aggregate counters" do
    times = NativeDesktop.cpu.times
    times.total.should be >= times.busy
    times.total.should be > 0_u64
  end

  it "requires a baseline before reporting utilization" do
    sampler = NativeDesktop::CPUSampler.new
    sampler.sample.should be_nil
    sampler.reset
    sampler.sample.should be_nil
  end

  it "serializes samples from parallel execution contexts" do
    sampler = NativeDesktop::CPUSampler.new
    results = Channel(Float64?).new(8)
    workers = Fiber::ExecutionContext::Parallel.new("native-desktop-cpu-spec", maximum: 4)
    8.times { workers.spawn { results.send(sampler.sample) } }

    8.times do
      results.receive.try do |usage|
        usage.should be >= 0.0
        usage.should be <= 100.0
      end
    end
  end
end
