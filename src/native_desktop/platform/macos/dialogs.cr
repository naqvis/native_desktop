{% if flag?(:darwin) %}
  require "./objc"

  @[Link(ldflags: "#{__DIR__}/dialogs.m -framework AppKit -framework Foundation")]
  lib LibNativeDesktopDialogs
    fun run_panel = native_desktop_run_panel(panel : Void*, owner : Void*) : Int64
  end

  module NativeDesktop::Platform::Dialogs
    extend self
    MODAL_OK = 1_i64

    private def ensure_application : Nil
      MacOS::ObjC.msg(MacOS::ObjC.klass("NSApplication"), "sharedApplication")
    end

    private def configure(panel : Void*, title : String?, directory : Path?, filters : Array(FileFilter)) : Nil
      MacOS::ObjC.msg(panel, "setTitle:", MacOS::ObjC.string(title)) if title
      if directory
        url = MacOS::ObjC.msg(MacOS::ObjC.klass("NSURL"), "fileURLWithPath:", MacOS::ObjC.string(directory.to_s))
        MacOS::ObjC.msg(panel, "setDirectoryURL:", url)
      end
      return if filters.empty?
      array = MacOS::ObjC.msg(MacOS::ObjC.klass("NSMutableArray"), "array")
      filters.each do |filter|
        filter.extensions.each { |extension| MacOS::ObjC.msg(array, "addObject:", MacOS::ObjC.string(extension.lstrip('.'))) }
      end
      MacOS::ObjC.msg(panel, "setAllowedFileTypes:", array)
    end

    private def configure_common(panel : Void*, accept_label : String?, show_hidden : Bool, can_create_directories : Bool = true) : Nil
      MacOS::ObjC.msg(panel, "setPrompt:", MacOS::ObjC.string(accept_label)) if accept_label
      MacOS::ObjC.msg_long(panel, "setShowsHiddenFiles:", show_hidden ? 1_i64 : 0_i64)
      MacOS::ObjC.msg_long(panel, "setCanCreateDirectories:", can_create_directories ? 1_i64 : 0_i64)
    end

    private def path(panel : Void*) : String?
      url = MacOS::ObjC.msg(panel, "URL")
      url.null? ? nil : MacOS::ObjC.to_s(MacOS::ObjC.msg(url, "path"))
    end

    private def run(panel : Void*, owner : Void*?) : Int64
      LibNativeDesktopDialogs.run_panel(panel, owner || Pointer(Void).null)
    end

    def open_file(options : OpenDialogOptions) : String?
      MacOS::ObjC.pool do
        ensure_application
        panel = MacOS::ObjC.msg(MacOS::ObjC.klass("NSOpenPanel"), "openPanel")
        MacOS::ObjC.msg_long(panel, "setCanChooseFiles:", 1)
        MacOS::ObjC.msg_long(panel, "setCanChooseDirectories:", 0)
        MacOS::ObjC.msg_long(panel, "setAllowsMultipleSelection:", 0)
        configure(panel, options.title, options.directory, options.filters)
        configure_common(panel, options.accept_label, options.show_hidden)
        run(panel, options.owner) == MODAL_OK ? path(panel) : nil
      end
    end

    def open_files(options : OpenDialogOptions) : Array(String)
      MacOS::ObjC.pool do
        ensure_application
        panel = MacOS::ObjC.msg(MacOS::ObjC.klass("NSOpenPanel"), "openPanel")
        MacOS::ObjC.msg_long(panel, "setCanChooseFiles:", 1)
        MacOS::ObjC.msg_long(panel, "setCanChooseDirectories:", 0)
        MacOS::ObjC.msg_long(panel, "setAllowsMultipleSelection:", 1)
        configure(panel, options.title, options.directory, options.filters)
        configure_common(panel, options.accept_label, options.show_hidden)
        next [] of String unless run(panel, options.owner) == MODAL_OK
        urls = MacOS::ObjC.msg(panel, "URLs")
        Array(String).new(MacOS::ObjC.long(urls, "count").to_i) do |index|
          url = MacOS::ObjC.msg_index(urls, "objectAtIndex:", index.to_u64)
          MacOS::ObjC.to_s(MacOS::ObjC.msg(url, "path")) || ""
        end.reject(&.empty?)
      end
    end

    def save_file(options : SaveDialogOptions) : String?
      MacOS::ObjC.pool do
        ensure_application
        panel = MacOS::ObjC.msg(MacOS::ObjC.klass("NSSavePanel"), "savePanel")
        configure(panel, options.title, options.directory, options.filters)
        configure_common(panel, options.accept_label, options.show_hidden, options.can_create_directories)
        if extension = options.default_extension
          MacOS::ObjC.msg(panel, "setAllowedFileTypes:", MacOS::ObjC.msg(MacOS::ObjC.klass("NSArray"), "arrayWithObject:", MacOS::ObjC.string(extension.lstrip('.'))))
        end
        if suggested_name = options.suggested_name
          MacOS::ObjC.msg(panel, "setNameFieldStringValue:", MacOS::ObjC.string(suggested_name))
        end
        run(panel, options.owner) == MODAL_OK ? path(panel) : nil
      end
    end

    def select_folder(options : FolderDialogOptions) : String?
      MacOS::ObjC.pool do
        ensure_application
        panel = MacOS::ObjC.msg(MacOS::ObjC.klass("NSOpenPanel"), "openPanel")
        MacOS::ObjC.msg_long(panel, "setCanChooseFiles:", 0)
        MacOS::ObjC.msg_long(panel, "setCanChooseDirectories:", 1)
        MacOS::ObjC.msg_long(panel, "setAllowsMultipleSelection:", 0)
        configure(panel, options.title, options.directory, [] of FileFilter)
        configure_common(panel, options.accept_label, options.show_hidden, options.can_create_directories)
        run(panel, options.owner) == MODAL_OK ? path(panel) : nil
      end
    end

    def message(title : String, message : String, kind : MessageKind) : Nil
      alert(title, message, kind, false)
    end

    def confirm(title : String, message : String) : Bool
      alert(title, message, MessageKind::Info, true)
    end

    private def alert(title : String, message : String, kind : MessageKind, confirmation : Bool) : Bool
      MacOS::ObjC.pool do
        ensure_application
        panel = MacOS::ObjC.msg(MacOS::ObjC.msg(MacOS::ObjC.klass("NSAlert"), "alloc"), "init")
        MacOS::ObjC.msg(panel, "setMessageText:", MacOS::ObjC.string(title))
        MacOS::ObjC.msg(panel, "setInformativeText:", MacOS::ObjC.string(message))
        style = kind.warning? ? 0_i64 : kind.error? ? 2_i64 : 1_i64
        MacOS::ObjC.msg_long(panel, "setAlertStyle:", style)
        MacOS::ObjC.msg(panel, "addButtonWithTitle:", MacOS::ObjC.string("OK"))
        MacOS::ObjC.msg(panel, "addButtonWithTitle:", MacOS::ObjC.string("Cancel")) if confirmation
        response = MacOS::ObjC.long(panel, "runModal")
        !confirmation || response == 1000
      end
    end
  end
{% end %}
