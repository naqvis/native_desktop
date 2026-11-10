require "./spec_helper"

describe NativeDesktop::Toolbar do
  it "builds typed toolbar controls" do
    clicked = false
    toolbar = NativeDesktop::Toolbar.new
    toolbar.button("save", "Save") { clicked = true }
    toolbar.toggle("preview", "Preview", checked: true) { }
    toolbar.dropdown("format", "Format", ["PDF", "HTML"], selected_index: 1) { }
    toolbar.color("accent", "Accent", "#336699") { }
    toolbar.separator

    toolbar.items.size.should eq(5)
    toolbar.items[1].checked.should be_true
    toolbar.items[2].selected_index.should eq(1)
    toolbar.items[4].type.separator?.should be_true
    toolbar.items.first.action.not_nil!.call
    clicked.should be_true
  end

  it "rejects a null host window before dispatch" do
    expect_raises(ArgumentError) do
      NativeDesktop::Toolbar.new.attach(Pointer(Void).null)
    end
  end

  it "requires the GUI runtime for native updates" do
    NativeDesktop::Runtime.detach
    expect_raises(NativeDesktop::RuntimeError) do
      NativeDesktop::Toolbar.new.sync
    end
  end

  it "keeps absent native toolbar operations safe and cleanup idempotent" do
    NativeDesktop::Runtime.detach
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    toolbar = NativeDesktop::Toolbar.new
    toolbar.sync
    toolbar.visible = false
    toolbar.visible = true
    toolbar.cleanup
    toolbar.cleanup
  ensure
    NativeDesktop::Runtime.detach
  end

  it "stores byte and named icons" do
    bytes = NativeDesktop::ToolbarIcon.bytes(Bytes[1_u8, 2_u8], "save")
    named = NativeDesktop::ToolbarIcon.name("document-save")
    bytes.key.should eq("save")
    bytes.bytes.should eq(Bytes[1_u8, 2_u8])
    named.name.should eq("document-save")
  end
end
