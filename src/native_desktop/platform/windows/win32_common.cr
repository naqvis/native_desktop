# Shared Win32 API bindings for all Windows platform modules.
# Centralizes common Windows API declarations to avoid "fun redefinition" errors.
#
# All Windows platform files should require this file instead of declaring
# their own lib blocks for these common APIs.

module NativeDesktop::Platform::Windows
  alias MonitorCallback = (Void*, Void*, LibUser32::Rect*, Int64 -> Int32)

  # ── Menu flag constants (shared) ─────────────────────────────────────────
  MFM_STRING    = 0x00000000_u32
  MFM_GRAYED    = 0x00000001_u32
  MFM_CHECKED   = 0x00000008_u32
  MFM_POPUP     = 0x00000010_u32
  MFM_SEPARATOR = 0x00000800_u32

  # ── TrackPopupMenu flags (shared) ────────────────────────────────────────
  TPM_RETURNCMD = 0x00000100_u32

  # ── User32 - Window and UI functions ──────────────────────────────────

  @[Link("user32")]
  lib LibUser32
    struct Point
      x : Int32
      y : Int32
    end

    struct Rect
      left : Int32
      top : Int32
      right : Int32
      bottom : Int32
    end

    struct WindowPlacement
      length : UInt32
      flags : UInt32
      show_command : UInt32
      minimum_position : Point
      maximum_position : Point
      normal_position : Rect
    end

    struct MonitorInfo
      size : UInt32
      monitor : Rect
      work : Rect
      flags : UInt32
    end

    struct LastInputInfo
      cb_size : UInt32
      tick : UInt32
    end

    fun MessageBoxW(hwnd : Void*, lp_text : UInt16*, lp_caption : UInt16*, u_type : UInt32) : Int32
    fun CreatePopupMenu : Void*
    fun CreateMenu : Void*
    fun AppendMenuW(h_menu : Void*, u_flags : UInt32, u_id_new_item : UInt64, lp_new_item : UInt16*) : Int32
    fun AppendMenuA(h_menu : Void*, u_flags : UInt32, u_id_new_item : UInt64, lp_new_item : UInt8*) : Int32
    fun TrackPopupMenu(h_menu : Void*, u_flags : UInt32, x : Int32, y : Int32, n_reserved : Int32, h_wnd : Void*, prc_rect : Void*) : Int32
    fun DestroyMenu(h_menu : Void*) : Int32
    fun SetMenu(h_wnd : Void*, h_menu : Void*) : Int32
    fun DrawMenuBar(h_wnd : Void*) : Int32
    fun GetWindowLongPtrW(h_wnd : Void*, n_index : Int32) : Int64
    fun SetWindowLongPtrW(h_wnd : Void*, n_index : Int32, dw_new_long : Int64) : Int64
    fun CallWindowProcW(lp_prev_wnd_func : Int64, h_wnd : Void*, msg : UInt32, w_param : UInt64, l_param : Int64) : Int64
    fun CreateAcceleratorTableW(p_accel : Void*, count : Int32) : Void*
    fun DestroyAcceleratorTable(h_accel : Void*) : Int32
    fun SetForegroundWindow(h_wnd : Void*) : Int32
    fun GetForegroundWindow : Void*
    fun GetCursorPos(lp_point : Point*) : Int32
    fun PostMessageW(h_wnd : Void*, msg : UInt32, w_param : UInt64, l_param : Int64) : Int32
    fun DefWindowProcW(h_wnd : Void*, msg : UInt32, w_param : UInt64, l_param : Int64) : Int64
    fun RegisterClassExW(lp_wnd_class : Void*) : UInt16
    fun CreateWindowExW(dw_ex_style : UInt32, lp_class_name : UInt16*, lp_window_name : UInt16*, dw_style : UInt32, x : Int32, y : Int32, n_width : Int32, n_height : Int32, h_wnd_parent : Void*, h_menu : Void*, h_instance : Void*, lp_param : Void*) : Void*
    fun CreateWindowExA(dw_ex_style : UInt32, lp_class_name : UInt8*, lp_window_name : UInt8*, dw_style : UInt32, x : Int32, y : Int32, n_width : Int32, n_height : Int32, h_wnd_parent : Void*, h_menu : Void*, h_instance : Void*, lp_param : Void*) : Void*
    fun DestroyWindow(h_wnd : Void*) : Int32
    fun GetMessageW(lp_msg : Void*, h_wnd : Void*, w_msg_filter_min : UInt32, w_msg_filter_max : UInt32) : Int32
    fun TranslateMessage(lp_msg : Void*) : Int32
    fun DispatchMessageW(lp_msg : Void*) : Int32
    fun PeekMessageW(lp_msg : Void*, h_wnd : Void*, w_msg_filter_min : UInt32, w_msg_filter_max : UInt32, w_remove_msg : UInt32) : Int32
    fun TranslateAcceleratorW(h_wnd : Void*, h_accel : Void*, lp_msg : Void*) : Int32
    fun OpenClipboard(h_wnd_new_owner : Void*) : Int32
    fun CloseClipboard : Int32
    fun EmptyClipboard : Int32
    fun GetClipboardData(u_format : UInt32) : Void*
    fun SetClipboardData(u_format : UInt32, h_mem : Void*) : Void*
    fun IsClipboardFormatAvailable(format : UInt32) : Int32
    fun RegisterClipboardFormatW(lpsz_format : UInt16*) : UInt32
    fun EnumClipboardFormats(format : UInt32) : UInt32
    fun GetClipboardSequenceNumber : UInt32
    fun GetWindowTextLengthW(h_wnd : Void*) : Int32
    fun GetWindowTextW(h_wnd : Void*, lp_string : UInt16*, n_max_count : Int32) : Int32
    fun GetWindowModuleFileNameW(h_wnd : Void*, lp_filename : UInt16*, n_size : UInt32) : UInt32
    fun GetWindowPlacement(window : Void*, placement : WindowPlacement*) : Int32
    fun SetWindowPlacement(window : Void*, placement : WindowPlacement*) : Int32
    fun MonitorFromWindow(window : Void*, flags : UInt32) : Void*
    fun GetMonitorInfoW(monitor : Void*, info : MonitorInfo*) : Int32
    fun SetWindowPos(hWnd : Void*, hWndInsertAfter : Void*, x : Int32, y : Int32, cx : Int32, cy : Int32, uFlags : UInt32) : Int32
    fun EnumDisplayMonitors(hdc : Void*, clip : Rect*, callback : MonitorCallback, data : Int64) : Int32
    fun RegisterHotKey(window : Void*, id : Int32, modifiers : UInt32, key : UInt32) : Int32
    fun UnregisterHotKey(window : Void*, id : Int32) : Int32
    fun SetTimer(window : Void*, id : UInt64, interval : UInt32, callback : Void*) : UInt64
    fun KillTimer(window : Void*, id : UInt64) : Int32
    fun GetLastInputInfo(info : LastInputInfo*) : Int32
    fun SendMessageA(hWnd : Void*, msg : UInt32, wParam : UInt64, lParam : Void*) : UInt64
    fun SendMessageW(hWnd : Void*, msg : UInt32, wParam : UInt64, lParam : Void*) : UInt64
    fun ShowWindow(hWnd : Void*, nCmdShow : Int32) : Int32
    fun SetParent(hWndChild : Void*, hWndNewParent : Void*) : Void*
    fun GetWindowRect(hWnd : Void*, lpRect : Rect*) : Int32
    fun MoveWindow(hWnd : Void*, x : Int32, y : Int32, nWidth : Int32, nHeight : Int32, bRepaint : Int32) : Int32
    fun GetClientRect(hWnd : Void*, lpRect : Rect*) : Int32
    fun LoadImageA(hInst : Void*, name : UInt8*, type : UInt32, cx : Int32, cy : Int32, fuLoad : UInt32) : Void*
    fun LoadIconA(hInst : Void*, lpIconName : UInt8*) : Void*
    fun LoadIconW(hInst : Void*, name : UInt16*) : Void*
    fun FindWindowExW(hWndParent : Void*, hWndChildAfter : Void*, lpszClass : UInt16*, lpszWindow : UInt16*) : Void*
    fun EnableWindow(hWnd : Void*, enable : Int32) : Int32
    fun IsWindow(hWnd : Void*) : Int32
    fun DestroyIcon(hIcon : Void*) : Int32
    fun GetMessagePos : UInt32
    fun SetLayeredWindowAttributes(hWnd : Void*, crKey : UInt32, bAlpha : UInt8, dwFlags : UInt32) : Int32
    fun ScreenToClient(hWnd : Void*, lpPoint : Point*) : Int32
    fun MsgWaitForMultipleObjects(count : UInt32, handles : Void*, wait_all : Int32, milliseconds : UInt32, wake_mask : UInt32) : UInt32
  end

  # ── Kernel32 - System functions ───────────────────────────────────────

  @[Link("kernel32")]
  lib LibKernel32
    GMEM_MOVEABLE = 0x0002_u32

    struct SystemPowerStatus
      ac_line_status : UInt8
      battery_flag : UInt8
      battery_life_percent : UInt8
      system_status_flag : UInt8
      battery_life_time : UInt32
      battery_full_life_time : UInt32
    end

    struct FileTime
      low : UInt32
      high : UInt32
    end

    fun GetCurrentProcess : Void*
    fun GetModuleHandleW(lp_module_name : UInt16*) : Void*
    fun GetModuleHandleA(name : UInt8*) : Void*
    fun GetProcAddress(module : Void*, name : UInt8*) : Void*
    fun CloseHandle(handle : Void*) : Int32
    fun GlobalAlloc(u_flags : UInt32, dw_bytes : UInt64) : Void*
    fun GlobalLock(h_mem : Void*) : Void*
    fun GlobalUnlock(h_mem : Void*) : Int32
    fun GlobalSize(h_mem : Void*) : UInt64
    fun GlobalFree(h_mem : Void*) : Void*
    fun RtlMoveMemory(dest : Void*, src : Void*, length : UInt64) : Nil
    fun GetTickCount : UInt32
    fun GetLastError : UInt32
    fun GetSystemPowerStatus(status : SystemPowerStatus*) : Int32
    fun GetSystemTimes(idle : FileTime*, kernel : FileTime*, user : FileTime*) : Int32
    fun LCIDToLocaleName(locale : UInt32, name : UInt16*, count : Int32, flags : UInt32) : Int32
    fun LocaleNameToLCID(name : UInt16*, flags : UInt32) : UInt32
    fun CreateMutexW(attributes : Void*, initial_owner : Int32, name : UInt16*) : Void*
    fun OpenProcess(access : UInt32, inherit : Int32, process_id : UInt32) : Void*
    fun GetExitCodeProcess(process : Void*, code : UInt32*) : Int32
  end

  # ── Shell32 - Shell functions ──────────────────────────────────────────

  @[Link("shell32")]
  lib LibShell32
    fun Shell_NotifyIconW(dw_message : UInt32, lp_data : Void*) : Int32
    fun SHBrowseForFolderW(lpbi : BrowseInfoW*) : Void*
    fun SHGetPathFromIDListW(pidl : Void*, psz_path : UInt16*) : Int32
    fun CoTaskMemFree(pv : Void*) : Nil
    fun ShellExecuteW(window : Void*, operation : UInt16*, file : UInt16*, parameters : UInt16*, directory : UInt16*, show : Int32) : Void*
    fun SHChangeNotify(event_id : Int32, flags : UInt32, item1 : Void*, item2 : Void*) : Nil

    struct BrowseInfoW
      hwnd_owner : Void*
      pidl_root : Void*
      psz_display_name : UInt16*
      lpsz_title : UInt16*
      ul_flags : UInt32
      lpfn : Void*
      l_param : Void*
      i_image : Int32
    end
  end

  # ── OLE32 - COM functions ──────────────────────────────────────────────

  @[Link("ole32")]
  lib LibOLE
    CLSCTX_INPROC_SERVER = 0x1_u32
    S_OK                 =   0_i32

    fun CoInitializeEx(pv_reserved : Void*, dw_co_init : UInt32) : Int32
    fun CoUninitialize : Nil
    fun CoCreateInstance(rclsid : Void*, p_unk_outer : Void*, dw_cls_context : UInt32, riid : Void*, ppv : Void**) : Int32
    fun CreateStreamOnHGlobal(hGlobal : Void*, fDeleteOnRelease : Int32, ppstm : Pointer(Void*)) : Int32
    fun CoTaskMemAlloc(cb : UInt64) : Void*
    fun CoTaskMemFree(pv : Void*) : Void
    fun CLSIDFromString(value : UInt16*, clsid : Void*) : Int32
  end

  # ── GDI32 - Graphics functions ─────────────────────────────────────────

  @[Link("gdi32")]
  lib LibGDI32
    fun LoadImageW(h_inst : Void*, name : UInt16*, type : UInt32, cx : Int32, cy : Int32, fu_load : UInt32) : Void*
    fun DestroyIcon(hicon : Void*) : Int32
    fun LoadIconW(h_inst : Void*, name : UInt16*) : Void*
    fun CreateCompatibleDC(hdc : Void*) : Void*
    fun CreateCompatibleBitmap(hdc : Void*, w : Int32, h : Int32) : Void*
    fun CreateSolidBrush(color : UInt32) : Void*
    fun SelectObject(hdc : Void*, h : Void*) : Void*
    fun DeleteObject(h : Void*) : Int32
    fun DeleteDC(hdc : Void*) : Int32
    fun PatBlt(hdc : Void*, x : Int32, y : Int32, w : Int32, h : Int32, rop : UInt32) : Int32
  end

  # ── GDI+ - Advanced graphics ───────────────────────────────────────────

  @[Link("gdiplus")]
  lib LibGdiplus
    fun GdiplusStartup(token : UInt64*, input : Void*, output : Void*) : Int32
    fun GdipCreateBitmapFromFile(filename : UInt16*, bitmap : Void**) : Int32
    fun GdipCreateBitmapFromStream(stream : Void*, bitmap : Void**) : Int32
    fun GdipCreateHICONFromBitmap(bitmap : Void*, hicon : Void**) : Int32
    fun GdipDisposeImage(image : Void*) : Int32
  end

  # ── ComDlg32 - Common dialogs ──────────────────────────────────────────

  @[Link("comdlg32")]
  lib LibComDlg
    struct OpenFileName
      l_struct_size : UInt32
      hwnd_owner : Void*
      h_instance : Void*
      lp_str_filter : UInt16*
      lp_str_cust_filter : UInt16*
      n_max_cust_filter : UInt32
      n_filter_index : UInt32
      lp_str_file : UInt16*
      n_max_file : UInt32
      lp_str_file_title : UInt16*
      n_max_file_title : UInt32
      lp_str_initial_dir : UInt16*
      lp_str_title : UInt16*
      flags : UInt32
      n_file_offset : UInt16
      n_file_ext_offset : UInt16
      lp_str_def_ext : UInt16*
      l_cust_data : Int64
      lpfn_hook : Void*
      lp_template_name : UInt16*
      pv_reserved : Void*
      dw_reserved : UInt32
      flags_ex : UInt32
    end

    fun GetOpenFileNameW(lpofn : OpenFileName*) : Int32
    fun GetSaveFileNameW(lpofn : OpenFileName*) : Int32

    struct CHOOSECOLORA
      l_struct_size : UInt32
      hwnd_owner : Void*
      h_instance : Void*
      rgb_result : UInt32
      lp_cust_colors : Void*
      flags : UInt32
      l_cust_data : Int64
      lpfn_hook : Void*
      lp_template_name : UInt8*
    end

    fun ChooseColorA(cc : CHOOSECOLORA*) : Int32
  end

  # ── AdvApi32 - Registry and security functions ───────────────────────

  @[Link("advapi32")]
  lib LibAdvApi32
    fun RegCreateKeyExW(root : Void*, path : UInt16*, reserved : UInt32, klass : UInt16*, options : UInt32, access : UInt32, attributes : Void*, key : Void**, disposition : UInt32*) : UInt32
    fun RegSetValueExW(key : Void*, name : UInt16*, reserved : UInt32, type : UInt32, data : UInt8*, size : UInt32) : UInt32
    fun RegDeleteValueW(key : Void*, name : UInt16*) : UInt32
    fun RegDeleteTreeW(root : Void*, path : UInt16*) : UInt32
    fun RegGetValueW(key : Void*, sub_key : UInt16*, value : UInt16*, flags : UInt32, type : UInt32*, data : Void*, size : UInt32*) : Int32
    fun RegEnumValueW(key : Void*, index : UInt32, value_name : UInt16*, value_name_size : UInt32*, reserved : Void*, type : UInt32*, data : UInt8*, data_size : UInt32*) : UInt32
    fun OpenProcessToken(process : Void*, access : UInt32, token : Void**) : Int32
    fun GetTokenInformation(token : Void*, type : UInt32, data : Void*, size : UInt32, returned : UInt32*) : Int32
    fun GetLengthSid(sid : Void*) : UInt32
    fun CopySid(size : UInt32, destination : Void*, source : Void*) : Int32
  end

  # ── Shlwapi - Shell utility functions ─────────────────────────────────

  @[Link("shlwapi")]
  lib LibShlwapi
    fun SHCreateMemStream(p_init : UInt8*, cb_init : UInt32) : Void*
  end

  # ── Shcore - DPI functions ────────────────────────────────────────────

  @[Link("shcore")]
  lib LibShcore
    fun GetDpiForMonitor(monitor : Void*, type : UInt32, x : UInt32*, y : UInt32*) : Int32
  end
end
