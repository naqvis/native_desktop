require "./spec_helper"

describe NativeDesktop::TrayMenuItem do
  it "stores typed nested menu items" do
    child = NativeDesktop::TrayMenuItem.new("open", "Open")
    parent = NativeDesktop::TrayMenuItem.new("file", "File", submenu: [child])

    parent.submenu.should eq([child])
    parent.type.normal?.should be_true
  end

  it "stores callbacks and state" do
    invoked = false
    item = NativeDesktop::TrayMenuItem.new(
      "enabled",
      "Enabled",
      NativeDesktop::TrayMenuItemType::Checkbox,
      checked: true,
      action: -> { invoked = true }
    )

    item.checked.should be_true
    item.action.not_nil!.call
    invoked.should be_true
  end
end

describe NativeDesktop::Tray do
  it "requires the GUI runtime" do
    NativeDesktop::Runtime.detach
    expect_raises(NativeDesktop::RuntimeError) do
      NativeDesktop.tray.create("com.example.application")
    end
  end

  it "can destroy an absent tray after runtime attachment" do
    NativeDesktop::Runtime.detach
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    NativeDesktop.tray.on_click { |_button| }
    NativeDesktop.tray.set_menu([
      NativeDesktop::TrayMenuItem.new("open", "Open", action: -> { }),
    ])
    NativeDesktop.tray.tooltip = "Example"
    NativeDesktop.tray.update_icon(NativeDesktop::TrayIcon.name("application"))
    NativeDesktop.tray.destroy
  ensure
    NativeDesktop::Runtime.detach
  end
end
