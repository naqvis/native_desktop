require "./spec_helper"

describe NativeDesktop do
  after_each { NativeDesktop::Runtime.detach }

  it "rejects null window handles" do
    expect_raises(ArgumentError) do
      NativeDesktop::Window.attach(Pointer(Void).null)
    end
  end

  it "attaches a native window without taking ownership" do
    handle = Pointer(Void).new(42_u64)
    NativeDesktop::Window.attach(handle).handle.should eq(handle)
  end

  it "rejects invalid opacity before dispatching to the GUI runtime" do
    window = NativeDesktop::Window.attach(Pointer(Void).new(42_u64))
    expect_raises(ArgumentError) { window.opacity = -0.1 }
    expect_raises(ArgumentError) { window.opacity = 1.1 }
    expect_raises(ArgumentError) { window.opacity = Float64::NAN }
  end

  it "describes window effects without platform selection" do
    effects = NativeDesktop::WindowEffects.new(vibrancy: true, material: :sidebar)

    effects.vibrancy.should be_true
    effects.material.should eq(:sidebar)
  end

  it "represents display geometry without platform handles" do
    bounds = NativeDesktop::Rectangle.new(0, 0, 1920, 1080)
    display = NativeDesktop::Display.new(bounds, bounds, primary: true)

    display.bounds.should eq(bounds)
    display.primary.should be_true
  end

  it "rejects an empty external target" do
    expect_raises(ArgumentError) do
      NativeDesktop.applications.open("")
    end
  end

  it "queries the foreground application without raising" do
    NativeDesktop.applications.foreground_name.should be_a(String | Nil)
  end

  it "validates URL-scheme registrations before touching the OS" do
    expect_raises(ArgumentError) do
      NativeDesktop.url_schemes.register(
        NativeDesktop::URLSchemeRegistration.new("1invalid", "Example", Path["/tmp/example"]),
      )
    end

    expect_raises(ArgumentError) do
      NativeDesktop.url_schemes.register(
        NativeDesktop::URLSchemeRegistration.new("example", "Example", Path["relative"]),
      )
    end
  end

  it "validates autostart entries before touching the OS" do
    expect_raises(ArgumentError) do
      NativeDesktop.autostart.enable(
        NativeDesktop::AutostartEntry.new("Example", Path["relative"]),
      )
    end

    expect_raises(ArgumentError) do
      NativeDesktop.autostart.enable(
        NativeDesktop::AutostartEntry.new("Example", Path["/tmp/example"], delay: -1.second),
      )
    end
  end

  it "runs GUI work inline on the attached fiber" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    NativeDesktop::Runtime.dispatch_sync { 42 }.should eq(42)
  end

  it "stores file filters in dialog options" do
    extensions = %w(png jpg)
    filters = [NativeDesktop::FileFilter.new("Images", extensions)]
    options = NativeDesktop::OpenDialogOptions.new(filters: filters)

    options.filters.should eq(filters)
    options.filters.first.extensions.should eq(extensions)
  end

  it "requires an attached host runtime for off-GUI work" do
    error = Channel(Exception).new(1)
    spawn do
      NativeDesktop::Runtime.dispatch_sync { 42 }
    rescue ex
      error.send(ex)
    end
    error.receive.should be_a(NativeDesktop::RuntimeError)
  end

  it "wakes pending GUI work when the host detaches" do
    queued = Channel(Proc(Nil)).new(1)
    NativeDesktop::Runtime.attach_to_current_thread { |work| queued.send(work) }
    workers = Fiber::ExecutionContext::Parallel.new("native-desktop-spec", maximum: 1)

    error = Channel(Exception).new(1)
    workers.spawn do
      NativeDesktop::Runtime.dispatch_sync { 42 }
    rescue ex
      error.send(ex)
    end

    queued.receive
    NativeDesktop::Runtime.detach
    received = error.receive
    received.should be_a(NativeDesktop::RuntimeError)
    received.as(NativeDesktop::RuntimeError).code.should eq(:detached)
  end
end
