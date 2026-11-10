require "./spec_helper"

describe NativeDesktop::ContextMenuItem do
  it "stores nested menu state" do
    child = NativeDesktop::ContextMenuItem.new("copy", "Copy")
    parent = NativeDesktop::ContextMenuItem.new(
      "edit",
      "Edit",
      submenu: [child]
    )

    parent.submenu.should eq([child])
    parent.enabled?.should be_true
  end

  it "supports separators and checked entries" do
    separator = NativeDesktop::ContextMenuItem.new(type: NativeDesktop::ContextMenuItemType::Separator)
    checked = NativeDesktop::ContextMenuItem.new(
      "enabled",
      "Enabled",
      checked: true,
      type: NativeDesktop::ContextMenuItemType::Checkbox
    )

    separator.type.separator?.should be_true
    checked.checked?.should be_true
  end
end

describe NativeDesktop::ContextMenus do
  it "requires the GUI runtime" do
    NativeDesktop::Runtime.detach
    expect_raises(NativeDesktop::RuntimeError) { NativeDesktop.context_menus.available? }
  end

  it "compiles the native show path without opening an interactive menu" do
    if ENV["NATIVE_DESKTOP_INTERACTIVE_CONTEXT_MENU"]?
      item = NativeDesktop::ContextMenuItem.new("test", "Test")
      NativeDesktop.context_menus.show([item], 0, 0, Pointer(Void).new(1_u64))
    end
  end
end
