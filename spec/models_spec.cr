require "./spec_helper"

describe "native desktop value objects" do
  it "gives equivalent window references value equality and hashes" do
    first = NativeDesktop::Window.attach(Pointer(Void).new(42_u64))
    second = NativeDesktop::Window.attach(Pointer(Void).new(42_u64))
    other = NativeDesktop::Window.attach(Pointer(Void).new(43_u64))

    first.should eq(second)
    first.should_not eq(other)
    Set{first, second, other}.size.should eq(2)
  end

  it "preserves every window-effects option" do
    effects = NativeDesktop::WindowEffects.new(
      vibrancy: true,
      material: :sidebar,
      mica: true,
      acrylic: true,
      blur_behind: true,
    )

    effects.vibrancy.should be_true
    effects.material.should eq(:sidebar)
    effects.mica.should be_true
    effects.acrylic.should be_true
    effects.blur_behind.should be_true
  end

  it "preserves display geometry including negative coordinates" do
    bounds = NativeDesktop::Rectangle.new(-1920, 0, 1920, 1080)
    work = NativeDesktop::Rectangle.new(-1920, 25, 1920, 1055)
    display = NativeDesktop::Display.new(bounds, work, false, "External", 1.5)

    display.bounds.x.should eq(-1920)
    display.work_area.should eq(work)
    display.primary.should be_false
    display.primary?.should be_false
    display.name.should eq("External")
    display.scale_factor.should eq(1.5)
    expect_raises(ArgumentError) { NativeDesktop::Display.new(bounds, work, scale_factor: 0.0) }
  end

  it "keeps native error codes available for recovery" do
    error = NativeDesktop::Error.new("failed", :test_failure)
    error.message.should eq("failed")
    error.code.should eq(:test_failure)
  end

  it "preserves autostart arguments and launch options" do
    arguments = ["--profile", "two words"]
    entry = NativeDesktop::AutostartEntry.new("Example", Path["/tmp/example"], arguments, true, 3.seconds)

    entry.arguments.should eq(arguments)
    entry.minimized.should be_true
    entry.delay.should eq(3.seconds)
  end
end
