require "./win32_common"
require "./string_helpers"

{% if flag?(:windows) %}
  @[Link("user32")]
  lib LibNativeDesktopDialogUser32
    fun GetParent(window : Void*) : Void*
    fun SetDlgItemTextW(dialog : Void*, item : Int32, text : UInt16*) : Int32
  end

  module NativeDesktop::Platform::Dialogs
    extend self
    MAX_BUFFER            =          32768
    WM_INITDIALOG         =     0x0110_u32
    IDOK                  =          1_i32
    OFN_ENABLEHOOK        = 0x00000020_u32
    BFFM_INITIALIZED      =          1_u32
    BFFM_SETSELECTIONW    =     0x0467_u32
    BFFM_SETOKTEXT        =     0x0469_u32
    BIF_RETURNONLYFSDIRS  =     0x0001_u32
    BIF_NEWDIALOGSTYLE    =     0x0040_u32
    BIF_NONEWFOLDERBUTTON =     0x0200_u32

    FILE_DIALOG_HOOK = ->(dialog : Void*, message : UInt32, _wparam : UInt64, parameter : Int64) : UInt64 {
      if message == WM_INITDIALOG && parameter != 0
        options = Pointer(Windows::LibComDlg::OpenFileName).new(parameter.to_u64)
        label = Pointer(UInt16).new(options.value.l_cust_data.to_u64)
        unless label.null?
          parent = LibNativeDesktopDialogUser32.GetParent(dialog)
          LibNativeDesktopDialogUser32.SetDlgItemTextW(parent, IDOK, label) unless parent.null?
        end
      end
      0_u64
    }

    class FolderDialogContext
      getter directory : Array(UInt16)?
      getter accept_label : Array(UInt16)?

      def initialize(directory : String?, accept_label : String?)
        @directory = directory.try { |value| Windows::StringHelpers.to_utf16(value) }
        @accept_label = accept_label.try { |value| Windows::StringHelpers.to_utf16(value) }
      end
    end

    FOLDER_DIALOG_CALLBACK = ->(dialog : Void*, message : UInt32, _parameter : Int64, data : Int64) : Int32 {
      if message == BFFM_INITIALIZED && data != 0
        context = Box(FolderDialogContext).unbox(Pointer(Void).new(data.to_u64))
        if directory = context.directory
          Windows::LibUser32.SendMessageW(
            dialog, BFFM_SETSELECTIONW, 1_u64, directory.to_unsafe.as(Void*)
          )
        end
        if label = context.accept_label
          Windows::LibUser32.SendMessageW(
            dialog, BFFM_SETOKTEXT, 0_u64, label.to_unsafe.as(Void*)
          )
        end
      end
      0_i32
    }

    private def wide(value : String?) : Slice(UInt16)?
      return nil unless value
      units = value.to_utf16
      Slice(UInt16).new(units.size + 1, 0_u16).tap { |buffer| units.each_with_index { |unit, index| buffer[index] = unit } }
    end

    private def string(pointer : UInt16*) : String
      String.from_utf16(pointer)[0]
    end

    private def filter_buffer(filters : Array(FileFilter)) : Slice(UInt16)?
      return nil if filters.empty?
      value = filters.flat_map { |entry| [entry.name, entry.extensions.map { |extension| "*.#{extension.lstrip('.')}" }.join(';')] }.join('\0') + "\0\0"
      units = value.to_utf16
      Slice.new(units.to_unsafe, units.size).dup
    end

    private def file_options(title : String?, directory : Path?, filters : Array(FileFilter), buffer : Slice(UInt16), flags : UInt32, owner : Void*? = nil, default_extension : String? = nil, accept_label : String? = nil) : {Windows::LibComDlg::OpenFileName, Slice(UInt16)?, Slice(UInt16)?, Slice(UInt16)?, Slice(UInt16)?, Slice(UInt16)?}
      title_wide = wide(title)
      directory_wide = wide(directory.try(&.to_s))
      filter_wide = filter_buffer(filters)
      extension_wide = wide(default_extension.try(&.lstrip('.')))
      accept_wide = wide(accept_label)
      options = Windows::LibComDlg::OpenFileName.new
      options.l_struct_size = sizeof(Windows::LibComDlg::OpenFileName).to_u32
      options.hwnd_owner = owner || Pointer(Void).null
      options.lp_str_file = buffer.to_unsafe
      options.n_max_file = buffer.size.to_u32
      options.lp_str_title = title_wide.try(&.to_unsafe) || Pointer(UInt16).null
      options.lp_str_initial_dir = directory_wide.try(&.to_unsafe) || Pointer(UInt16).null
      options.lp_str_filter = filter_wide.try(&.to_unsafe) || Pointer(UInt16).null
      options.lp_str_def_ext = extension_wide.try(&.to_unsafe) || Pointer(UInt16).null
      options.flags = flags
      if accept_wide
        options.flags |= OFN_ENABLEHOOK
        options.l_cust_data = accept_wide.to_unsafe.address.to_i64
        options.lpfn_hook = FILE_DIALOG_HOOK.pointer
      end
      {options, title_wide, directory_wide, filter_wide, extension_wide, accept_wide}
    end

    def open_file(options : OpenDialogOptions) : String?
      buffer = Slice(UInt16).new(MAX_BUFFER, 0_u16)
      flags = 0x00081808_u32 | (options.show_hidden ? 0x10000000_u32 : 0_u32)
      native, _title, _directory, _filters, _extension, _accept = file_options(options.title, options.directory, options.filters, buffer, flags, options.owner, accept_label: options.accept_label)
      Windows::LibComDlg.GetOpenFileNameW(pointerof(native)) == 0 ? nil : string(buffer.to_unsafe)
    end

    def open_files(options : OpenDialogOptions) : Array(String)
      buffer = Slice(UInt16).new(MAX_BUFFER, 0_u16)
      flags = 0x00081A08_u32 | (options.show_hidden ? 0x10000000_u32 : 0_u32)
      native, _title, _directory, _filters, _extension, _accept = file_options(options.title, options.directory, options.filters, buffer, flags, options.owner, accept_label: options.accept_label)
      return [] of String if Windows::LibComDlg.GetOpenFileNameW(pointerof(native)) == 0
      first = string(buffer.to_unsafe)
      index = first.to_utf16.size + 1
      return [first] if buffer[index] == 0
      files = [] of String
      while buffer[index] != 0
        name = string(buffer.to_unsafe + index)
        files << Path[first, name].to_s
        index += name.to_utf16.size + 1
      end
      files
    end

    def save_file(options : SaveDialogOptions) : String?
      buffer = Slice(UInt16).new(MAX_BUFFER, 0_u16)
      if name = options.suggested_name
        name.to_utf16.each_with_index { |unit, index| buffer[index] = unit }
      end
      flags = 0x00080008_u32
      flags |= 0x00000002_u32 if options.confirm_overwrite
      flags |= 0x10000000_u32 if options.show_hidden
      native, _title, _directory, _filters, _extension, _accept = file_options(options.title, options.directory, options.filters, buffer, flags, options.owner, options.default_extension, options.accept_label)
      Windows::LibComDlg.GetSaveFileNameW(pointerof(native)) == 0 ? nil : string(buffer.to_unsafe)
    end

    def select_folder(options : FolderDialogOptions) : String?
      display = Slice(UInt16).new(260, 0_u16)
      title = wide(options.title)
      context = FolderDialogContext.new(options.directory.try(&.to_s), options.accept_label)
      context_pointer = Box.box(context)
      info = Windows::LibShell32::BrowseInfoW.new
      info.hwnd_owner = options.owner || Pointer(Void).null
      info.pidl_root = Pointer(Void).null
      info.psz_display_name = display.to_unsafe
      info.lpsz_title = title.try(&.to_unsafe) || Pointer(UInt16).null
      info.ul_flags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE
      info.ul_flags |= BIF_NONEWFOLDERBUTTON unless options.can_create_directories
      info.lpfn = FOLDER_DIALOG_CALLBACK.pointer
      info.l_param = context_pointer
      info.i_image = 0
      list = Windows::LibShell32.SHBrowseForFolderW(pointerof(info))
      return nil if list.null?
      begin
        path = Slice(UInt16).new(MAX_BUFFER, 0_u16)
        Windows::LibShell32.SHGetPathFromIDListW(list, path.to_unsafe) == 0 ? nil : string(path.to_unsafe)
      ensure
        Windows::LibShell32.CoTaskMemFree(list)
      end
    end

    def message(title : String, message : String, kind : MessageKind) : Nil
      flags = kind.warning? ? 0x30_u32 : kind.error? ? 0x10_u32 : 0x40_u32
      Windows::LibUser32.MessageBoxW(nil, wide(message).not_nil!.to_unsafe, wide(title).not_nil!.to_unsafe, flags)
    end

    def confirm(title : String, message : String) : Bool
      Windows::LibUser32.MessageBoxW(nil, wide(message).not_nil!.to_unsafe, wide(title).not_nil!.to_unsafe, 0x21_u32) == 1
    end
  end
{% end %}
