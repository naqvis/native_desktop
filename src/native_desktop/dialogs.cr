{% if flag?(:darwin) %}
  require "./platform/macos/dialogs"
{% elsif flag?(:linux) %}
  require "./platform/linux/dialogs"
{% elsif flag?(:windows) %}
  require "./platform/windows/dialogs"
{% end %}

module NativeDesktop
  # A file type shown in an open or save dialog.
  # Extensions should not include a leading dot.
  record FileFilter, name : String, extensions : Array(String)

  # Settings shared by single- and multiple-file open dialogs.
  record OpenDialogOptions,
    title : String? = nil,
    directory : Path? = nil,
    filters : Array(FileFilter) = [] of FileFilter,
    owner : Void*? = nil,
    accept_label : String? = nil,
    show_hidden : Bool = false

  # Settings for a save dialog.
  record SaveDialogOptions,
    title : String? = nil,
    directory : Path? = nil,
    suggested_name : String? = nil,
    filters : Array(FileFilter) = [] of FileFilter,
    owner : Void*? = nil,
    accept_label : String? = nil,
    default_extension : String? = nil,
    show_hidden : Bool = false,
    can_create_directories : Bool = true,
    confirm_overwrite : Bool = true

  # Settings for a folder picker.
  record FolderDialogOptions,
    title : String? = nil,
    directory : Path? = nil,
    owner : Void*? = nil,
    accept_label : String? = nil,
    show_hidden : Bool = false,
    can_create_directories : Bool = true

  # Visual severity used by a message dialog.
  enum MessageKind
    Info
    Warning
    Error
  end

  # Native file pickers and message dialogs.
  #
  # Every operation is marshalled through `Runtime` and therefore requires an
  # attached GUI host.
  module Dialogs
    extend self

    # Opens a single-file picker and returns the selected path.
    def open_file(options = OpenDialogOptions.new) : Path?
      Runtime.dispatch_sync { Platform::Dialogs.open_file(options).try { |path| Path[path] } }
    end

    # Opens a multiple-file picker and returns all selected paths.
    def open_files(options = OpenDialogOptions.new) : Array(Path)
      Runtime.dispatch_sync { Platform::Dialogs.open_files(options).map { |path| Path[path] } }
    end

    # Opens a save picker and returns the selected destination.
    def save_file(options = SaveDialogOptions.new) : Path?
      Runtime.dispatch_sync { Platform::Dialogs.save_file(options).try { |path| Path[path] } }
    end

    # Opens a folder picker and returns the selected directory.
    def select_folder(options = FolderDialogOptions.new) : Path?
      Runtime.dispatch_sync { Platform::Dialogs.select_folder(options).try { |path| Path[path] } }
    end

    # Shows an informational, warning, or error message.
    def message(title : String, message : String, kind = MessageKind::Info) : Nil
      Runtime.dispatch_sync { Platform::Dialogs.message(title, message, kind) }
    end

    # Shows an OK/Cancel question and returns `true` when OK is chosen.
    def confirm(title : String, message : String) : Bool
      Runtime.dispatch_sync { Platform::Dialogs.confirm(title, message) }
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::Dialogs, NativeDesktop::CapabilityState::Supported)
