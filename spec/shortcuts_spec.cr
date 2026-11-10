require "./spec_helper"

describe NativeDesktop::Shortcut do
  it "builds a stable identifier independent of modifier order" do
    first = NativeDesktop::Shortcut.new(
      [NativeDesktop::ShortcutModifier::Shift, NativeDesktop::ShortcutModifier::Ctrl],
      NativeDesktop::ShortcutKey::A
    )
    second = NativeDesktop::Shortcut.new(
      [NativeDesktop::ShortcutModifier::Ctrl, NativeDesktop::ShortcutModifier::Shift],
      NativeDesktop::ShortcutKey::A
    )

    first.identifier.should eq("Ctrl+Shift+A")
    second.identifier.should eq(first.identifier)
  end

  it "identifies an unmodified key" do
    shortcut = NativeDesktop::Shortcut.new(([] of NativeDesktop::ShortcutModifier), NativeDesktop::ShortcutKey::F5)
    shortcut.identifier.should eq("F5")
  end
end

describe NativeDesktop::GlobalShortcuts do
  it "tracks registrations without touching the platform before start" do
    shortcuts = NativeDesktop::GlobalShortcuts.new
    shortcut = NativeDesktop::Shortcut.new([NativeDesktop::ShortcutModifier::Ctrl], NativeDesktop::ShortcutKey::Comma)

    shortcuts.register(shortcut) { }
    shortcuts.registered.should eq([shortcut])
    shortcuts.unregister(shortcut)
    shortcuts.registered.should be_empty
  end

  it "rejects duplicate normalized registrations" do
    shortcuts = NativeDesktop::GlobalShortcuts.new
    shortcut = NativeDesktop::Shortcut.new([NativeDesktop::ShortcutModifier::Meta], NativeDesktop::ShortcutKey::Space)
    shortcuts.register(shortcut) { }

    error = expect_raises(NativeDesktop::Error) { shortcuts.register(shortcut) { } }
    error.code.should eq(:shortcut_conflict)
  end

  it "clears all registrations while stopped" do
    shortcuts = NativeDesktop::GlobalShortcuts.new
    shortcuts.register(NativeDesktop::Shortcut.new(([] of NativeDesktop::ShortcutModifier), NativeDesktop::ShortcutKey::A)) { }
    shortcuts.register(NativeDesktop::Shortcut.new(([] of NativeDesktop::ShortcutModifier), NativeDesktop::ShortcutKey::B)) { }

    shortcuts.unregister_all
    shortcuts.registered.should be_empty
    shortcuts.listening?.should be_false
  end
end

{% if flag?(:darwin) %}
  describe NativeDesktop::Platform::MacOS::Shortcuts do
    it "retains a run loop shared with the controlling thread" do
      ready = Channel(Void*).new(1)
      thread = Thread.new do
        run_loop = NativeDesktop::Platform::MacOS::Shortcuts::LibCFShortcuts.CFRunLoopGetCurrent
        NativeDesktop::Platform::MacOS::Shortcuts::LibCFShortcuts.CFRetain(run_loop)
        ready.send(run_loop)
      end

      run_loop = ready.receive
      thread.join
      NativeDesktop::Platform::MacOS::Shortcuts::LibCFShortcuts.CFRunLoopStop(run_loop)
      NativeDesktop::Platform::MacOS::Shortcuts::LibCFShortcuts.CFRunLoopWakeUp(run_loop)
      NativeDesktop::Platform::MacOS::Shortcuts::LibCFShortcuts.CFRelease(run_loop)
    end
  end
{% end %}
