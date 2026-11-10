require "log"

@[Link("gtk-3", pkg_config: "gtk+-3.0")]
lib LibGTKToolbar
  fun gtk_toolbar_new : Void*
  fun gtk_toolbar_insert(toolbar : Void*, item : Void*, pos : Int32) : Nil
  fun gtk_tool_item_new : Void*
  fun gtk_separator_tool_item_new : Void*
  fun gtk_bin_get_child(bin : Void*) : Void*
  fun gtk_box_new(orientation : Int32, spacing : Int32) : Void*
  fun gtk_box_pack_start(box : Void*, child : Void*, expand : Int32, fill : Int32, padding : UInt32) : Nil
  fun gtk_box_reorder_child(box : Void*, child : Void*, position : Int32) : Nil
  fun gtk_container_add(container : Void*, widget : Void*) : Nil
  fun gtk_container_remove(container : Void*, widget : Void*) : Nil
  fun gtk_container_get_children(container : Void*) : Void*
  fun gtk_image_new_from_icon_name(icon_name : UInt8*, size : Int32) : Void*
  fun gtk_image_new_from_file(filename : UInt8*) : Void*
  fun gtk_box_get_type : UInt64
  fun gtk_label_new(str : UInt8*) : Void*
  fun gtk_button_new : Void*
  fun gtk_button_set_relief(button : Void*, relief : Int32) : Nil
  fun gtk_icon_theme_get_default : Void*
  fun gtk_icon_theme_has_icon(theme : Void*, icon_name : UInt8*) : Int32
  fun gtk_toggle_button_new : Void*
  fun gtk_toggle_button_set_active(toggle_button : Void*, is_active : Int32) : Nil
  fun gtk_toggle_button_get_active(toggle_button : Void*) : Int32
  fun gtk_menu_tool_button_new(icon_widget : Void*, label : UInt8*) : Void*
  fun gtk_menu_tool_button_set_menu(menu_tool_button : Void*, menu : Void*) : Nil
  fun gtk_color_button_new : Void*
  fun gtk_color_button_set_rgba(button : Void*, rgba : GdkRGBA*) : Nil
  fun gtk_color_chooser_get_rgba(chooser : Void*, rgba : GdkRGBA*) : Nil
  fun gtk_menu_new : Void*
  fun gtk_menu_item_new_with_label(label : UInt8*) : Void*
  fun gtk_menu_shell_append(menu : Void*, item : Void*) : Nil
  fun gtk_widget_show(widget : Void*) : Nil
  fun gtk_widget_hide(widget : Void*) : Nil
  fun gtk_widget_show_all(widget : Void*) : Nil
  fun gtk_widget_set_sensitive(widget : Void*, sensitive : Int32) : Nil
  fun gtk_widget_destroy(widget : Void*) : Nil
  fun gtk_widget_get_visible(widget : Void*) : Int32

  struct GdkRGBA
    red : Float64
    green : Float64
    blue : Float64
    alpha : Float64
  end
end

@[Link("gobject-2.0")]
lib LibGObjectToolbar
  fun g_object_ref(object : Void*) : Void*
  fun g_object_unref(object : Void*) : Nil
  fun g_signal_connect_data(instance : Void*, signal : UInt8*, callback : Void*, data : Void*, destroy_data : Void*, flags : Int32) : UInt64
  fun g_type_check_instance_is_a(instance : Void*, type : UInt64) : Int32
end

@[Link("glib-2.0")]
lib LibGLibToolbar
  fun g_list_length(list : Void*) : UInt32
  fun g_list_nth_data(list : Void*, index : UInt32) : Void*
  fun g_list_free(list : Void*) : Nil
end

module NativeDesktop
  module Platform
    module Linux
      module Toolbar
        extend self

        GTK_ICON_SIZE_SMALL_TOOLBAR = 2

        @@native : Void* = Pointer(Void).null
        @@toolbar : Void* = Pointer(Void).null
        @@item_widgets : Hash(String, Void*) = {} of String => Void*
        @@actions : Hash(String, Proc(Nil)?) = {} of String => Proc(Nil)?
        @@menu_item_map : Hash(Void*, String) = {} of Void* => String

        def register(native : Void*, _content : Void*?, feature : ::NativeDesktop::Toolbar) : Nil
          return if !@@toolbar.null? && @@native != native
          cleanup unless @@toolbar.null?
          @@actions.clear
          feature.items.each { |item| @@actions[item.id] = item.action }

          return if native.null?

          child = LibGTKToolbar.gtk_bin_get_child(native)
          return if child.null?

          box_type = LibGTKToolbar.gtk_box_get_type
          if LibGObjectToolbar.g_type_check_instance_is_a(child, box_type) != 0
            box = child
          else
            was_visible = LibGTKToolbar.gtk_widget_get_visible(native) != 0
            LibGObjectToolbar.g_object_ref(child)
            LibGTKToolbar.gtk_container_remove(native, child)
            box = LibGTKToolbar.gtk_box_new(1, 0)
            LibGTKToolbar.gtk_container_add(native, box)
            LibGTKToolbar.gtk_box_pack_start(box, child, 1, 1, 0_u32)
            LibGObjectToolbar.g_object_unref(child)
            if was_visible
              LibGTKToolbar.gtk_widget_show_all(native)
            end
          end

          tb = LibGTKToolbar.gtk_toolbar_new
          rebuild_items(tb, feature.items)

          # Insert toolbar below any existing menu bar (position 1) or at top (position 0) if no menu
          existing = LibGTKToolbar.gtk_container_get_children(box)
          n = existing.null? ? 1 : LibGLibToolbar.g_list_length(existing)
          LibGLibToolbar.g_list_free(existing) unless existing.null?
          pos = n > 1 ? 1 : 0

          LibGTKToolbar.gtk_box_pack_start(box, tb, 0, 0, 0_u32)
          LibGTKToolbar.gtk_box_reorder_child(box, tb, pos)
          LibGTKToolbar.gtk_widget_show_all(tb)

          if !feature.visible?
            LibGTKToolbar.gtk_widget_hide(tb)
          end

          @@toolbar = tb
          @@native = native
          Log.debug { "Toolbar[Linux]: installed GTK toolbar with #{feature.items.size} items" }
        end

        def update_items(items : Array(::NativeDesktop::ToolbarItem)) : Nil
          @@actions.clear
          items.each { |item| @@actions[item.id] = item.action }
          return if @@toolbar.null?
          rebuild_items(@@toolbar, items)
          LibGTKToolbar.gtk_widget_show_all(@@toolbar)
        end

        def visible=(visible : Bool) : Nil
          return if @@toolbar.null?
          if visible
            LibGTKToolbar.gtk_widget_show(@@toolbar)
          else
            LibGTKToolbar.gtk_widget_hide(@@toolbar)
          end
        end

        @@temp_icon_files = [] of String

        def cleanup_temp_files : Nil
          @@temp_icon_files.each do |p|
            File.delete(p) rescue nil
          end
          @@temp_icon_files.clear
        end

        def cleanup : Nil
          cleanup_temp_files
          LibGTKToolbar.gtk_widget_destroy(@@toolbar) unless @@toolbar.null?
          @@native = Pointer(Void).null
          @@toolbar = Pointer(Void).null
          @@item_widgets.clear
          @@actions.clear
          @@menu_item_map.clear
        end

        private def rebuild_items(tb : Void*, items : Array(::NativeDesktop::ToolbarItem)) : Nil
          clear_toolbar(tb)
          @@item_widgets.clear
          @@menu_item_map.clear

          items.each do |item|
            if item.id == "__separator__"
              sep = LibGTKToolbar.gtk_separator_tool_item_new
              LibGTKToolbar.gtk_toolbar_insert(tb, sep, -1_i32)
              next
            end

            case item.type
            when ::NativeDesktop::ToolbarItemType::Dropdown
              icon_widget = create_icon_widget_from_source(item.icon)
              tool_btn = LibGTKToolbar.gtk_menu_tool_button_new(icon_widget, item.label.to_unsafe)
              menu = LibGTKToolbar.gtk_menu_new
              item.options.each do |opt|
                menu_item = LibGTKToolbar.gtk_menu_item_new_with_label(opt.to_unsafe)
                LibGTKToolbar.gtk_menu_shell_append(menu, menu_item)
                @@menu_item_map[menu_item] = item.id
                LibGObjectToolbar.g_signal_connect_data(
                  menu_item, "activate".to_unsafe,
                  ->(widget : Void*, _data : Void*) {
                    if id = @@menu_item_map[widget]?
                      if action = @@actions[id]?
                        invoke(action)
                      end
                    end
                    0
                  }.pointer,
                  Pointer(Void).null, Pointer(Void).null, 0_i32,
                )
              end
              LibGTKToolbar.gtk_widget_show_all(menu)
              LibGTKToolbar.gtk_menu_tool_button_set_menu(tool_btn, menu)
              LibGTKToolbar.gtk_toolbar_insert(tb, tool_btn, -1_i32)
              LibGTKToolbar.gtk_widget_set_sensitive(tool_btn, item.enabled ? 1 : 0)
              @@item_widgets[item.id] = tool_btn
            when ::NativeDesktop::ToolbarItemType::Color
              btn = LibGTKToolbar.gtk_color_button_new
              rgba = parse_hex_rgba(item.color)
              LibGTKToolbar.gtk_color_button_set_rgba(btn, pointerof(rgba))
              tool_item = LibGTKToolbar.gtk_tool_item_new
              LibGTKToolbar.gtk_container_add(tool_item, btn)
              LibGTKToolbar.gtk_toolbar_insert(tb, tool_item, -1_i32)
              LibGTKToolbar.gtk_widget_set_sensitive(tool_item, item.enabled ? 1 : 0)
              LibGTKToolbar.gtk_widget_show_all(tool_item)
              @@item_widgets[item.id] = btn
              LibGObjectToolbar.g_signal_connect_data(
                btn, "color-set".to_unsafe,
                ->(widget : Void*, _data : Void*) {
                  handle_item_click(widget)
                  0
                }.pointer,
                Pointer(Void).null, Pointer(Void).null, 0_i32,
              )
            else
              btn = if item.type == ::NativeDesktop::ToolbarItemType::Toggle
                      toggle = LibGTKToolbar.gtk_toggle_button_new
                      LibGTKToolbar.gtk_toggle_button_set_active(toggle, item.checked ? 1 : 0)
                      toggle
                    else
                      LibGTKToolbar.gtk_button_new
                    end
              LibGTKToolbar.gtk_button_set_relief(btn, 2)

              hbox = LibGTKToolbar.gtk_box_new(0, 3)
              icon_widget = create_icon_widget_from_source(item.icon)
              LibGTKToolbar.gtk_box_pack_start(hbox, icon_widget, 0, 0, 0_u32) unless icon_widget.null?

              lbl = LibGTKToolbar.gtk_label_new(item.label.to_unsafe)
              LibGTKToolbar.gtk_box_pack_start(hbox, lbl, 0, 0, 0_u32)

              LibGTKToolbar.gtk_container_add(btn, hbox)

              tool_item = LibGTKToolbar.gtk_tool_item_new
              LibGTKToolbar.gtk_container_add(tool_item, btn)
              LibGTKToolbar.gtk_toolbar_insert(tb, tool_item, -1_i32)

              LibGTKToolbar.gtk_widget_set_sensitive(tool_item, item.enabled ? 1 : 0)
              LibGTKToolbar.gtk_widget_show_all(tool_item)

              @@item_widgets[item.id] = btn

              LibGObjectToolbar.g_signal_connect_data(
                btn, "clicked".to_unsafe,
                ->(widget : Void*, _data : Void*) {
                  handle_item_click(widget)
                  0
                }.pointer,
                Pointer(Void).null, Pointer(Void).null, 0_i32,
              )
            end
          end
        end

        private def create_icon_widget_from_source(icon : ::NativeDesktop::ToolbarIcon?) : Void*
          return Pointer(Void).null unless icon
          if b = icon.bytes
            key = icon.key || "toolbar"
            filename = "native-desktop-toolbar-#{key.gsub('/', '_')}.png"
            path = File.join(Dir.tempdir, filename)
            unless File.exists?(path)
              File.write(path, b)
              @@temp_icon_files << path
            end
            LibGTKToolbar.gtk_image_new_from_file(path.to_unsafe)
          elsif n = icon.name
            create_icon_widget(n)
          else
            Pointer(Void).null
          end
        end

        private def create_icon_widget(icon_name : String?) : Void*
          return Pointer(Void).null unless icon_name
          icon_ok = if icon_name.includes?('/')
                      File.exists?(icon_name)
                    else
                      theme = LibGTKToolbar.gtk_icon_theme_get_default
                      LibGTKToolbar.gtk_icon_theme_has_icon(theme, icon_name.to_unsafe) != 0
                    end
          return Pointer(Void).null unless icon_ok
          if icon_name.includes?('/')
            LibGTKToolbar.gtk_image_new_from_file(icon_name.to_unsafe)
          else
            LibGTKToolbar.gtk_image_new_from_icon_name(icon_name.to_unsafe, GTK_ICON_SIZE_SMALL_TOOLBAR)
          end
        end

        private def parse_hex_rgba(hex : String) : LibGTKToolbar::GdkRGBA
          rgba = LibGTKToolbar::GdkRGBA.new(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
          return rgba if hex.empty? || hex.size < 6
          s = hex.lstrip('#')
          rgba.red = s[0..1].to_i(16) / 255.0
          rgba.green = s[2..3].to_i(16) / 255.0
          rgba.blue = s[4..5].to_i(16) / 255.0
          rgba
        end

        private def clear_toolbar(tb : Void*) : Nil
          children = LibGTKToolbar.gtk_container_get_children(tb)
          return if children.null?
          n = LibGLibToolbar.g_list_length(children)
          n.times do |i|
            widget = LibGLibToolbar.g_list_nth_data(children, i)
            LibGTKToolbar.gtk_widget_destroy(widget) unless widget.null?
          end
          LibGLibToolbar.g_list_free(children)
        end

        private def handle_item_click(widget : Void*) : Nil
          @@item_widgets.each do |id, widget_ptr|
            next unless widget_ptr == widget
            if action = @@actions[id]?
              invoke(action)
            end
            break
          end
        rescue ex
          Log.error { "Toolbar item click error: #{ex.message}" }
        end

        private def invoke(action : Proc(Nil)?) : Nil
          action.try(&.call)
        rescue ex
          Log.error { "Toolbar[Linux]: item callback failed: #{ex.message}" }
        end
      end
    end
  end
end
