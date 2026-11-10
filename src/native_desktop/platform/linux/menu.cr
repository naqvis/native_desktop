require "log"

# Linux application menu bar implementation using GTK+3.
#
# A GtkMenuBar is packed into the top of the webview window's content box
# (the same GtkBox the toolbar uses). Each top-level Menu becomes a
# GtkMenuItem owning a GtkMenu submenu; leaf items become GtkMenuItem /
# GtkCheckMenuItem widgets. Accelerators are registered against a
# GtkAccelGroup attached to the window so they fire while the app is focused.
#
# Click callbacks are dispatched through a flat array of actions indexed by
# the data pointer passed to g_signal_connect_data — no heap allocation and
# no GC involvement, mirroring the tray implementation.
@[Link("gtk-3", pkg_config: "gtk+-3.0")]
lib LibGTKApplicationMenu
  fun gtk_menu_bar_new : Void*
  fun gtk_menu_new : Void*
  fun gtk_menu_item_new_with_label(label : UInt8*) : Void*
  fun gtk_menu_item_set_submenu(menu_item : Void*, submenu : Void*) : Nil
  fun gtk_check_menu_item_new_with_label(label : UInt8*) : Void*
  fun gtk_check_menu_item_set_active(item : Void*, active : Int32) : Nil
  fun gtk_separator_menu_item_new : Void*
  fun gtk_menu_shell_append(menu_shell : Void*, child : Void*) : Nil
  fun gtk_box_pack_start(box : Void*, child : Void*, expand : Int32, fill : Int32, padding : UInt32) : Nil
  fun gtk_box_reorder_child(box : Void*, child : Void*, position : Int32) : Nil
  fun gtk_bin_get_child(bin : Void*) : Void*
  fun gtk_accel_group_new : Void*
  fun gtk_window_add_accel_group(window : Void*, accel_group : Void*) : Nil
  fun gtk_window_remove_accel_group(window : Void*, accel_group : Void*) : Nil
  fun gtk_widget_add_accelerator(widget : Void*, accel_signal : UInt8*, accel_group : Void*, accel_key : UInt32, accel_mods : UInt32, accel_flags : Int32) : Nil
  fun gtk_accelerator_parse(accelerator : UInt8*, accelerator_key : UInt32*, accelerator_mods : UInt32*) : Nil
  fun gtk_box_new(orientation : Int32, spacing : Int32) : Void*
  fun gtk_container_add(container : Void*, widget : Void*) : Nil
  fun gtk_container_remove(container : Void*, widget : Void*) : Nil
  fun gtk_box_get_type : UInt64
  fun gtk_widget_get_visible(widget : Void*) : Int32
  fun gtk_widget_show_all(widget : Void*) : Nil
  fun gtk_widget_set_sensitive(widget : Void*, sensitive : Int32) : Nil
  fun gtk_widget_destroy(widget : Void*) : Nil
end

@[Link("gobject-2.0")]
lib LibGObjectApplicationMenu
  fun g_object_ref(object : Void*) : Void*
  fun g_object_unref(object : Void*) : Nil
  fun g_signal_connect_data(instance : Void*, signal : UInt8*, callback : Void*, data : Void*, destroy_data : Void*, flags : Int32) : UInt64
  fun g_type_check_instance_is_a(instance : Void*, type : UInt64) : Int32
end

module NativeDesktop
  module Platform
    module Linux
      module Menu
        extend self

        GTK_ACCEL_VISIBLE = 1

        @@menu_bar_widget : Void* = Pointer(Void).null
        @@accel_group : Void* = Pointer(Void).null
        @@menu_window : Void* = Pointer(Void).null
        # Flat list of actions, indexed by (signal data pointer - 1).
        @@menu_actions : Array(Proc(Nil)?) = [] of Proc(Nil)?

        # Attach a menu bar to a specific window. This is the primary entry point
        # on Linux — the menu bar lives inside the window's content box.
        def set_window_menu(window_ptr : Void*, menu_bar : ::NativeDesktop::MenuBar) : Nil
          return if window_ptr.null?

          child = LibGTKApplicationMenu.gtk_bin_get_child(window_ptr)
          if child.null?
            Log.warn { "Menu[Linux]: window has no content box; cannot attach menu bar" }
            return
          end

          box = if gtk_box?(child)
                  child
                else
                  was_visible = LibGTKApplicationMenu.gtk_widget_get_visible(window_ptr) != 0
                  LibGObjectApplicationMenu.g_object_ref(child)
                  LibGTKApplicationMenu.gtk_container_remove(window_ptr, child)
                  new_box = LibGTKApplicationMenu.gtk_box_new(1, 0)
                  LibGTKApplicationMenu.gtk_container_add(window_ptr, new_box)
                  LibGTKApplicationMenu.gtk_box_pack_start(new_box, child, 1, 1, 0_u32)
                  LibGObjectApplicationMenu.g_object_unref(child)
                  if was_visible
                    LibGTKApplicationMenu.gtk_widget_show_all(window_ptr)
                  end
                  new_box
                end

          # Tear down any previously-installed menu bar / accel group.
          teardown

          @@menu_window = window_ptr
          @@menu_actions.clear

          @@accel_group = LibGTKApplicationMenu.gtk_accel_group_new
          LibGTKApplicationMenu.gtk_window_add_accel_group(window_ptr, @@accel_group)

          menubar = LibGTKApplicationMenu.gtk_menu_bar_new

          menu_bar.menus.each do |menu|
            top_item = LibGTKApplicationMenu.gtk_menu_item_new_with_label(menu.label)
            submenu = build_submenu(menu)
            LibGTKApplicationMenu.gtk_menu_item_set_submenu(top_item, submenu)
            LibGTKApplicationMenu.gtk_menu_shell_append(menubar, top_item)
          end

          LibGTKApplicationMenu.gtk_box_pack_start(box, menubar, 0, 0, 0_u32)
          LibGTKApplicationMenu.gtk_box_reorder_child(box, menubar, 0)
          LibGTKApplicationMenu.gtk_widget_show_all(menubar)

          @@menu_bar_widget = menubar
          Log.debug { "Menu[Linux]: installed GtkMenuBar with #{menu_bar.menus.size} top-level menus" }
        rescue ex
          Log.error { "Menu[Linux]: failed to set window menu: #{ex.message}" }
        end

        # GTK has no application-global menu bar (per-window only). When no window
        # is supplied we fall back to the last window a menu was attached to, if
        # any, so repeated `install` calls keep working.
        def global_menu=(menu_bar : ::NativeDesktop::MenuBar) : Nil
          if @@menu_window.null?
            Log.warn { "Menu[Linux]: no window available; menu bar attaches per-window on GTK" }
            return
          end
          set_window_menu(@@menu_window, menu_bar)
        end

        private def build_submenu(menu : ::NativeDesktop::Menu) : Void*
          submenu = LibGTKApplicationMenu.gtk_menu_new

          menu.entries.each do |item|
            case item
            in ::NativeDesktop::Menu
              nested_item = LibGTKApplicationMenu.gtk_menu_item_new_with_label(item.label)
              child = build_submenu(item)
              LibGTKApplicationMenu.gtk_menu_item_set_submenu(nested_item, child)
              LibGTKApplicationMenu.gtk_menu_shell_append(submenu, nested_item)
            in ::NativeDesktop::MenuSeparator
              sep = LibGTKApplicationMenu.gtk_separator_menu_item_new
              LibGTKApplicationMenu.gtk_menu_shell_append(submenu, sep)
            in ::NativeDesktop::MenuItem
              gtk_item =
                if item.checked
                  ci = LibGTKApplicationMenu.gtk_check_menu_item_new_with_label(item.label)
                  LibGTKApplicationMenu.gtk_check_menu_item_set_active(ci, 1)
                  ci
                else
                  LibGTKApplicationMenu.gtk_menu_item_new_with_label(item.label)
                end

              LibGTKApplicationMenu.gtk_widget_set_sensitive(gtk_item, item.enabled ? 1 : 0)

              if accel = item.accelerator
                attach_accelerator(gtk_item, accel)
              end

              idx = @@menu_actions.size
              @@menu_actions << item.action
              LibGObjectApplicationMenu.g_signal_connect_data(
                gtk_item,
                "activate".to_unsafe,
                ->(_widget : Void*, data : Void*) {
                  i = data.address.to_i64 - 1
                  if (cb = @@menu_actions[i]?) && cb
                    begin
                      cb.call
                    rescue ex
                      Log.error { "Menu[Linux]: click handler error: #{ex.message}" }
                    end
                  end
                  nil
                }.pointer,
                Pointer(Void).new((idx + 1).to_u64),
                Pointer(Void).null,
                0,
              )

              LibGTKApplicationMenu.gtk_menu_shell_append(submenu, gtk_item)
            end
          end

          submenu
        end

        private def attach_accelerator(widget : Void*, accel : String) : Nil
          gtk_accel = to_gtk_accel(accel)
          return if gtk_accel.empty?

          key = 0_u32
          mods = 0_u32
          LibGTKApplicationMenu.gtk_accelerator_parse(gtk_accel, pointerof(key), pointerof(mods))
          return if key == 0_u32

          LibGTKApplicationMenu.gtk_widget_add_accelerator(
            widget, "activate".to_unsafe, @@accel_group, key, mods, GTK_ACCEL_VISIBLE,
          )
        end

        # Translate an accelerator ("Cmd+Shift+O") into the GTK form
        # ("<Primary><Shift>o") understood by gtk_accelerator_parse.
        private def to_gtk_accel(accel : String) : String
          parts = accel.split("+").map(&.strip).reject(&.empty?)
          return "" if parts.empty?

          key_name = gtk_key_name(parts.last)
          return "" if key_name.empty?

          mods = String.build do |io|
            parts[0..-2].each do |part|
              case part.downcase
              when "cmd", "command", "meta", "super", "win" then io << "<Primary>"
              when "ctrl", "control"                        then io << "<Control>"
              when "alt", "option"                          then io << "<Alt>"
              when "shift"                                  then io << "<Shift>"
              end
            end
          end

          "#{mods}#{key_name}"
        end

        # Map a key token to a GDK key name (gdk_keyval_from_name).
        private def gtk_key_name(key : String) : String
          case key.downcase
          when "enter", "return" then "Return"
          when "tab"             then "Tab"
          when "space"           then "space"
          when "escape", "esc"   then "Escape"
          when "backspace"       then "BackSpace"
          when "delete"          then "Delete"
          when "left"            then "Left"
          when "right"           then "Right"
          when "up"              then "Up"
          when "down"            then "Down"
          when "home"            then "Home"
          when "end"             then "End"
          when "pageup"          then "Page_Up"
          when "pagedown"        then "Page_Down"
          when "f1"              then "F1"
          when "f2"              then "F2"
          when "f3"              then "F3"
          when "f4"              then "F4"
          when "f5"              then "F5"
          when "f6"              then "F6"
          when "f7"              then "F7"
          when "f8"              then "F8"
          when "f9"              then "F9"
          when "f10"             then "F10"
          when "f11"             then "F11"
          when "f12"             then "F12"
          else
            # Single letters/digits/punctuation use their lowercase character.
            key.size == 1 ? key.downcase : ""
          end
        end

        private def teardown : Nil
          unless @@menu_bar_widget.null?
            LibGTKApplicationMenu.gtk_widget_destroy(@@menu_bar_widget)
            @@menu_bar_widget = Pointer(Void).null
          end
          unless @@accel_group.null?
            LibGTKApplicationMenu.gtk_window_remove_accel_group(@@menu_window, @@accel_group) unless @@menu_window.null?
            @@accel_group = Pointer(Void).null
          end
        end

        # Check whether a GtkWidget is a GtkBox (or subclass) using the GType system.
        private def gtk_box?(widget : Void*) : Bool
          return false if widget.null?
          # g_type_check_instance_is_a checks the full GType hierarchy
          box_type = LibGTKApplicationMenu.gtk_box_get_type
          LibGObjectApplicationMenu.g_type_check_instance_is_a(widget, box_type) != 0
        rescue
          false
        end
      end
    end
  end
end
