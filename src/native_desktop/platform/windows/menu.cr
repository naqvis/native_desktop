require "log"
require "./win32_common"
require "./string_helpers"

module NativeDesktop
  module Platform
    module Windows
      module Menu
        extend self

        GWLP_WNDPROC_MENU = -4

        WM_COMMAND_MENU = 0x0111_u32

        # ACCEL.fVirt flags
        FACCEL_VIRTKEY = 0x01_u8
        FACCEL_SHIFT   = 0x04_u8
        FACCEL_CONTROL = 0x08_u8
        FACCEL_ALT     = 0x10_u8

        # Map key tokens to Win32 virtual-key codes.
        VK_TABLE = {
          "a" => 0x41_u16, "b" => 0x42_u16, "c" => 0x43_u16, "d" => 0x44_u16,
          "e" => 0x45_u16, "f" => 0x46_u16, "g" => 0x47_u16, "h" => 0x48_u16,
          "i" => 0x49_u16, "j" => 0x4A_u16, "k" => 0x4B_u16, "l" => 0x4C_u16,
          "m" => 0x4D_u16, "n" => 0x4E_u16, "o" => 0x4F_u16, "p" => 0x50_u16,
          "q" => 0x51_u16, "r" => 0x52_u16, "s" => 0x53_u16, "t" => 0x54_u16,
          "u" => 0x55_u16, "v" => 0x56_u16, "w" => 0x57_u16, "x" => 0x58_u16,
          "y" => 0x59_u16, "z" => 0x5A_u16,
          "0" => 0x30_u16, "1" => 0x31_u16, "2" => 0x32_u16, "3" => 0x33_u16,
          "4" => 0x34_u16, "5" => 0x35_u16, "6" => 0x36_u16, "7" => 0x37_u16,
          "8" => 0x38_u16, "9" => 0x39_u16,
          "f1" => 0x70_u16, "f2" => 0x71_u16, "f3" => 0x72_u16, "f4" => 0x73_u16,
          "f5" => 0x74_u16, "f6" => 0x75_u16, "f7" => 0x76_u16, "f8" => 0x77_u16,
          "f9" => 0x78_u16, "f10" => 0x79_u16, "f11" => 0x7A_u16, "f12" => 0x7B_u16,
          "space" => 0x20_u16, "enter" => 0x0D_u16, "return" => 0x0D_u16,
          "tab" => 0x09_u16, "escape" => 0x1B_u16, "esc" => 0x1B_u16,
          "backspace" => 0x08_u16, "delete" => 0x2E_u16,
          "left" => 0x25_u16, "up" => 0x26_u16, "right" => 0x27_u16, "down" => 0x28_u16,
          "home" => 0x24_u16, "end" => 0x23_u16, "pageup" => 0x21_u16, "pagedown" => 0x22_u16,
        }

        @@menu_hwnd : Void* = Pointer(Void).null
        @@hmenu : Void* = Pointer(Void).null
        @@haccel : Void* = Pointer(Void).null
        @@original_wndproc : Int64 = 0_i64
        @@callbacks : Hash(UInt16, Proc(Nil)) = {} of UInt16 => Proc(Nil)
        @@next_cmd_id : UInt16 = 1000_u16
        # Pending accelerator descriptors: {fVirt, key, cmd_id}
        @@accel_specs : Array({UInt8, UInt16, UInt16}) = [] of {UInt8, UInt16, UInt16}

        # Attach a menu bar to the given top-level window (HWND).
        def set_window_menu(window_ptr : Void*, menu_bar : ::NativeDesktop::MenuBar) : Nil
          return if window_ptr.null?

          teardown

          @@menu_hwnd = window_ptr
          @@callbacks.clear
          @@accel_specs.clear
          @@next_cmd_id = 1000_u16

          @@hmenu = LibUser32.CreateMenu
          return if @@hmenu.null?

          menu_bar.menus.each do |menu|
            submenu = build_popup(menu)
            StringHelpers.with_utf16_bytes(menu.label) do |label_ptr|
              LibUser32.AppendMenuW(@@hmenu, MFM_POPUP, submenu.address, label_ptr)
            end
          end

          LibUser32.SetMenu(window_ptr, @@hmenu)
          LibUser32.DrawMenuBar(window_ptr)

          install_wndproc(window_ptr)
          build_accelerator_table

          Log.debug { "Menu[Windows]: installed menu bar with #{menu_bar.menus.size} top-level menus" }
        rescue ex
          Log.error { "Menu[Windows]: failed to set window menu: #{ex.message}" }
        end

        # Windows menu bars are per-window. With no window we reuse the last one.
        def global_menu=(menu_bar : ::NativeDesktop::MenuBar) : Nil
          if @@menu_hwnd.null?
            Log.warn { "Menu[Windows]: no window available; menu bar attaches per-window on Win32" }
            return
          end
          set_window_menu(@@menu_hwnd, menu_bar)
        end

        private def build_popup(menu : ::NativeDesktop::Menu) : Void*
          hmenu = LibUser32.CreatePopupMenu
          return hmenu if hmenu.null?

          menu.entries.each do |item|
            case item
            in ::NativeDesktop::Menu
              sub = build_popup(item)
              StringHelpers.with_utf16_bytes(item.label) do |label_ptr|
                LibUser32.AppendMenuW(hmenu, MFM_POPUP, sub.address, label_ptr)
              end
            in ::NativeDesktop::MenuSeparator
              LibUser32.AppendMenuW(hmenu, MFM_SEPARATOR, 0_u64, Pointer(UInt16).null)
            in ::NativeDesktop::MenuItem
              cmd_id = @@next_cmd_id
              @@next_cmd_id += 1_u16

              flags = MFM_STRING
              flags |= MFM_GRAYED unless item.enabled
              flags |= MFM_CHECKED if item.checked

              label = menu_label_with_accel(item.label, item.accelerator)
              StringHelpers.with_utf16_bytes(label) do |label_ptr|
                LibUser32.AppendMenuW(hmenu, flags, cmd_id.to_u64, label_ptr)
              end

              if action = item.action
                @@callbacks[cmd_id] = action
              end

              if accel = item.accelerator
                register_accel_spec(accel, cmd_id)
              end
            end
          end

          hmenu
        end

        # Append the shortcut hint to the label (Win32 shows text after a tab).
        private def menu_label_with_accel(label : String, accel : String?) : String
          return label unless accel
          "#{label}\t#{accel}"
        end

        private def register_accel_spec(accel : String, cmd_id : UInt16) : Nil
          parts = accel.split("+").map(&.strip).reject(&.empty?)
          return if parts.empty?

          vk = VK_TABLE[parts.last.downcase]?
          return unless vk

          fvirt = FACCEL_VIRTKEY
          parts[0..-2].each do |part|
            case part.downcase
            when "cmd", "command", "meta", "super", "win", "ctrl", "control"
              fvirt |= FACCEL_CONTROL
            when "alt", "option"
              fvirt |= FACCEL_ALT
            when "shift"
              fvirt |= FACCEL_SHIFT
            end
          end

          @@accel_specs << {fvirt, vk, cmd_id}
        end

        # Build the HACCEL from accumulated specs and hand it to the message loop.
        private def build_accelerator_table : Nil
          return if @@accel_specs.empty?

          # ACCEL is pack(2): fVirt(BYTE)@0, key(WORD)@2, cmd(WORD)@4 => 6 bytes.
          buf = Bytes.new(@@accel_specs.size * 6, 0_u8)
          @@accel_specs.each_with_index do |spec, i|
            fvirt, key, cmd = spec
            base = i * 6
            buf[base] = fvirt
            IO::ByteFormat::LittleEndian.encode(key, buf[base + 2, 2])
            IO::ByteFormat::LittleEndian.encode(cmd, buf[base + 4, 2])
          end

          @@haccel = LibUser32.CreateAcceleratorTableW(buf.to_unsafe.as(Void*), @@accel_specs.size)
        end

        # Called by the host message loop before normal message translation.
        def process_event(event : Void*) : Bool
          return false if event.null? || @@haccel.null? || @@menu_hwnd.null?
          LibUser32.TranslateAcceleratorW(@@menu_hwnd, @@haccel, event) != 0
        end

        # Window procedure that intercepts WM_COMMAND for menu clicks and chains
        # everything else to the original procedure.
        private def menu_wndproc(h_wnd : Void*, msg : UInt32, w_param : UInt64, l_param : Int64) : Int64
          if msg == WM_COMMAND_MENU && l_param == 0_i64
            # Menu commands: HIWORD(wParam)==0, LOWORD(wParam)==command id.
            if (w_param >> 16) == 0_u64
              cmd_id = (w_param & 0xFFFF).to_u16
              if cb = @@callbacks[cmd_id]?
                begin
                  cb.call
                rescue ex
                  Log.error { "Menu[Windows]: click handler error: #{ex.message}" }
                end
                return 0_i64
              end
            end
          end
          LibUser32.CallWindowProcW(@@original_wndproc, h_wnd, msg, w_param, l_param)
        end

        private def install_wndproc(window_ptr : Void*) : Nil
          return unless @@original_wndproc == 0_i64
          @@original_wndproc = LibUser32.GetWindowLongPtrW(window_ptr, GWLP_WNDPROC_MENU)
          new_proc = ->(h_wnd : Void*, msg : UInt32, w_param : UInt64, l_param : Int64) : Int64 {
            menu_wndproc(h_wnd, msg, w_param, l_param)
          }
          LibUser32.SetWindowLongPtrW(window_ptr, GWLP_WNDPROC_MENU, new_proc.pointer.address.to_i64!)
        end

        private def teardown : Nil
          unless @@haccel.null?
            LibUser32.DestroyAcceleratorTable(@@haccel)
            @@haccel = Pointer(Void).null
          end

          if !@@menu_hwnd.null? && @@original_wndproc != 0_i64
            LibUser32.SetWindowLongPtrW(@@menu_hwnd, GWLP_WNDPROC_MENU, @@original_wndproc)
            @@original_wndproc = 0_i64
          end

          unless @@menu_hwnd.null?
            LibUser32.SetMenu(@@menu_hwnd, Pointer(Void).null)
            LibUser32.DrawMenuBar(@@menu_hwnd)
          end

          unless @@hmenu.null?
            LibUser32.DestroyMenu(@@hmenu)
            @@hmenu = Pointer(Void).null
          end
        end
      end
    end
  end
end
