{% if flag?(:linux) %}
  module NativeDesktop::Platform::Dialogs
    extend self

    @[Link("gtk-3", pkg_config: "gtk+-3.0")]
    lib LibGTKDialogs
      fun gtk_file_chooser_dialog_new(title : UInt8*, parent : Void*, action : Int32, first_button : UInt8*, ...) : Void*
      fun gtk_dialog_run(dialog : Void*) : Int32
      fun gtk_widget_destroy(widget : Void*) : Nil
      fun gtk_file_chooser_get_filename(chooser : Void*) : UInt8*
      fun gtk_file_chooser_get_filenames(chooser : Void*) : Void*
      fun gtk_file_chooser_set_select_multiple(chooser : Void*, multiple : Int32) : Nil
      fun gtk_file_chooser_set_current_folder(chooser : Void*, folder : UInt8*) : Int32
      fun gtk_file_chooser_set_current_name(chooser : Void*, name : UInt8*) : Nil
      fun gtk_file_chooser_set_do_overwrite_confirmation(chooser : Void*, enabled : Int32) : Nil
      fun gtk_file_chooser_set_show_hidden(chooser : Void*, show_hidden : Int32) : Nil
      fun gtk_file_chooser_set_create_folders(chooser : Void*, create_folders : Int32) : Nil
      fun gtk_file_filter_new : Void*
      fun gtk_file_filter_set_name(filter : Void*, name : UInt8*) : Nil
      fun gtk_file_filter_add_pattern(filter : Void*, pattern : UInt8*) : Nil
      fun gtk_file_chooser_add_filter(chooser : Void*, filter : Void*) : Nil
      fun gtk_message_dialog_new(parent : Void*, flags : Int32, type : Int32, buttons : Int32, format : UInt8*, ...) : Void*
      fun gtk_window_set_title(window : Void*, title : UInt8*) : Nil
    end

    @[Link("glib-2.0")]
    lib LibGLibDialogs
      fun g_free(data : Void*) : Nil
      fun g_slist_length(list : Void*) : UInt32
      fun g_slist_nth_data(list : Void*, index : UInt32) : Void*
      fun g_slist_free_full(list : Void*, free_func : Void*) : Nil
    end

    ACCEPT = -3
    CANCEL = -6

    private def chooser(title : String, action : Int32, accept : String, owner : Void*) : Void*
      LibGTKDialogs.gtk_file_chooser_dialog_new(title, owner, action, "_Cancel", CANCEL, accept, ACCEPT, nil)
    end

    private def configure(dialog : Void*, directory : Path?, filters : Array(FileFilter)) : Nil
      LibGTKDialogs.gtk_file_chooser_set_current_folder(dialog, directory.to_s) if directory
      filters.each do |entry|
        filter = LibGTKDialogs.gtk_file_filter_new
        LibGTKDialogs.gtk_file_filter_set_name(filter, entry.name)
        entry.extensions.each { |extension| LibGTKDialogs.gtk_file_filter_add_pattern(filter, "*.#{extension.lstrip('.')}") }
        LibGTKDialogs.gtk_file_chooser_add_filter(dialog, filter)
      end
    end

    private def selected(dialog : Void*) : String?
      pointer = LibGTKDialogs.gtk_file_chooser_get_filename(dialog)
      return nil if pointer.null?
      String.new(pointer).tap { LibGLibDialogs.g_free(pointer.as(Void*)) }
    end

    private def run(dialog : Void*, &block : -> T) : T forall T
      begin
        block.call
      ensure
        LibGTKDialogs.gtk_widget_destroy(dialog)
      end
    end

    def open_file(options : OpenDialogOptions) : String?
      dialog = chooser(options.title || "Open File", 0, options.accept_label || "_Open", options.owner || Pointer(Void).null)
      LibGTKDialogs.gtk_file_chooser_set_show_hidden(dialog, options.show_hidden ? 1 : 0)
      configure(dialog, options.directory, options.filters)
      run(dialog) { LibGTKDialogs.gtk_dialog_run(dialog) == ACCEPT ? selected(dialog) : nil }
    end

    def open_files(options : OpenDialogOptions) : Array(String)
      dialog = chooser(options.title || "Open Files", 0, options.accept_label || "_Open", options.owner || Pointer(Void).null)
      LibGTKDialogs.gtk_file_chooser_set_select_multiple(dialog, 1)
      LibGTKDialogs.gtk_file_chooser_set_show_hidden(dialog, options.show_hidden ? 1 : 0)
      configure(dialog, options.directory, options.filters)
      run(dialog) do
        next [] of String unless LibGTKDialogs.gtk_dialog_run(dialog) == ACCEPT
        list = LibGTKDialogs.gtk_file_chooser_get_filenames(dialog)
        next [] of String if list.null?
        begin
          Array(String).new(LibGLibDialogs.g_slist_length(list).to_i) do |index|
            String.new(LibGLibDialogs.g_slist_nth_data(list, index.to_u32).as(UInt8*))
          end
        ensure
          LibGLibDialogs.g_slist_free_full(list, (->LibGLibDialogs.g_free(Pointer(Void))).pointer)
        end
      end
    end

    def save_file(options : SaveDialogOptions) : String?
      dialog = chooser(options.title || "Save File", 1, options.accept_label || "_Save", options.owner || Pointer(Void).null)
      LibGTKDialogs.gtk_file_chooser_set_do_overwrite_confirmation(dialog, options.confirm_overwrite ? 1 : 0)
      LibGTKDialogs.gtk_file_chooser_set_show_hidden(dialog, options.show_hidden ? 1 : 0)
      LibGTKDialogs.gtk_file_chooser_set_create_folders(dialog, options.can_create_directories ? 1 : 0)
      configure(dialog, options.directory, options.filters)
      if suggested_name = options.suggested_name
        LibGTKDialogs.gtk_file_chooser_set_current_name(dialog, suggested_name)
      end
      run(dialog) { LibGTKDialogs.gtk_dialog_run(dialog) == ACCEPT ? selected(dialog) : nil }
    end

    def select_folder(options : FolderDialogOptions) : String?
      dialog = chooser(options.title || "Select Folder", 2, options.accept_label || "_Open", options.owner || Pointer(Void).null)
      LibGTKDialogs.gtk_file_chooser_set_show_hidden(dialog, options.show_hidden ? 1 : 0)
      LibGTKDialogs.gtk_file_chooser_set_create_folders(dialog, options.can_create_directories ? 1 : 0)
      configure(dialog, options.directory, [] of FileFilter)
      run(dialog) { LibGTKDialogs.gtk_dialog_run(dialog) == ACCEPT ? selected(dialog) : nil }
    end

    def message(title : String, message : String, kind : MessageKind) : Nil
      type = kind.warning? ? 1 : kind.error? ? 3 : 0
      dialog = LibGTKDialogs.gtk_message_dialog_new(nil, 0, type, 1, "%s", message)
      LibGTKDialogs.gtk_window_set_title(dialog, title)
      run(dialog) { LibGTKDialogs.gtk_dialog_run(dialog); nil }
    end

    def confirm(title : String, message : String) : Bool
      dialog = LibGTKDialogs.gtk_message_dialog_new(nil, 0, 2, 3, "%s", message)
      LibGTKDialogs.gtk_window_set_title(dialog, title)
      run(dialog) { LibGTKDialogs.gtk_dialog_run(dialog) == -5 }
    end
  end
{% end %}
