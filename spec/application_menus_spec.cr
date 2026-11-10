require "./spec_helper"

describe NativeDesktop::MenuBar do
  it "stores nested menus, separators, state, and callbacks" do
    invoked = false
    open = NativeDesktop::MenuItem.new(
      "open",
      "Open",
      accelerator: "Cmd+O",
      action: -> { invoked = true }
    )
    recent = NativeDesktop::Menu.new("Recent", entries: [open] of NativeDesktop::MenuItem | NativeDesktop::Menu | NativeDesktop::MenuSeparator)
    file = NativeDesktop::Menu.new(
      "File",
      entries: [recent, NativeDesktop::MenuSeparator.new] of NativeDesktop::MenuItem | NativeDesktop::Menu | NativeDesktop::MenuSeparator
    )
    bar = NativeDesktop::MenuBar.new([file])

    bar.menus.first.entries.size.should eq(2)
    open.accelerator.should eq("Cmd+O")
    open.action.not_nil!.call
    invoked.should be_true
  end

  it "requires an attached GUI runtime for installation" do
    NativeDesktop::Runtime.detach
    expect_raises(NativeDesktop::RuntimeError) do
      NativeDesktop.application_menus.install(NativeDesktop::MenuBar.new)
    end
  end

  it "builds application menus without exposing platform models" do
    bar = NativeDesktop::MenuBar.new
    selected = false

    bar.menu("File", "file") do |file|
      file.item("open", "Open", accelerator: "Cmd+O") { selected = true }
      file.separator
      file.menu("Recent") do |recent|
        recent.item("first", "First") { }
      end
    end

    bar.menus.first.entries.size.should eq(3)
    bar.menus.first.entries.first.as(NativeDesktop::MenuItem).action.not_nil!.call
    selected.should be_true
  end
end
