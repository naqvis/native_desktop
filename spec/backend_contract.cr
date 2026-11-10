require "../src/native_desktop"

# This branch is intentionally runtime-disabled. Building this file forces
# Crystal's lazy compiler to type-check the complete platform paths that need a
# real native window and therefore cannot run in headless CI.
if ENV["NATIVE_DESKTOP_RUN_BACKEND_CONTRACT"]? == "1"
  NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
  window = NativeDesktop::Window.attach(Pointer(Void).new(1_u64))

  NativeDesktop::Dialogs.open_file(
    NativeDesktop::OpenDialogOptions.new(
      owner: window.handle,
      accept_label: "Choose",
      show_hidden: true
    )
  )
  NativeDesktop::Dialogs.save_file(
    NativeDesktop::SaveDialogOptions.new(
      owner: window.handle,
      accept_label: "Save",
      default_extension: "txt",
      show_hidden: true,
      can_create_directories: false,
      confirm_overwrite: false
    )
  )
  NativeDesktop::Dialogs.select_folder(
    NativeDesktop::FolderDialogOptions.new(
      owner: window.handle,
      accept_label: "Choose",
      show_hidden: true,
      can_create_directories: false
    )
  )

  NativeDesktop::DropTarget.new(window) { |_event| }.close
end
