require "log"
require "./objc_runtime"

module NativeDesktop
  module Platform
    module MacOS
      module Menu
        extend self

        # Native macOS menu implementation using Cocoa's NSMenu / NSMenuItem.
        #
        # Menu item clicks are routed through a dynamically-registered
        # `NativeDesktopMenuTarget` Objective-C class. Each NSMenuItem is given an
        # integer `tag`; the target's `menuItemClicked:` method reads the tag
        # of the sender and dispatches to the matching Crystal callback.

        # NSEventModifierFlags (NSEvent.h)
        NS_MOD_SHIFT   = 1_u64 << 17
        NS_MOD_CONTROL = 1_u64 << 18
        NS_MOD_OPTION  = 1_u64 << 19
        NS_MOD_COMMAND = 1_u64 << 20

        @@menu_target : Void* = Pointer(Void).null
        @@menu_target_class_registered = false
        @@callbacks : Hash(Int64, Proc(Nil)) = {} of Int64 => Proc(Nil)
        @@next_tag : Int64 = 1_i64

        # Set the global application menu bar from a MenuBar definition.
        def global_menu=(menu_bar : ::NativeDesktop::MenuBar) : Nil
          ObjCRuntime.with_autorelease_pool do
            ensure_menu_target

            @@callbacks.clear
            @@next_tag = 1_i64

            ns_app = ObjCRuntime.msg(ObjCRuntime.get_class("NSApplication"), "sharedApplication")
            main_menu = create_nsmenu(menu_bar)
            ObjCRuntime.msg(ns_app, "setMainMenu:", main_menu)
          end
          Log.debug { "Menu[macOS]: installed application menu with #{menu_bar.menus.size} top-level menus" }
        rescue ex
          Log.error { "Failed to set global menu: #{ex.message}" }
        end

        # On macOS the menu bar is always application-global, so attaching to a
        # specific window simply installs the global menu.
        def set_window_menu(window_ptr : Void*, menu_bar : ::NativeDesktop::MenuBar) : Nil
          return if window_ptr.null?
          self.global_menu = menu_bar
        rescue ex
          Log.error { "Failed to set window menu: #{ex.message}" }
        end

        private def create_nsmenu(menu_bar : ::NativeDesktop::MenuBar) : Void*
          o = ObjCRuntime
          menu_ptr = o.msg(o.msg(o.get_class("NSMenu"), "alloc"), "initWithTitle:", o.nsstring("MainMenu"))
          # Disable auto-enabling so our explicit `setEnabled:` flags are honoured.
          o.msg_int(menu_ptr, "setAutoenablesItems:", 0_i64)

          menu_bar.menus.each do |menu|
            item = create_top_level(menu)
            o.msg_void(menu_ptr, "addItem:", item) unless item.null?
          end

          menu_ptr
        end

        # Build a top-level NSMenuItem that owns a submenu (File, Edit, …).
        # This is also used recursively for nested submenus.
        private def create_top_level(menu : ::NativeDesktop::Menu) : Void*
          o = ObjCRuntime
          title = o.nsstring(menu.label)

          menu_item = o.msg(o.msg(o.get_class("NSMenuItem"), "alloc"), "init")
          o.msg_void(menu_item, "setTitle:", title)

          submenu = o.msg(o.msg(o.get_class("NSMenu"), "alloc"), "initWithTitle:", title)
          o.msg_int(submenu, "setAutoenablesItems:", 0_i64)

          populate(submenu, menu)

          o.msg_void(menu_item, "setSubmenu:", submenu)
          menu_item
        end

        # Add all of a menu's children (items, separators, nested submenus) to an
        # NSMenu.
        private def populate(submenu : Void*, menu : ::NativeDesktop::Menu) : Nil
          o = ObjCRuntime
          menu.entries.each do |item|
            case item
            in ::NativeDesktop::Menu
              nested = create_top_level(item)
              o.msg_void(submenu, "addItem:", nested) unless nested.null?
            in ::NativeDesktop::MenuSeparator
              sep = o.msg(o.get_class("NSMenuItem"), "separatorItem")
              o.msg_void(submenu, "addItem:", sep)
            in ::NativeDesktop::MenuItem
              leaf = build_leaf(item)
              o.msg_void(submenu, "addItem:", leaf) unless leaf.null?
            end
          end
        end

        private def build_leaf(item : ::NativeDesktop::MenuItem) : Void*
          o = ObjCRuntime
          key_equiv, mods = parse_accelerator(item.accelerator)

          ns_item = o.msg(o.get_class("NSMenuItem"), "alloc")
          ns_item = o.msg_init_menu_item_no_action(
            ns_item, "initWithTitle:action:keyEquivalent:",
            o.nsstring(item.label), o.nsstring(key_equiv),
          )

          o.msg_uint(ns_item, "setKeyEquivalentModifierMask:", mods) unless key_equiv.empty?

          # Wire the click target/action and tag for dispatch.
          tag = @@next_tag
          @@next_tag += 1_i64
          o.msg_int(ns_item, "setTag:", tag)
          o.msg_void(ns_item, "setTarget:", @@menu_target)
          o.msg_void(ns_item, "setAction:", o.sel("menuItemClicked:"))

          o.msg_int(ns_item, "setEnabled:", item.enabled ? 1_i64 : 0_i64)
          o.msg_int(ns_item, "setState:", item.checked ? 1_i64 : 0_i64)

          if action = item.action
            @@callbacks[tag] = action
          end

          ns_item
        end

        # Parse an accelerator like "Cmd+Shift+Z" into an NSMenuItem key
        # equivalent ("z") plus an NSEventModifierFlags mask.
        def parse_accelerator(accel : String?) : {String, UInt64}
          return {"", 0_u64} unless accel
          parts = accel.split("+").map(&.strip).reject(&.empty?)
          return {"", 0_u64} if parts.empty?

          key_str = parts.last
          mods = 0_u64
          parts[0..-2].each do |part|
            case part.downcase
            when "cmd", "command", "meta", "super", "win" then mods |= NS_MOD_COMMAND
            when "ctrl", "control"                        then mods |= NS_MOD_CONTROL
            when "alt", "option"                          then mods |= NS_MOD_OPTION
            when "shift"                                  then mods |= NS_MOD_SHIFT
            end
          end

          {key_equivalent_for(key_str), mods}
        end

        # Map a key name to the NSMenuItem key-equivalent character.
        # Function/navigation keys use the Unicode values Cocoa expects.
        def key_equivalent_for(key : String) : String
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
          else
            # Single characters (letters, digits, punctuation) use the lowercase
            # form; Shift is conveyed via the modifier mask.
            key.downcase
          end
        end

        # Lazily register the NativeDesktopMenuTarget ObjC class and instantiate one
        # shared target object.
        private def ensure_menu_target : Nil
          unless @@menu_target_class_registered
            ns_object = ObjCRuntime.get_class("NSObject")
            cls = LibNativeDesktopObjCRuntime.allocate_class_pair(ns_object, "NativeDesktopMenuTarget", 0)

            unless cls.null?
              sel = ObjCRuntime.sel("menuItemClicked:")
              imp = ->(_self : Void*, _cmd : Void*, sender : Void*) {
                handle_click(sender)
              }
              LibNativeDesktopObjCRuntime.add_method(cls, sel, imp.pointer, "v@:@")
              LibNativeDesktopObjCRuntime.register_class_pair(cls)
            end

            @@menu_target_class_registered = true
          end

          if @@menu_target.null?
            cls = ObjCRuntime.get_class("NativeDesktopMenuTarget")
            @@menu_target = ObjCRuntime.msg(ObjCRuntime.msg(cls, "alloc"), "init") unless cls.null?
          end
        end

        private def handle_click(sender : Void*) : Nil
          ObjCRuntime.with_autorelease_pool do
            tag = ObjCRuntime.msg_long(sender, "tag")
            @@callbacks[tag]?.try(&.call)
          end
        rescue ex
          Log.error { "Menu[macOS]: click handler error: #{ex.message}" }
        end
      end
    end
  end
end
