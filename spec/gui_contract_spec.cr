require "./spec_helper"

describe "GUI-bound service contracts" do
  after_each { NativeDesktop::Runtime.detach }

  it "requires an attached runtime for every clipboard operation" do
    operations = [
      -> { NativeDesktop.clipboard.read_text; nil },
      -> { NativeDesktop.clipboard.write_text("text"); nil },
      -> { NativeDesktop.clipboard.read_html; nil },
      -> { NativeDesktop.clipboard.write_html("<b>text</b>"); nil },
      -> { NativeDesktop.clipboard.read_rtf; nil },
      -> { NativeDesktop.clipboard.write_rtf("{\\rtf1 text}"); nil },
      -> { NativeDesktop.clipboard.read_image; nil },
      -> { NativeDesktop.clipboard.write_image(Bytes[1_u8]); nil },
      -> { NativeDesktop.clipboard.clear; nil },
      -> { NativeDesktop.clipboard.version; nil },
    ]
    operations.each { |operation| expect_raises(NativeDesktop::RuntimeError) { operation.call } }
  end

  it "rejects a non-positive clipboard monitor interval" do
    expect_raises(ArgumentError) { NativeDesktop::ClipboardMonitor.new.start(0.seconds) { |_| } }
  end

  it "requires an attached runtime for every dialog operation" do
    operations = [
      -> { NativeDesktop.dialogs.open_file; nil },
      -> { NativeDesktop.dialogs.open_files; nil },
      -> { NativeDesktop.dialogs.save_file; nil },
      -> { NativeDesktop.dialogs.select_folder; nil },
      -> { NativeDesktop.dialogs.message("Title", "Message"); nil },
      -> { NativeDesktop.dialogs.confirm("Title", "Message"); nil },
    ]
    operations.each { |operation| expect_raises(NativeDesktop::RuntimeError) { operation.call } }
  end

  it "requires an attached runtime for display queries" do
    expect_raises(NativeDesktop::RuntimeError) { NativeDesktop.displays.all }
    expect_raises(NativeDesktop::RuntimeError) { NativeDesktop.displays.cursor }
  end

  it "requires an attached runtime before touching a native window" do
    window = NativeDesktop::Window.attach(Pointer(Void).new(1_u64))
    expect_raises(NativeDesktop::RuntimeError) { window.always_on_top = true }
    expect_raises(NativeDesktop::RuntimeError) { window.titlebar_overlay = true }
    expect_raises(NativeDesktop::RuntimeError) { window.apply(NativeDesktop::WindowEffects.new(mica: true)) }
  end

  it "requires an attached runtime for drag source operations" do
    window = NativeDesktop::Window.attach(Pointer(Void).new(1_u64))
    source = NativeDesktop::DragSource.new(window)
    payload = NativeDesktop::DragPayload.text("test")
    expect_raises(NativeDesktop::RuntimeError) { source.start(payload) }
    expect_raises(NativeDesktop::RuntimeError) { source.close }
  end

  it "builds typed drag payloads and rejects empty values" do
    NativeDesktop::DragPayload.file("document.txt").kind.file?.should be_true
    NativeDesktop::DragPayload.text("text").kind.text?.should be_true
    NativeDesktop::DragPayload.url("https://example.com").kind.url?.should be_true
    NativeDesktop::DragPayload.image("image.png").kind.image?.should be_true
    expect_raises(ArgumentError) { NativeDesktop::DragPayload.text("") }
  end

  it "preserves dialog option values" do
    filter = NativeDesktop::FileFilter.new("Images", %w(png jpg))
    open = NativeDesktop::OpenDialogOptions.new("Open", Path["/tmp"], [filter])
    save = NativeDesktop::SaveDialogOptions.new("Save", Path["/tmp"], "image.png", [filter])
    folder = NativeDesktop::FolderDialogOptions.new("Folder", Path["/tmp"])

    open.filters.should eq([filter])
    save.suggested_name.should eq("image.png")
    folder.directory.should eq(Path["/tmp"])

    owner = Pointer(Void).new(1_u64)
    rich_open = NativeDesktop::OpenDialogOptions.new(owner: owner, accept_label: "Choose", show_hidden: true)
    rich_save = NativeDesktop::SaveDialogOptions.new(default_extension: "txt", confirm_overwrite: false)
    rich_folder = NativeDesktop::FolderDialogOptions.new(can_create_directories: false)
    rich_open.owner.should eq(owner)
    rich_open.accept_label.should eq("Choose")
    rich_open.show_hidden.should be_true
    rich_save.default_extension.should eq("txt")
    rich_save.confirm_overwrite.should be_false
    rich_folder.can_create_directories.should be_false
  end
end
