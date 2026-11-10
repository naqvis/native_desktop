require "log"
require "./win32_common"
require "./string_helpers"
require "./icon_helpers"

module NativeDesktop
  module Platform
    module Windows
      module Tray
        extend self

        # ── Constants ────────────────────────────────────────────────────────────

        # NIM_ messages
        NIM_ADD    = 0x00000000_u32
        NIM_MODIFY = 0x00000001_u32
        NIM_DELETE = 0x00000002_u32

        # NIF_ flags
        NIF_MESSAGE = 0x00000001_u32
        NIF_ICON    = 0x00000002_u32
        NIF_TIP     = 0x00000004_u32
        NIF_STATE   = 0x00000008_u32

        # WM_ messages
        WM_APP      = 0x8000_u32
        TRAY_MSG_ID = WM_APP + 1
        WM_COMMAND  = 0x0111_u32

        # Mouse messages sent as lParam in tray callback
        WM_LBUTTONUP = 0x0202_u32
        WM_RBUTTONUP = 0x0205_u32

        # Menu flags
        MF_STRING       = 0x00000000_u32
        MF_GRAYED       = 0x00000001_u32
        MF_CHECKED      = 0x00000008_u32
        MF_POPUP        = 0x00000010_u32
        MF_SEPARATOR    = 0x00000800_u32
        TPM_BOTTOMALIGN =     0x0020_u32
        TPM_RIGHTALIGN  =     0x0008_u32
        # IMAGE_ type
        IMAGE_ICON      =          1_u32
        LR_LOADFROMFILE = 0x00000010_u32

        # ── State ────────────────────────────────────────────────────────────────

        @@hwnd : Void* = Pointer(Void).null
        @@hicon : Void* = Pointer(Void).null
        @@prev_hicon : Void* = Pointer(Void).null # Track previous icon for cleanup
        @@menu_items : Array(PlatformTrayMenuEntry) = [] of PlatformTrayMenuEntry
        @@item_callbacks : Hash(String, Proc(Nil)) = {} of String => Proc(Nil)
        @@click_callback : Proc(Int32, Nil)? = nil
        @@nid_buffer : Bytes = Bytes.new(1024, 0_u8) # NOTIFYICONDATA is ~952 bytes on Win64

        # ── Helpers ──────────────────────────────────────────────────────────────

        # Write NOTIFYICONDATA fields into the buffer.
        # Layout (64-bit): cbSize(4), hWnd(8), uID(4), uFlags(4), uCallbackMessage(4),
        #                  hIcon(8), szTip(256*2=512), dwState(4), dwStateMask(4),
        #                  szInfo(256*2), uVersion(4), szInfoTitle(64*2), dwInfoFlags(4)
        private def build_nid(hwnd : Void*, hicon : Void*, flags : UInt32, tip : String, msg_id : UInt32) : Nil
          buf = @@nid_buffer
          buf.fill(0_u8)

          # cbSize = 952 (NOTIFYICONDATAW size on Win64 with Vista+ fields)
          IO::ByteFormat::LittleEndian.encode(952_u32, buf[0, 4])
          # hWnd at offset 8 (pointer, 8 bytes)
          ptr_val = hwnd.address
          IO::ByteFormat::LittleEndian.encode(ptr_val, buf[8, 8])
          # uID at offset 16
          IO::ByteFormat::LittleEndian.encode(1_u32, buf[16, 4])
          # uFlags at offset 20
          IO::ByteFormat::LittleEndian.encode(flags, buf[20, 4])
          # uCallbackMessage at offset 24
          IO::ByteFormat::LittleEndian.encode(msg_id, buf[24, 4])
          # hIcon at offset 32 (pointer, 8 bytes)
          icon_val = hicon.address
          IO::ByteFormat::LittleEndian.encode(icon_val, buf[32, 8])
          # szTip at offset 40 — UTF-16LE, max 128 chars (256 bytes)
          tip_utf16 = tip.encode("UTF-16LE")
          copy_len = Math.min(tip_utf16.size, 254)
          tip_utf16[0, copy_len].copy_to(buf + 40)
        end

        # Load a PNG file via GDI+ and return an HICON.
        # Window procedure for the hidden tray notification window.
        # Correct Win64 signature: WPARAM=UInt64, LPARAM=Int64, LRESULT=Int64.
        def tray_window_proc(h_wnd : Void*, msg : UInt32, w_param : UInt64, l_param : Int64) : Int64
          if msg == TRAY_MSG_ID
            case l_param.to_u32!
            when WM_LBUTTONUP
              @@click_callback.try(&.call(0))
            when WM_RBUTTONUP
              @@click_callback.try(&.call(1))
              show_context_menu
            end
          end
          LibUser32.DefWindowProcW(h_wnd, msg, w_param, l_param)
        end

        # Create a hidden message-only window to receive tray notifications.
        private def create_message_window : Void*
          hinst = LibKernel32.GetModuleHandleW(Pointer(UInt16).null)

          StringHelpers.with_utf16_bytes("NativeDesktopTrayWindow") do |class_name_ptr|
            # WNDCLASSEXW: cbSize(4), style(4), lpfnWndProc(8), cbClsExtra(4),
            #              cbWndExtra(4), hInstance(8), hIcon(8), hCursor(8),
            #              hbrBackground(8), lpszMenuName(8), lpszClassName(8), hIconSm(8)
            wnd_class = Bytes.new(80, 0_u8)
            IO::ByteFormat::LittleEndian.encode(80_u32, wnd_class[0, 4])
            # lpfnWndProc at offset 8 — proper WNDPROC that handles TRAY_MSG_ID
            wndproc_addr = (->tray_window_proc(Void*, UInt32, UInt64, Int64)).pointer.address.to_u64
            IO::ByteFormat::LittleEndian.encode(wndproc_addr, wnd_class[8, 8])
            IO::ByteFormat::LittleEndian.encode(hinst.address, wnd_class[24, 8])
            IO::ByteFormat::LittleEndian.encode(class_name_ptr.address, wnd_class[64, 8])

            LibUser32.RegisterClassExW(wnd_class.to_unsafe)

            hwnd = LibUser32.CreateWindowExW(
              0_u32,
              class_name_ptr,
              Pointer(UInt16).null,
              0_u32,
              0, 0, 0, 0,
              Pointer(Void).new(-3_i64.to_u64!), # HWND_MESSAGE
              Pointer(Void).null,
              hinst,
              Pointer(Void).null
            )
            hwnd
          end
        end

        # Find the position of an item id in the flat @@menu_items array.
        private def find_flat_position(id : String) : Int32
          @@menu_items.each_with_index do |entry, idx|
            return idx if entry[:id] == id
          end
          0
        end

        # Recursively build a Win32 popup menu. Each item's command ID is
        # (flat_position + 1) so TrackPopupMenu return values map to flat items.
        private def build_win32_menu(parent_id : String, children_of : Hash(String, Array(PlatformTrayMenuEntry))) : Void*
          hmenu = LibUser32.CreatePopupMenu
          return hmenu if hmenu.null?

          children_of.fetch(parent_id, [] of PlatformTrayMenuEntry).each do |entry|
            if entry[:type] == 3
              LibUser32.AppendMenuW(hmenu, MF_SEPARATOR, 0_u64, Pointer(UInt16).null)
            elsif children_of.has_key?(entry[:id])
              # Item with submenu — create sub-popup
              submenu = build_win32_menu(entry[:id], children_of)
              unless submenu.null?
                label = entry[:label]
                if accel = entry[:accelerator]?
                  label = "#{label}\t#{accel}"
                end
                StringHelpers.with_utf16_bytes(label) do |label_ptr|
                  LibUser32.AppendMenuW(hmenu, MF_POPUP | (entry[:enabled] != 0 ? 0_u32 : MF_GRAYED), submenu.address, label_ptr)
                end
              end
            else
              flags = MF_STRING
              flags |= MF_GRAYED unless entry[:enabled] != 0
              flags |= MF_CHECKED if entry[:checked] != 0
              # Find flat position for command ID
              pos = find_flat_position(entry[:id])
              label = entry[:label]
              if accel = entry[:accelerator]?
                label = "#{label}\t#{accel}"
              end
              StringHelpers.with_utf16_bytes(label) do |label_ptr|
                LibUser32.AppendMenuW(hmenu, flags, (pos + 1).to_u64, label_ptr)
              end
            end
          end

          hmenu
        end

        # Show the context menu at the current cursor position.
        # Builds submenus recursively from flat items with parent_id.
        private def show_context_menu : Nil
          return if @@menu_items.empty?

          # Build parent → children mapping
          children_of = {} of String => Array(PlatformTrayMenuEntry)
          @@menu_items.each do |entry|
            children_of[entry[:parent_id]] ||= [] of PlatformTrayMenuEntry
            children_of[entry[:parent_id]] << entry
          end

          hmenu = build_win32_menu("", children_of)
          return if hmenu.null?

          point = LibUser32::Point.new
          LibUser32.GetCursorPos(pointerof(point))
          x = point.x
          y = point.y

          LibUser32.SetForegroundWindow(@@hwnd)
          cmd = LibUser32.TrackPopupMenu(
            hmenu,
            TPM_BOTTOMALIGN | TPM_RIGHTALIGN | TPM_RETURNCMD,
            x, y, 0, @@hwnd, Pointer(Void).null
          )

          LibUser32.DestroyMenu(hmenu)

          if cmd > 0
            idx = cmd - 1
            if idx < @@menu_items.size
              item_id = @@menu_items[idx][:id]
              @@item_callbacks[item_id]?.try(&.call)
            end
          end
        end

        # ── Public API ───────────────────────────────────────────────────────────

        # Create the tray icon.
        def create(app_id : String, icon : ::NativeDesktop::TrayIcon?, tooltip : String?) : Nil
          @@hwnd = create_message_window

          @@hicon = IconHelpers.hicon_from_source(icon)

          tip = tooltip || app_id
          flags = NIF_MESSAGE | NIF_TIP
          flags |= NIF_ICON unless @@hicon.null?

          build_nid(@@hwnd, @@hicon, flags, tip, TRAY_MSG_ID)

          result = LibShell32.Shell_NotifyIconW(NIM_ADD, @@nid_buffer.to_unsafe)
          if result == 0
            raise Error.new("Shell_NotifyIconW(NIM_ADD) failed", :tray_create_failed)
          end

          Log.debug { "Tray[Windows]: created tray icon for '#{app_id}'" }
        rescue ex
          raise Error.new("Failed to create system tray: #{ex.message}", :tray_create_failed)
        end

        # Update the tray icon image.
        def update_icon(icon : ::NativeDesktop::TrayIcon) : Nil
          return if @@hwnd.null?

          # Destroy previous icon to prevent leak
          unless @@prev_hicon.null?
            LibGDI32.DestroyIcon(@@prev_hicon) rescue nil
          end

          @@prev_hicon = @@hicon
          @@hicon = IconHelpers.hicon_from_source(icon)
          build_nid(@@hwnd, @@hicon, NIF_ICON, "", TRAY_MSG_ID)
          LibShell32.Shell_NotifyIconW(NIM_MODIFY, @@nid_buffer.to_unsafe)
        end

        # Update the tooltip.
        def tooltip=(text : String) : Nil
          return if @@hwnd.null?
          build_nid(@@hwnd, @@hicon, NIF_TIP, text, TRAY_MSG_ID)
          LibShell32.Shell_NotifyIconW(NIM_MODIFY, @@nid_buffer.to_unsafe)
        end

        # Store menu items and callbacks for use when right-click occurs.
        # items: Array of {id, label, type_int, enabled_int, checked_int, parent_id}
        #   parent_id is empty string for top-level items.
        def set_menu(items : Array(PlatformTrayMenuEntry), callbacks : Hash(String, Proc(Nil))) : Nil
          @@menu_items = items
          @@item_callbacks = callbacks
        end

        # Register a click callback (called with 0=left, 1=right).
        def on_click(&block : Int32 ->) : Nil
          @@click_callback = block
        end

        # Remove the tray icon.
        def destroy : Nil
          return if @@hwnd.null?

          build_nid(@@hwnd, Pointer(Void).null, 0_u32, "", 0_u32)
          LibShell32.Shell_NotifyIconW(NIM_DELETE, @@nid_buffer.to_unsafe)
          LibUser32.DestroyWindow(@@hwnd)

          # Clean up icons
          unless @@hicon.null?
            LibGDI32.DestroyIcon(@@hicon) rescue nil
          end
          unless @@prev_hicon.null?
            LibGDI32.DestroyIcon(@@prev_hicon) rescue nil
          end

          @@hwnd = Pointer(Void).null
          @@hicon = Pointer(Void).null
          @@prev_hicon = Pointer(Void).null
          @@item_callbacks.clear
        end
      end
    end
  end
end
