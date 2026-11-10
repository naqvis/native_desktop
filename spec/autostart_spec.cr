require "./spec_helper"
require "file_utils"

def autostart_test_exe : Path
  {% if flag?(:windows) %}
    Path[Dir.current, "test_app"]
  {% else %}
    Path["/tmp/example"]
  {% end %}
end

describe NativeDesktop::Autostart do
  test_root = Path[File.tempname("native-desktop-autostart")]

  before_all do
    Dir.mkdir_p(test_root)
    ENV["NATIVE_DESKTOP_AUTOSTART_DIR"] = test_root.to_s
    {% if flag?(:windows) %}
      ENV["NATIVE_DESKTOP_AUTOSTART_KEY"] = "HKCU\\Software\\NativeDesktop\\Specs\\Autostart"
    {% end %}
  end

  after_all do
    ENV.delete("NATIVE_DESKTOP_AUTOSTART_DIR")
    ENV.delete("NATIVE_DESKTOP_AUTOSTART_KEY")
    FileUtils.rm_rf(test_root)
  end

  it "round-trips an entry" do
    entry = NativeDesktop::AutostartEntry.new("roundtrip", autostart_test_exe)
    NativeDesktop.autostart.enabled?(entry.name).should be_false
    NativeDesktop.autostart.enable(entry)
    NativeDesktop.autostart.enabled?(entry.name).should be_true
    NativeDesktop.autostart.disable(entry.name)
    NativeDesktop.autostart.enabled?(entry.name).should be_false
  end

  it "replaces an existing entry idempotently" do
    first = NativeDesktop::AutostartEntry.new("replace", autostart_test_exe, ["--first"])
    second = NativeDesktop::AutostartEntry.new("replace", autostart_test_exe, ["--second"], true, 5.seconds)
    begin
      NativeDesktop.autostart.enable(first)
      NativeDesktop.autostart.enable(second)
      NativeDesktop.autostart.enabled?(second.name).should be_true
    ensure
      NativeDesktop.autostart.disable(second.name)
    end
  end

  it "rejects invalid input before writing" do
    expect_raises(ArgumentError) { NativeDesktop.autostart.enable(NativeDesktop::AutostartEntry.new("", autostart_test_exe)) }
    expect_raises(ArgumentError) { NativeDesktop.autostart.enable(NativeDesktop::AutostartEntry.new("app", Path["relative"])) }
    expect_raises(ArgumentError) { NativeDesktop.autostart.enable(NativeDesktop::AutostartEntry.new("app", autostart_test_exe, delay: -1.second)) }
    expect_raises(ArgumentError) { NativeDesktop.autostart.enable(NativeDesktop::AutostartEntry.new("app", autostart_test_exe, ["bad\0arg"])) }
  end

  {% if flag?(:darwin) %}
    it "writes escaped LaunchAgent arguments without turning delay into a repeating interval" do
      entry = NativeDesktop::AutostartEntry.new("My App", Path["/tmp/My App"], ["<&\""], true, 7.seconds)
      begin
        NativeDesktop.autostart.enable(entry)
        content = File.read(test_root / "My_App.plist")
        content.should contain("<string>/tmp/My App</string>")
        content.should contain("<string>&lt;&amp;&quot;</string>")
        content.should contain("<string>--minimized</string>")
        content.should_not contain("StartInterval")
      ensure
        NativeDesktop.autostart.disable(entry.name)
      end
    end
  {% elsif flag?(:linux) %}
    it "writes a quoted XDG desktop entry" do
      entry = NativeDesktop::AutostartEntry.new("My App", Path["/tmp/My App"], ["--value", "two words"], true, 7.seconds)
      begin
        NativeDesktop.autostart.enable(entry)
        content = File.read(test_root / "my_app.desktop")
        content.should contain(%(Exec="/tmp/My App" "--value" "two words" "--minimized"))
        content.should contain("X-GNOME-Autostart-Delay=7")
      ensure
        NativeDesktop.autostart.disable(entry.name)
      end
    end
  {% end %}
end
