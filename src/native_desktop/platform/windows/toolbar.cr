require "log"
require "./win32_common"
require "./icon_helpers"

module NativeDesktop
  module Platform
    module Windows
      # Toolbar-specific structs (C-compatible layout inside lib block)
      @[Link("user32")]
      lib LibUserToolbar
        struct TBBUTTON
          i_bitmap : Int32
          id_command : Int32
          fs_state : UInt8
          fs_style : UInt8
          b_reserved : UInt8[6]
          dw_data : UInt64
          i_string : UInt64
        end

        struct NMHDR
          hwnd_from : Void*
          id_from : UInt64
          code : Int32
        end

        struct NMTOOLBARW
          hdr : NMHDR
          i_item : Int32
          rc_button : LibUser32::Rect
        end
      end

      @[Link("comctl32")]
      lib LibComCtl32
        fun InitCommonControls : Void
        fun ImageList_Create(cx : Int32, cy : Int32, flags : UInt32, cInitial : Int32, cGrow : Int32) : Void*
        fun ImageList_Destroy(himl : Void*) : Int32
        fun ImageList_AddIcon(himl : Void*, hicon : Void*) : Int32
        fun ImageList_Add(himl : Void*, hbm_image : Void*, hbm_mask : Void*) : Int32
      end

      module Toolbar
        extend self

        @@cust_colors : Pointer(UInt32) = Pointer(UInt32).malloc(16)
        @@init_cc : Bool = false

        TOOLBARCLASSNAME = "ToolbarWindow32"

        WS_CHILD         = 0x40000000_u32
        TBWS_VISIBLE     = 0x10000000_u32
        WS_CLIPSIBLINGS  = 0x04000000_u32
        TBSTYLE_TOOLTIPS = 0x00000100_u32
        TBSTYLE_FLAT     = 0x00000800_u32
        TBSTYLE_LIST     = 0x00001000_u32
        CCS_TOP          = 0x00000001_u32
        CCS_NORESIZE     = 0x00000004_u32

        IMAGE_ICON      =          1
        LR_LOADFROMFILE = 0x0010_u32
        ILC_COLOR32     = 0x0020_u32

        TB_ADDBUTTONSA      = 0x0414_u32
        TB_DELETEBUTTON     = 0x0416_u32
        TB_BUTTONSTRUCTSIZE = 0x041E_u32
        TB_ADDBUTTONSW      = 0x044E_u32
        TB_GETRECT          = 0x0433_u32
        TB_AUTOSIZE         = 0x0421_u32
        TB_SETSTATE         = 0x0441_u32
        TB_GETSTATE         = 0x0442_u32
        TB_ENABLEBUTTON     = 0x0401_u32
        TB_HIDEBUTTON       = 0x0404_u32
        TB_ISBUTTONHIDDEN   = 0x040C_u32
        TB_ADDSTRINGA       = 0x041C_u32
        TB_ADDSTRINGW       = 0x044D_u32
        TB_SETIMAGELIST     = 0x0430_u32
        TB_SETBITMAPSIZE    = 0x0420_u32
        TB_SETBUTTONINFOA   = 0x0440_u32

        BTNS_BUTTON        = 0x0000_u8
        BTNS_SEP           = 0x0001_u8
        BTNS_CHECKBOX      = 0x0002_u8
        BTNS_DROPDOWN      = 0x0008_u8
        BTNS_AUTOSIZE      = 0x0010_u8
        BTNS_WHOLEDROPDOWN = 0x0080_u8
        BTNS_SHOWTEXT      = 0x0040_u8

        CC_RGBINIT        = 0x00000001_u32
        CC_FULLOPEN       = 0x00000002_u32
        TBSTATE_ENABLED   =           4_u8
        TBSTATE_CHECKED   =           1_u8
        I_IMAGECALLBACK   =             -1
        IMAGE_BITMAP      =          0_u32
        TBLR_LOADFROMFILE =     0x0010_u32
        TBSW_SHOW         =              5
        TBSW_HIDE         =              0

        GWLP_WNDPROC =         -4
        WM_SIZE      = 0x0005_u32
        WM_COMMAND   = 0x0111_u32
        WM_NCDESTROY = 0x0082_u32
        WM_NOTIFY    = 0x004E_u32
        TBN_FIRST    =       -700
        TBN_DROPDOWN = TBN_FIRST - 10

        MF_STRING     = 0x00000000_u32
        TPM_RETURNCMD = 0x00000100_u32
        TPM_LEFTALIGN = 0x00000000_u32
        TPM_TOPALIGN  = 0x00000000_u32

        DROPDOWN_MENU_ITEM_BASE = 1000

        @@toolbar_hwnd : Void* = Pointer(Void).null
        @@parent_hwnd : Void* = Pointer(Void).null
        @@content_hwnd : Void* = Pointer(Void).null
        @@button_count : Int32 = 0
        @@visible : Bool = true
        @@create_timer : UInt64 = 0_u64
        @@timer_proc : (Void*, UInt32, UInt64, UInt32 -> Nil)? = nil
        @@himl : Void* = Pointer(Void).null
        @@items : Array(::NativeDesktop::ToolbarItem) = [] of ::NativeDesktop::ToolbarItem
        @@original_wndproc : Int64 = 0_i64
        @@wndproc_proc : (Void*, UInt32, UInt64, Int64 -> Int64)? = nil

        def register(native : Void*, content : Void*?, feature : ::NativeDesktop::Toolbar) : Nil
          return if native.null?
          cleanup unless @@toolbar_hwnd.null?
          init_common_controls

          @@parent_hwnd = native
          @@content_hwnd = content || Pointer(Void).null
          @@items = feature.items
          @@button_count = @@items.size.to_i32
          @@visible = feature.visible?
          install_parent_hook(native)
          request_toolbar_creation unless @@items.empty?
        end

        def update_items(items : Array(::NativeDesktop::ToolbarItem)) : Nil
          toolbar = @@toolbar_hwnd
          if toolbar.null?
            @@items = items
            @@button_count = items.size.to_i32
            request_toolbar_creation unless items.empty?
            return
          end

          @@button_count.times do
            LibUser32.SendMessageA(toolbar, TB_DELETEBUTTON, 0_u64, Pointer(Void).null)
          end

          LibUser32.SendMessageA(toolbar, TB_SETIMAGELIST, 0_u64, Pointer(Void).null)
          cleanup_image_list

          @@items = items
          init_image_list(toolbar, @@items)
          items.each_with_index do |item, idx|
            add_button(toolbar, item, idx)
          end
          LibUser32.SendMessageA(toolbar, TB_AUTOSIZE, 0_u64, Pointer(Void).null)
          @@button_count = items.size.to_i32
          reposition_child_windows(@@parent_hwnd)
        end

        def visible=(visible : Bool) : Nil
          @@visible = visible
          return if @@toolbar_hwnd.null?
          LibUser32.ShowWindow(@@toolbar_hwnd, visible ? TBSW_SHOW : TBSW_HIDE)
        end

        def cleanup : Nil
          if @@create_timer != 0_u64 && !@@parent_hwnd.null?
            LibUser32.KillTimer(@@parent_hwnd, @@create_timer)
            @@create_timer = 0_u64
          end
          if !@@parent_hwnd.null? && @@original_wndproc != 0_i64 && LibUser32.IsWindow(@@parent_hwnd) != 0
            LibUser32.SetWindowLongPtrW(@@parent_hwnd, GWLP_WNDPROC, @@original_wndproc)
          end
          @@original_wndproc = 0_i64

          if !@@toolbar_hwnd.null? && LibUser32.IsWindow(@@toolbar_hwnd) != 0
            LibUser32.DestroyWindow(@@toolbar_hwnd)
          end
          restore_content
          @@toolbar_hwnd = Pointer(Void).null
          @@parent_hwnd = Pointer(Void).null
          @@content_hwnd = Pointer(Void).null
          @@button_count = 0
          @@visible = true
          @@items = [] of ::NativeDesktop::ToolbarItem
          cleanup_image_list
        end

        private def create_toolbar : Nil
          return unless @@toolbar_hwnd.null?
          parent = @@parent_hwnd
          return if parent.null?
          if LibUser32.IsWindow(parent) == 0
            Log.error { "Toolbar[Windows]: supplied parent handle is not a valid HWND" }
            return
          end

          toolbar = LibUser32.CreateWindowExA(
            0_u32, TOOLBARCLASSNAME.to_unsafe, Pointer(UInt8).null,
            WS_CHILD | TBWS_VISIBLE | WS_CLIPSIBLINGS | TBSTYLE_TOOLTIPS | TBSTYLE_FLAT | CCS_TOP,
            0, 0, 0, 0,
            parent, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null,
          )
          if toolbar.null?
            Log.error { "Toolbar[Windows]: CreateWindowExA failed with Win32 error #{LibKernel32.GetLastError}" }
            return
          end

          LibUser32.SendMessageA(
            toolbar,
            TB_BUTTONSTRUCTSIZE,
            sizeof(LibUserToolbar::TBBUTTON).to_u64!,
            Pointer(Void).null
          )
          init_image_list(toolbar, @@items)
          @@items.each_with_index { |item, index| add_button(toolbar, item, index) }
          LibUser32.SendMessageA(toolbar, TB_AUTOSIZE, 0_u64, Pointer(Void).null)
          LibUser32.ShowWindow(toolbar, TBSW_HIDE) unless @@visible

          @@toolbar_hwnd = toolbar
          reposition_child_windows(parent)
        end

        private def request_toolbar_creation : Nil
          parent = @@parent_hwnd
          return if parent.null? || !@@toolbar_hwnd.null?
          return unless @@create_timer == 0_u64

          @@timer_proc ||= ->(window : Void*, _message : UInt32, timer : UInt64, _time : UInt32) : Nil {
            LibUser32.KillTimer(window, timer)
            @@create_timer = 0_u64
            create_toolbar unless @@items.empty?
          }
          timer = LibUser32.SetTimer(
            parent,
            0_u64,
            1_u32,
            @@timer_proc.not_nil!.pointer.as(Void*)
          )
          if timer == 0_u64
            Log.error { "Toolbar[Windows]: SetTimer failed with Win32 error #{LibKernel32.GetLastError}" }
          else
            @@create_timer = timer
          end
        end

        private def restore_content : Nil
          parent = @@parent_hwnd
          content = @@content_hwnd
          return if parent.null? || content.null?
          return if LibUser32.IsWindow(parent) == 0 || LibUser32.IsWindow(content) == 0

          rect = LibUser32::Rect.new
          return if LibUser32.GetClientRect(parent, pointerof(rect)) == 0
          LibUser32.MoveWindow(content, 0, 0, rect.right - rect.left, rect.bottom - rect.top, 1)
        end

        private def toolbar_wndproc(h_wnd : Void*, msg : UInt32, w_param : UInt64, l_param : Int64) : Int64
          result = LibUser32.CallWindowProcW(@@original_wndproc, h_wnd, msg, w_param, l_param)
          return result if @@toolbar_hwnd.null?
          case msg
          when WM_SIZE
            reposition_child_windows(h_wnd)
          when WM_COMMAND
            btn_id = (w_param & 0xFFFF).to_i32
            if btn_id < @@items.size
              item = @@items[btn_id]
              if item.type == ::NativeDesktop::ToolbarItemType::Color
                cc = LibComDlg::CHOOSECOLORA.new
                cc.l_struct_size = sizeof(LibComDlg::CHOOSECOLORA).to_u32!
                cc.hwnd_owner = @@parent_hwnd
                cc.lp_cust_colors = @@cust_colors.as(Void*)
                cc.flags = CC_RGBINIT
                cc.rgb_result = hex_to_colorref(item.color)
                if LibComDlg.ChooseColorA(pointerof(cc)) != 0
                  new_hex = colorref_to_hex(cc.rgb_result)
                  item.color = new_hex
                  invoke(item.action)
                end
              else
                invoke(item.action)
              end
            end
          when WM_NOTIFY
            nmhdr = Pointer(LibUserToolbar::NMHDR).new(l_param.to_u64!)
            if nmhdr.value.code == TBN_DROPDOWN
              nmtb = Pointer(LibUserToolbar::NMTOOLBARW).new(l_param.to_u64!)
              idx = nmtb.value.i_item
              if idx >= 0 && idx < @@items.size
                item = @@items[idx]
                if item.type == ::NativeDesktop::ToolbarItemType::Dropdown && !item.options.empty?
                  pt = LibUser32::Point.new
                  LibUser32.GetCursorPos(pointerof(pt))
                  menu = LibUser32.CreatePopupMenu
                  unless menu.null?
                    item.options.each_with_index do |opt, opt_idx|
                      LibUser32.AppendMenuA(menu, MF_STRING, (DROPDOWN_MENU_ITEM_BASE + opt_idx).to_u64!, opt.to_unsafe)
                    end
                    chosen = LibUser32.TrackPopupMenu(menu, TPM_RETURNCMD | TPM_LEFTALIGN | TPM_TOPALIGN, pt.x, pt.y, 0, h_wnd, Pointer(Void).null)
                    LibUser32.DestroyMenu(menu)
                    if chosen >= DROPDOWN_MENU_ITEM_BASE
                      if action = item.action
                        invoke(action)
                      end
                    end
                  end
                end
              end
              # return 1 to indicate we handled the notification
              return 1_i64
            end
          when WM_NCDESTROY
            @@toolbar_hwnd = Pointer(Void).null
          end
          result
        end

        private def install_parent_hook(parent : Void*) : Nil
          return if parent.null?
          return if @@original_wndproc != 0_i64

          @@original_wndproc = LibUser32.GetWindowLongPtrW(parent, GWLP_WNDPROC)

          @@wndproc_proc = ->(h_wnd : Void*, msg : UInt32, w_param : UInt64, l_param : Int64) : Int64 {
            toolbar_wndproc(h_wnd, msg, w_param, l_param)
          }

          LibUser32.SetWindowLongPtrW(parent, GWLP_WNDPROC, @@wndproc_proc.not_nil!.pointer.address.to_i64!)
        end

        private def reposition_child_windows(parent : Void*) : Nil
          tb = @@toolbar_hwnd
          return if tb.null? || parent.null? || LibUser32.IsWindow(tb) == 0 || LibUser32.IsWindow(parent) == 0

          tb_rect = LibUser32::Rect.new
          return if LibUser32.GetClientRect(tb, pointerof(tb_rect)) == 0
          tb_height = tb_rect.bottom
          return if tb_height <= 0

          cl_rect = LibUser32::Rect.new
          return if LibUser32.GetClientRect(parent, pointerof(cl_rect)) == 0
          cl_width = cl_rect.right
          cl_height = cl_rect.bottom

          LibUser32.SetWindowPos(tb, Pointer(Void).null, 0, 0,
            cl_width, tb_height, 0x0004_u32) # SWP_NOZORDER

          content = @@content_hwnd
          if !content.null? && LibUser32.IsWindow(content) != 0
            new_h = cl_height - tb_height
            if new_h > 0
              LibUser32.MoveWindow(content, 0, tb_height, cl_width, new_h, 1)
            end
          end
        end

        private def invoke(action : Proc(Nil)?) : Nil
          action.try(&.call)
        rescue ex
          Log.error { "Toolbar[Windows]: item callback failed: #{ex.message}" }
        end

        private def init_common_controls : Nil
          return if @@init_cc
          @@init_cc = true
          LibComCtl32.InitCommonControls
        end

        private def init_image_list(tb : Void*, items : Array(::NativeDesktop::ToolbarItem)) : Nil
          image_count = items.count { |i| !i.icon.nil? || (i.type == ::NativeDesktop::ToolbarItemType::Color && !i.color.empty?) }
          return if image_count == 0
          @@himl = LibComCtl32.ImageList_Create(16, 16, ILC_COLOR32, image_count, 0)
          return if @@himl.null?
          LibUser32.SendMessageA(tb, TB_SETIMAGELIST, 0_u64, @@himl)
        end

        private def cleanup_image_list : Nil
          return if @@himl.null?
          LibComCtl32.ImageList_Destroy(@@himl)
          @@himl = Pointer(Void).null
        end

        private def add_button(tb : Void*, item : ::NativeDesktop::ToolbarItem, idx : Int32) : Nil
          btn = LibUserToolbar::TBBUTTON.new
          if item.id == "__separator__"
            btn.fs_style = BTNS_SEP
            btn.id_command = idx
            btn.fs_state = 4_u8
          else
            label = item.type == ::NativeDesktop::ToolbarItemType::Color && !item.color.empty? ? item.color : item.label
            string = label + "\0"
            str_idx = LibUser32.SendMessageA(tb, TB_ADDSTRINGA, 0_u64, string.to_unsafe.as(Void*))

            btn.fs_style = BTNS_AUTOSIZE | BTNS_SHOWTEXT
            case item.type
            when ::NativeDesktop::ToolbarItemType::Toggle
              btn.fs_style |= BTNS_CHECKBOX
              btn.fs_state = (item.checked ? TBSTATE_CHECKED : 0) | (item.enabled ? TBSTATE_ENABLED : 0)
            when ::NativeDesktop::ToolbarItemType::Dropdown
              btn.fs_style |= BTNS_WHOLEDROPDOWN
              btn.fs_state = item.enabled ? TBSTATE_ENABLED : 0
            else
              btn.fs_style |= BTNS_BUTTON
              btn.fs_state = item.enabled ? TBSTATE_ENABLED : 0
            end

            btn.id_command = idx
            btn.i_string = str_idx

            if hicon = IconHelpers.hicon_from_source(item.icon)
              if !hicon.null? && !@@himl.null?
                btn.i_bitmap = LibComCtl32.ImageList_AddIcon(@@himl, hicon)
                LibUser32.DestroyIcon(hicon)
              end
            elsif item.type == ::NativeDesktop::ToolbarItemType::Color && !item.color.empty? && !@@himl.null?
              btn.i_bitmap = create_color_swatch(hex_to_colorref(item.color))
            end
          end
          LibUser32.SendMessageA(tb, TB_ADDBUTTONSA, 1_u64, pointerof(btn).as(Void*))
        end

        private def create_color_swatch(colorref : UInt32) : Int32
          return -1 if @@himl.null?
          dc = LibGDI32.CreateCompatibleDC(Pointer(Void).null)
          return -1 if dc.null?
          bitmap = LibGDI32.CreateCompatibleBitmap(dc, 16, 16)
          if bitmap.null?
            LibGDI32.DeleteDC(dc)
            return -1
          end
          old_obj = LibGDI32.SelectObject(dc, bitmap)
          brush = LibGDI32.CreateSolidBrush(colorref)
          LibGDI32.SelectObject(dc, brush)
          LibGDI32.PatBlt(dc, 0, 0, 16, 16, 0x0042_u32) # PATCOPY
          LibGDI32.SelectObject(dc, old_obj) unless old_obj.null?
          LibGDI32.DeleteObject(brush) unless brush.null?
          LibGDI32.DeleteDC(dc)
          idx = LibComCtl32.ImageList_Add(@@himl, bitmap, Pointer(Void).null)
          LibGDI32.DeleteObject(bitmap)
          idx
        end

        private def hex_to_colorref(hex : String) : UInt32
          s = hex.lstrip('#')
          return 0x000000_u32 if s.size < 6
          r = s[0..1].to_u32(16)
          g = s[2..3].to_u32(16)
          b = s[4..5].to_u32(16)
          # COLORREF is BGR
          (b << 16) | (g << 8) | r
        end

        private def colorref_to_hex(rgb : UInt32) : String
          r = (rgb & 0xFF)
          g = (rgb >> 8) & 0xFF
          b = (rgb >> 16) & 0xFF
          String.build { |io| io << '#' << r.to_s(16, upcase: false).rjust(2, '0') << g.to_s(16, upcase: false).rjust(2, '0') << b.to_s(16, upcase: false).rjust(2, '0') }
        end
      end
    end
  end
end
