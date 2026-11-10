require "log"
require "./objc_runtime"

module NativeDesktop
  module Platform
    module MacOS
      module Tray
        extend self

        NS_MOD_SHIFT   = 1_u64 << 17
        NS_MOD_CONTROL = 1_u64 << 18
        NS_MOD_OPTION  = 1_u64 << 19
        NS_MOD_COMMAND = 1_u64 << 20

        @@status_item : Void* = Pointer(Void).null
        @@menu : Void* = Pointer(Void).null
        @@menu_delegate : Void* = Pointer(Void).null

        # Handlers indexed by menu item tag (set during set_menu)
        # Avoids all intermediate ring buffer / poll fiber machinery which
        # causes SIGSEGV/SIGBUS when handlers invoke nested Cocoa event
        # loops (e.g. via NSAlert runModal).
        @@handlers : Array(Proc(Nil)?) = [] of Proc(Nil)?

        # Click handler for direct status item button clicks (no menu).
        class_getter click_handler : Proc(Int32, Nil)? = nil

        def handlers
          @@handlers
        end

        def self.on_click(&block : Int32 ->) : Nil
          @@click_handler = block
        end

        # ObjC class for handling menu actions
        @@delegate_class : Void* = Pointer(Void).null
        @@delegate_class_registered = false

        # Create the ObjC delegate class that handles menu item actions
        private def ensure_delegate_class
          return if @@delegate_class_registered

          ns_object = ObjCRuntime.get_class("NSObject")
          @@delegate_class = LibNativeDesktopObjCRuntime.allocate_class_pair(ns_object, "NativeDesktopTrayDelegate", 0)

          if @@delegate_class.null?
            # Class might already exist from a previous run
            @@delegate_class = ObjCRuntime.get_class("NativeDesktopTrayDelegate")
            @@delegate_class_registered = true
            return
          end

          # Add the menuItemClicked: method
          # The callback receives (self, _cmd, sender) and extracts the tag.
          # Dispatches handlers DIRECTLY — no ring buffer, no poll fiber.
          callback = ->(_self_obj : Void*, _cmd : Void*, sender : Void*) : Void* {
            tag = ObjCRuntime.msg_long(sender, "tag").to_i32
            if tag >= 0 && tag < handlers.size
              if handler = handlers[tag]
                begin
                  handler.call
                rescue ex
                  Log.error { "Tray[macOS]: handler raised #{ex.class}: #{ex.message || ex.inspect}" }
                end
              end
            end
            Pointer(Void).null
          }

          # Method signature: v@:@ (void return, object self, selector, object arg)
          LibNativeDesktopObjCRuntime.add_method(
            @@delegate_class,
            ObjCRuntime.sel("menuItemClicked:"),
            callback.pointer,
            "v@:@"
          )

          # Add the trayClicked: method for direct status item button clicks
          tray_cb = ->(_self_obj : Void*, _cmd : Void*, _sender : Void*) : Void* {
            if handler = click_handler
              begin
                handler.call(0)
              rescue ex
                Log.error { "Tray[macOS]: click handler raised #{ex.class}: #{ex.message || ex.inspect}" }
              end
            end
            Pointer(Void).null
          }

          LibNativeDesktopObjCRuntime.add_method(
            @@delegate_class,
            ObjCRuntime.sel("trayClicked:"),
            tray_cb.pointer,
            "v@:@"
          )

          LibNativeDesktopObjCRuntime.register_class_pair(@@delegate_class)
          @@delegate_class_registered = true
        end

        def create(app_id : String, icon : ::NativeDesktop::TrayIcon?, tooltip : String?) : Nil
          Log.info { "Tray[macOS]: creating tray for '#{app_id}'" }

          # Ensure NSApplication is initialized

          # Ensure delegate class exists
          ensure_delegate_class

          ObjCRuntime.with_autorelease_pool do
            ns_status_bar_class = ObjCRuntime.get_class("NSStatusBar")
            status_bar = ObjCRuntime.msg(ns_status_bar_class, "systemStatusBar")

            if status_bar.null?
              raise "Failed to get system status bar"
            end

            status_item = ObjCRuntime.msg_float(status_bar, "statusItemWithLength:", -1.0_f64)

            if status_item.null?
              raise "Failed to create status item"
            end

            ObjCRuntime.msg(status_item, "retain")
            @@status_item = status_item

            # Create delegate instance
            delegate = ObjCRuntime.msg(ObjCRuntime.msg(@@delegate_class, "alloc"), "init")
            ObjCRuntime.msg(delegate, "retain")
            @@menu_delegate = delegate

            button = ObjCRuntime.msg(@@status_item, "button")

            if button.null?
              Log.warn { "Tray[macOS]: status item button is null" }
            else
              image = nsimage_from_source(icon)

              if image.null?
                Log.warn { "Tray[macOS]: failed to load icon" }
              else
                ObjCRuntime.msg(button, "setImage:", image)
              end

              if t = tooltip
                ObjCRuntime.msg(button, "setToolTip:", ObjCRuntime.nsstring(t))
              end

              # Wire button action to delegate for direct click support
              ObjCRuntime.msg_void(button, "setTarget:", @@menu_delegate)
              ObjCRuntime.msg_void(button, "setAction:", ObjCRuntime.sel("trayClicked:"))
            end
            Log.info { "Tray[macOS]: created status item for '#{app_id}'" }
          end
        rescue ex
          Log.error { "Tray[macOS]: create failed: #{ex.message}" }
          @@status_item = Pointer(Void).null
          raise Error.new("Failed to create system tray: #{ex.message}", :tray_create_failed)
        end

        def update_icon(icon : ::NativeDesktop::TrayIcon) : Nil
          item = @@status_item
          return if item.null?

          begin
            ObjCRuntime.with_autorelease_pool do
              image = nsimage_from_source(icon)
              return if image.null?
              button = ObjCRuntime.msg(item, "button")
              return if button.null?
              ObjCRuntime.msg(button, "setImage:", image)
            end
          rescue ex
            Log.warn { "Tray[macOS]: update_icon failed: #{ex.message}" }
          end
        end

        def tooltip=(text : String) : Nil
          item = @@status_item
          if item.null?
            Log.warn { "Tray[macOS]: set_tooltip called but status_item is null" }
            return
          end

          begin
            ObjCRuntime.with_autorelease_pool do
              button = ObjCRuntime.msg(item, "button")
              if button.null?
                Log.warn { "Tray[macOS]: set_tooltip - button is null" }
                return
              end
              ObjCRuntime.msg(button, "setToolTip:", ObjCRuntime.nsstring(text))
            end
          rescue ex
            Log.warn { "Tray[macOS]: set_tooltip failed: #{ex.message}" }
          end
        end

        # items: Array of {id, label, type_int, enabled_int, checked_int, parent_id}
        #        parent_id is empty string for top-level items.
        # callbacks: Hash mapping item id → Proc(Nil) handler
        def set_menu(items : Array(PlatformTrayMenuEntry), callbacks : Hash(String, Proc(Nil))) : Nil
          item = @@status_item
          if item.null?
            Log.warn { "Tray[macOS]: set_menu called but status_item is null" }
            return
          end

          handlers = Array(Proc(Nil)?).new(items.size) { nil }
          items.each_with_index do |entry, idx|
            handlers[idx] = callbacks[entry[:id]]? unless entry[:type] == 3
          end
          @@handlers = handlers

          # Build parent → children mapping preserving insertion order
          children_of = {} of String => Array(PlatformTrayMenuEntry)
          items.each do |entry|
            children_of[entry[:parent_id]] ||= [] of PlatformTrayMenuEntry
            children_of[entry[:parent_id]] << entry
          end

          # Map item id → its index in the flat items list (used for tags)
          id_to_index = {} of String => Int32
          items.each_with_index { |entry, idx| id_to_index[entry[:id]] = idx }

          begin
            ObjCRuntime.with_autorelease_pool do
              unless @@menu.null?
                ObjCRuntime.msg(@@menu, "release")
              end

              menu = build_nsmenu("", children_of, id_to_index)
              @@menu = menu

              ObjCRuntime.msg(item, "setMenu:", menu)
              Log.info { "Tray[macOS]: menu set with #{items.size} items" }
            end
          rescue ex
            Log.warn { "Tray[macOS]: set_menu failed: #{ex.message}" }
          end
        end

        # Recursively build an NSMenu for items whose parent_id matches.
        # Tags are set from id_to_index to match the handlers array position.
        private def build_nsmenu(parent_id : String, children_of : Hash(String, Array(PlatformTrayMenuEntry)), id_to_index : Hash(String, Int32)) : Void*
          menu = ObjCRuntime.msg(
            ObjCRuntime.msg(ObjCRuntime.get_class("NSMenu"), "alloc"),
            "initWithTitle:",
            ObjCRuntime.nsstring("")
          )
          ObjCRuntime.msg(menu, "retain")
          ObjCRuntime.msg_bool(menu, "setAutoenablesItems:", 0_i64)

          children_of.fetch(parent_id, [] of PlatformTrayMenuEntry).each do |entry|
            menu_item = if entry[:type] == 3
                          ObjCRuntime.msg(ObjCRuntime.get_class("NSMenuItem"), "separatorItem")
                        else
                          key_equiv, mods = parse_accelerator(entry[:accelerator]?)
                          mi = ObjCRuntime.msg_init_menu_item(
                            ObjCRuntime.msg(ObjCRuntime.get_class("NSMenuItem"), "alloc"),
                            "initWithTitle:action:keyEquivalent:",
                            ObjCRuntime.nsstring(entry[:label]),
                            "menuItemClicked:",
                            ObjCRuntime.nsstring(key_equiv),
                          )

                          ObjCRuntime.msg(mi, "setTarget:", @@menu_delegate)
                          ObjCRuntime.msg_bool(mi, "setEnabled:", entry[:enabled] != 0 ? 1_i64 : 0_i64)
                          if entry[:type] == 1 || entry[:type] == 2
                            ObjCRuntime.msg_bool(mi, "setState:", entry[:checked] != 0 ? 1_i64 : 0_i64)
                          end
                          ObjCRuntime.msg_bool(mi, "setTag:", id_to_index.fetch(entry[:id], 0).to_i64)
                          if mods != 0
                            ObjCRuntime.msg_int(mi, "setKeyEquivalentModifierMask:", mods.to_i64)
                          end

                          mi
                        end

            if children_of.has_key?(entry[:id])
              submenu = build_nsmenu(entry[:id], children_of, id_to_index)
              ObjCRuntime.msg(menu_item, "setSubmenu:", submenu)
            end

            ObjCRuntime.msg(menu, "addItem:", menu_item)
          end

          menu
        end

        private def parse_accelerator(accelerator : String?) : {String, UInt64}
          return {"", 0_u64} unless accelerator
          parts = accelerator.split('+').map(&.strip).reject(&.empty?)
          return {"", 0_u64} if parts.empty?

          modifiers = 0_u64
          parts[0..-2].each do |part|
            case part.downcase
            when "cmd", "command", "meta", "super", "win" then modifiers |= NS_MOD_COMMAND
            when "ctrl", "control"                        then modifiers |= NS_MOD_CONTROL
            when "alt", "option"                          then modifiers |= NS_MOD_OPTION
            when "shift"                                  then modifiers |= NS_MOD_SHIFT
            end
          end
          {key_equivalent(parts.last), modifiers}
        end

        private def key_equivalent(key : String) : String
          case key.downcase
          when "tab"             then "\t"
          when "enter", "return" then "\r"
          when "space"           then " "
          when "escape", "esc"   then "\e"
          when "backspace"       then "\u{8}"
          when "delete"          then "\u{7F}"
          when "left"            then "\u{F702}"
          when "right"           then "\u{F703}"
          when "up"              then "\u{F700}"
          when "down"            then "\u{F701}"
          when "home"            then "\u{F729}"
          when "end"             then "\u{F72B}"
          when "pageup"          then "\u{F72C}"
          when "pagedown"        then "\u{F72D}"
          when "f1"              then "\u{F704}"
          when "f2"              then "\u{F705}"
          when "f3"              then "\u{F706}"
          when "f4"              then "\u{F707}"
          when "f5"              then "\u{F708}"
          when "f6"              then "\u{F709}"
          when "f7"              then "\u{F70A}"
          when "f8"              then "\u{F70B}"
          when "f9"              then "\u{F70C}"
          when "f10"             then "\u{F70D}"
          when "f11"             then "\u{F70E}"
          when "f12"             then "\u{F70F}"
          else                        key.downcase
          end
        end

        def destroy : Nil
          return if @@status_item.null?

          item = @@status_item
          menu = @@menu
          delegate = @@menu_delegate
          @@status_item = Pointer(Void).null
          @@menu = Pointer(Void).null
          @@menu_delegate = Pointer(Void).null
          @@handlers = [] of Proc(Nil)?

          begin
            ObjCRuntime.with_autorelease_pool do
              status_bar = ObjCRuntime.msg(ObjCRuntime.get_class("NSStatusBar"), "systemStatusBar")
              unless status_bar.null?
                ObjCRuntime.msg(status_bar, "removeStatusItem:", item)
              end
              ObjCRuntime.msg(item, "release")
              ObjCRuntime.msg(menu, "release") unless menu.null?
              ObjCRuntime.msg(delegate, "release") unless delegate.null?
            end
          rescue ex
            Log.warn { "Tray[macOS]: destroy failed: #{ex.message}" }
          end
        end

        private def nsimage_from_file(path : String) : Void*
          ObjCRuntime.msg(
            ObjCRuntime.msg(ObjCRuntime.get_class("NSImage"), "alloc"),
            "initWithContentsOfFile:",
            ObjCRuntime.nsstring(path)
          )
        end

        private def nsimage_from_bytes(bytes : Bytes) : Void*
          data = ObjCRuntime.msg_data_with_bytes(
            ObjCRuntime.get_class("NSData"),
            "dataWithBytes:length:",
            bytes.to_unsafe.as(Void*),
            bytes.size.to_u64
          )
          return Pointer(Void).null if data.null?
          ObjCRuntime.msg(
            ObjCRuntime.msg(ObjCRuntime.get_class("NSImage"), "alloc"),
            "initWithData:",
            data
          )
        end

        # Map a theme name to an NSImage. Tries SF Symbols
        # (systemSymbolName:withConfiguration:) on 10.14+, falls back to
        # imageNamed: for legacy named images. Returns null if neither
        # resolves.
        private def nsimage_from_theme(name : String) : Void*
          symbol = ObjCRuntime.msg(
            ObjCRuntime.get_class("NSImage"),
            "systemSymbolName:withConfiguration:",
            ObjCRuntime.nsstring(name),
            Pointer(Void).null
          )
          return symbol unless symbol.null?
          ObjCRuntime.msg(ObjCRuntime.get_class("NSImage"), "imageNamed:", ObjCRuntime.nsstring(name))
        end

        # Dispatch an IconSource to the right nsimage_* helper.
        private def nsimage_from_source(icon : ::NativeDesktop::TrayIcon?) : Void*
          return Pointer(Void).null unless icon
          if b = icon.bytes
            nsimage_from_bytes(b)
          elsif n = icon.name
            nsimage_from_theme(n)
          else
            Pointer(Void).null
          end
        end
      end
    end
  end
end
