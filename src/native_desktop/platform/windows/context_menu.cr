require "log"
require "./win32_common"

module NativeDesktop
  module Platform
    module Windows
      module ContextMenu
        extend self

        TPM_RIGHTBUTTON = 0x00000002_u32
        TPM_RETURNCMD   = 0x00000100_u32
        MFM_STRING      = 0x00000000_u32
        MFM_GRAYED      = 0x00000001_u32
        MFM_CHECKED     = 0x00000008_u32
        MFM_POPUP       = 0x00000010_u32
        MFM_SEPARATOR   = 0x00000800_u32

        WM_NULL = 0x0000_u32

        Log = ::Log.for(self)

        def available? : Bool
          true
        end

        def show_context_menu(items : Array(NativeDesktop::ContextMenuItem), x : Int32, y : Int32, window_ptr : Void*) : String?
          hmenu = LibUser32.CreatePopupMenu
          return nil if hmenu.null?
          begin
            cmd_map = {} of UInt16 => String
            next_cmd = 1000_u16

            append_items(items, hmenu, cmd_map, pointerof(next_cmd))

            # JS sends clientX/clientY (viewport-relative), but TrackPopupMenu
            # expects screen coordinates. Use GetCursorPos which is the standard
            # Windows pattern for context menu positioning.
            pt = LibUser32::Point.new
            LibUser32.GetCursorPos(pointerof(pt))

            LibUser32.SetForegroundWindow(window_ptr)
            selected = LibUser32.TrackPopupMenu(
              hmenu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
              pt.x, pt.y, 0, window_ptr, Pointer(Void).null,
            )
            LibUser32.PostMessageW(window_ptr, WM_NULL, 0_u64, 0_i64)

            LibUser32.DestroyMenu(hmenu)

            return nil if selected == 0
            cmd_map[selected.to_u16]?
          rescue ex
            Log.error { "ContextMenu[Windows]: #{ex.message}" }
            LibUser32.DestroyMenu(hmenu) unless hmenu.null?
            nil
          end
        end

        private def append_items(
          items : Array(NativeDesktop::ContextMenuItem),
          hmenu : Void*,
          cmd_map : Hash(UInt16, String),
          next_cmd : Pointer(UInt16),
        ) : Nil
          items.each do |item|
            case item.type
            in .separator?
              LibUser32.AppendMenuW(hmenu, MFM_SEPARATOR, 0_u64, Pointer(UInt16).null)
            in .normal?, .checkbox?
              if sub = item.submenu
                submenu = LibUser32.CreatePopupMenu
                unless submenu.null?
                  append_items(sub, submenu, cmd_map, next_cmd)
                  with_utf16(item.label) do |label_ptr|
                    LibUser32.AppendMenuW(hmenu, MFM_POPUP, submenu.address, label_ptr)
                  end
                end
              else
                flags = MFM_STRING
                flags |= MFM_GRAYED unless item.enabled?
                flags |= MFM_CHECKED if item.checked?
                cmd_map[next_cmd.value] = item.id
                with_utf16(item.label) do |label_ptr|
                  LibUser32.AppendMenuW(hmenu, flags, next_cmd.value.to_u64, label_ptr)
                end
                next_cmd.value += 1_u16
              end
            end
          end
        end

        private def with_utf16(value : String, &block : UInt16* -> T) : T forall T
          units = value.to_utf16
          buffer = Slice(UInt16).new(units.size + 1, 0_u16)
          units.each_with_index { |unit, index| buffer[index] = unit }
          yield buffer.to_unsafe
        end
      end
    end
  end
end
