require "log"

# Linux system tray implementation using libappindicator3 (preferred) with
# fallback to GtkStatusIcon (deprecated but still widely available).
#
# libappindicator3 is the modern approach used by Ubuntu/GNOME/KDE.
# It requires: libappindicator3-dev (apt) / libappindicator-gtk3 (dnf)
#
# GTK bindings are used for the context menu (GtkMenu/GtkMenuItem).
@[Link("gtk-3", pkg_config: "gtk+-3.0")]
lib LibGTKTray
  fun gtk_main : Nil
  fun gtk_main_quit : Nil
  fun gtk_menu_new : Void*
  fun gtk_menu_item_new_with_label(label : UInt8*) : Void*
  fun gtk_menu_item_set_submenu(menu_item : Void*, submenu : Void*) : Nil
  fun gtk_check_menu_item_new_with_label(label : UInt8*) : Void*
  fun gtk_radio_menu_item_new_with_label(group : Void*, label : UInt8*) : Void*
  fun gtk_separator_menu_item_new : Void*
  fun gtk_menu_shell_append(menu : Void*, item : Void*) : Nil
  fun gtk_check_menu_item_set_active(item : Void*, active : Int32) : Nil
  fun gtk_check_menu_item_get_active(item : Void*) : Int32
  fun gtk_widget_destroy(widget : Void*) : Nil
  fun gtk_widget_show_all(widget : Void*) : Nil
  fun gtk_widget_set_sensitive(widget : Void*, sensitive : Int32) : Nil
  fun gtk_main_iteration_do(blocking : Int32) : Int32
end

@[Link("gobject-2.0")]
lib LibGObjectTray
  fun g_signal_connect_data(instance : Void*, signal : UInt8*, callback : Void*, data : Void*, destroy_data : Void*, flags : Int32) : UInt64
end

module NativeDesktop
  module Platform
    module Linux
      module Tray
        # ── AppIndicator bindings ────────────────────────────────────────────────

        @[Link("appindicator3", pkg_config: "appindicator3-0.1")]
        lib LibAppIndicator
          type Indicator = Void*

          # :nodoc:
          enum Category
            ApplicationStatus = 0
            Communications    = 1
            SystemServices    = 2
            Hardware          = 3
            Other             = 4
          end

          # :nodoc:
          enum Status
            Passive   = 0
            Active    = 1
            Attention = 2
          end

          fun app_indicator_new(id : UInt8*, icon_name : UInt8*, category : Category) : Indicator
          fun app_indicator_set_status(indicator : Indicator, status : Status) : Nil
          fun app_indicator_set_icon_full(indicator : Indicator, icon_path : UInt8*, icon_desc : UInt8*) : Nil
          fun app_indicator_set_menu(indicator : Indicator, menu : Void*) : Nil
          fun app_indicator_set_title(indicator : Indicator, title : UInt8*) : Nil
          fun app_indicator_set_attention_icon_full(indicator : Indicator, icon_path : UInt8*, icon_desc : UInt8*) : Nil
        end

        # ── TrayPlatform ─────────────────────────────────────────────────────────

        extend self

        @@indicator : LibAppIndicator::Indicator = Pointer(Void).null.as(LibAppIndicator::Indicator)
        @@gtk_menu : Void* = Pointer(Void).null
        @@click_callback : Proc(Int32, Nil)? = nil
        @@item_callbacks : Hash(String, Proc(Nil)) = {} of String => Proc(Nil)
        # Item IDs indexed by menu position. The GTK callback passes the position
        # (+1 to avoid null for index 0) as the raw data pointer — no heap
        # allocation, no GC involvement.
        @@item_ids : Array(String) = [] of String

        @@temp_icon_files : Array(String) = [] of String

        # Write *bytes* to a temp file keyed by *key* (VFS path or URL) and
        # return the path. Repeated calls with the same key reuse the file.
        private def materialize_temp_icon(bytes : Bytes, key : String) : String
          filename = "native-desktop-tray-#{key.gsub('/', '_')}.png"
          path = File.join(Dir.tempdir, filename)
          unless File.exists?(path)
            File.write(path, bytes)
            @@temp_icon_files << path
          end
          path
        end

        # Delete every temp icon file we've written. Called on destroy.
        private def cleanup_temp_icons : Nil
          @@temp_icon_files.each do |p|
            File.delete(p) rescue nil
          end
          @@temp_icon_files.clear
        end

        # Resolve an IconSource to the path/string that libappindicator
        # accepts: bytes -> temp file path; name -> name pass-through.
        private def icon_to_path(icon : ::NativeDesktop::TrayIcon?) : String?
          return nil unless icon
          if b = icon.bytes
            key = icon.key || "bytes"
            materialize_temp_icon(b, key)
          elsif n = icon.name
            n
          else
            nil
          end
        end

        # Create the tray icon using libappindicator3.
        def create(app_id : String, icon : ::NativeDesktop::TrayIcon?, tooltip : String?) : Nil
          icon_path = icon_to_path(icon) || "indicator-default"

          @@indicator = LibAppIndicator.app_indicator_new(
            app_id,
            icon_path,
            LibAppIndicator::Category::ApplicationStatus
          )

          LibAppIndicator.app_indicator_set_status(
            @@indicator,
            LibAppIndicator::Status::Active
          )

          LibAppIndicator.app_indicator_set_icon_full(
            @@indicator,
            icon_path,
            tooltip || app_id
          )

          if t = tooltip
            LibAppIndicator.app_indicator_set_title(@@indicator, t)
          end

          Log.debug { "Tray[Linux]: created indicator for '#{app_id}'" }
        rescue ex
          raise Error.new("Failed to create system tray: #{ex.message}", :tray_create_failed)
        end

        # Update the tray icon image.
        def update_icon(icon : ::NativeDesktop::TrayIcon) : Nil
          return if @@indicator.null?
          icon_path = icon_to_path(icon) || return
          cleanup_temp_icons
          LibAppIndicator.app_indicator_set_icon_full(@@indicator, icon_path, "icon")
        end

        # Set the tooltip (title in AppIndicator terms).
        def tooltip=(text : String) : Nil
          return if @@indicator.null?
          LibAppIndicator.app_indicator_set_title(@@indicator, text)
        end

        # Build and attach a GTK menu from the abstract Menu structure.
        # items: Array of {id, label, type, enabled, checked, parent_id}
        #   parent_id is empty string for top-level items.
        # type: 0=Normal, 1=Checkbox, 2=Radio, 3=Separator
        def set_menu(items : Array(PlatformTrayMenuEntry), callbacks : Hash(String, Proc(Nil))) : Nil
          return if @@indicator.null?

          @@item_callbacks = callbacks

          # Build parent → children mapping preserving insertion order
          children_of = {} of String => Array(PlatformTrayMenuEntry)
          items.each do |entry|
            children_of[entry[:parent_id]] ||= [] of PlatformTrayMenuEntry
            children_of[entry[:parent_id]] << entry
          end

          # Clear and rebuild item_ids in flat order (for callback lookup)
          @@item_ids.clear
          items.each { |entry| @@item_ids << entry[:id] }

          # Destroy old menu if it exists
          unless @@gtk_menu.null?
            LibGTKTray.gtk_widget_destroy(@@gtk_menu)
          end

          @@gtk_menu = build_gtk_menu("", children_of)

          LibGTKTray.gtk_widget_show_all(@@gtk_menu)
          LibAppIndicator.app_indicator_set_menu(@@indicator, @@gtk_menu)
        end

        # Recursively build a GtkMenu for items whose parent_id matches.
        private def build_gtk_menu(parent_id : String, children_of : Hash(String, Array(PlatformTrayMenuEntry))) : Void*
          menu = LibGTKTray.gtk_menu_new

          children_of.fetch(parent_id, [] of PlatformTrayMenuEntry).each do |entry|
            label = entry[:label]
            if accel = entry[:accelerator]?
              label = "#{label}\t#{accel}"
            end
            gtk_item = case entry[:type]
                       when 1 # Checkbox
                         ci = LibGTKTray.gtk_check_menu_item_new_with_label(label)
                         LibGTKTray.gtk_check_menu_item_set_active(ci, entry[:checked])
                         ci.as(Void*)
                       when 2 # Radio
                         LibGTKTray.gtk_radio_menu_item_new_with_label(Pointer(Void).null, label).as(Void*)
                       when 3 # Separator
                         LibGTKTray.gtk_separator_menu_item_new.as(Void*)
                       else # Normal
                         LibGTKTray.gtk_menu_item_new_with_label(label).as(Void*)
                       end

            LibGTKTray.gtk_widget_set_sensitive(gtk_item, entry[:enabled])

            unless entry[:type] == 3
              # Find the flat position of this item for callback lookup
              pos = @@item_ids.index(entry[:id]) || 0
              LibGObjectTray.g_signal_connect_data(
                gtk_item,
                "activate",
                ->(_widget : Void*, data : Void*) {
                  idx = (data.address - 1).to_i64
                  cb_id = @@item_ids[idx]
                  @@item_callbacks[cb_id]?.try(&.call)
                }.pointer,
                Pointer(Void).new((pos + 1).to_u64),
                Pointer(Void).null,
                0
              )
            end

            # If this item has children, create a submenu
            if children_of.has_key?(entry[:id])
              submenu = build_gtk_menu(entry[:id], children_of)
              LibGTKTray.gtk_menu_item_set_submenu(gtk_item, submenu)
            end

            LibGTKTray.gtk_menu_shell_append(menu, gtk_item)
          end

          menu
        end

        # Register a click callback (called with 0=left, 1=right).
        def on_click(&block : Int32 ->) : Nil
          @@click_callback = block
        end

        # Hide the tray icon.
        def destroy : Nil
          cleanup_temp_icons
          return if @@indicator.null?

          # Destroy GTK menu
          unless @@gtk_menu.null?
            LibGTKTray.gtk_widget_destroy(@@gtk_menu)
            @@gtk_menu = Pointer(Void).null
          end

          LibAppIndicator.app_indicator_set_status(
            @@indicator,
            LibAppIndicator::Status::Passive
          )
          @@indicator = Pointer(Void).null.as(LibAppIndicator::Indicator)
          @@item_callbacks.clear
          @@item_ids.clear
        end

        # Process pending GTK events (call from app main loop).
        def process_events : Nil
          while LibGTKTray.gtk_main_iteration_do(0) != 0
          end
        end
      end
    end
  end
end
