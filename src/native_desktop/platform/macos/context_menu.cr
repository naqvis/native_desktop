require "log"
require "./objc_runtime"

module NativeDesktop
  module Platform
    module MacOS
      module ContextMenu
        extend self

        Log = ::Log.for("ContextMenu[macOS]")

        @@context_menu_target : Void* = Pointer(Void).null
        @@item_map : Hash(Int64, String) = {} of Int64 => String
        @@next_tag : Int64 = 1_i64
        @@context_result : String? = nil

        def available? : Bool
          true
        end

        def show_context_menu(items : Array(NativeDesktop::ContextMenuItem), x : Int32, y : Int32, window_ptr : Void*) : String?
          MacOS::ObjCRuntime.with_autorelease_pool do
            ensure_context_menu_target
            o = MacOS::ObjCRuntime

            menu = o.msg(o.msg(o.get_class("NSMenu"), "alloc"), "initWithTitle:", o.nsstring("ContextMenu"))
            o.msg_int(menu, "setAutoenablesItems:", 0_i64)

            @@item_map.clear
            @@next_tag = 1_i64
            @@context_result = nil

            build_items(items, menu, o)

            # Use NSEvent.mouseLocation for screen coordinates — avoids all the
            # coordinate-space confusion between the webview, content view, window,
            # and screen.
            mouse_loc = o.msg_point(o.get_class("NSEvent"), "mouseLocation")
            o.msg_void(menu, "popUpMenuPositioningItem:atLocation:inView:", Pointer(Void).null, mouse_loc.x, mouse_loc.y, Pointer(Void).null)

            result = @@context_result
            @@context_result = nil
            result
          end
        rescue ex
          Log.error { "#{ex.message}" }
          nil
        end

        private def build_items(items : Array(NativeDesktop::ContextMenuItem), parent_menu : Void*, o) : Nil
          items.each do |item|
            case item.type
            in .separator?
              sep = o.msg(o.get_class("NSMenuItem"), "separatorItem")
              o.msg_void(parent_menu, "addItem:", sep)
            in .normal?, .checkbox?
              if sub = item.submenu
                ns_item = o.msg(o.get_class("NSMenuItem"), "alloc")
                ns_item = o.msg_init_menu_item_no_action(
                  ns_item,
                  "initWithTitle:action:keyEquivalent:",
                  o.nsstring(item.label),
                  o.nsstring(""),
                )
                submenu = o.msg(o.msg(o.get_class("NSMenu"), "alloc"), "initWithTitle:", o.nsstring(""))
                o.msg_int(submenu, "setAutoenablesItems:", 0_i64)
                build_items(sub, submenu, o)
                o.msg_void(ns_item, "setSubmenu:", submenu)
              else
                ns_item = o.msg(o.get_class("NSMenuItem"), "alloc")
                ns_item = o.msg_init_menu_item_no_action(
                  ns_item,
                  "initWithTitle:action:keyEquivalent:",
                  o.nsstring(item.label),
                  o.nsstring(""),
                )
                tag = @@next_tag
                @@next_tag += 1_i64
                @@item_map[tag] = item.id
                o.msg_int(ns_item, "setTag:", tag)
                o.msg_void(ns_item, "setTarget:", @@context_menu_target)
                o.msg_void(ns_item, "setAction:", o.sel("contextMenuItemClicked:"))
              end
              o.msg_int(ns_item, "setEnabled:", item.enabled? ? 1_i64 : 0_i64)
              o.msg_int(ns_item, "setState:", item.checked? ? 1_i64 : 0_i64)
              o.msg_void(parent_menu, "addItem:", ns_item)
            end
          end
        end

        private def ensure_context_menu_target : Nil
          unless @@context_menu_target.null?
            return
          end

          ns_object = MacOS::ObjCRuntime.get_class("NSObject")
          cls = LibNativeDesktopObjCRuntime.allocate_class_pair(ns_object, "CrystKitContextMenuTarget", 0)

          unless cls.null?
            sel = MacOS::ObjCRuntime.sel("contextMenuItemClicked:")
            imp = ->(_self : Void*, _cmd : Void*, sender : Void*) {
              handle_context_click(sender)
            }
            LibNativeDesktopObjCRuntime.add_method(cls, sel, imp.pointer, "v@:@")
            LibNativeDesktopObjCRuntime.register_class_pair(cls)
          end

          cls = MacOS::ObjCRuntime.get_class("CrystKitContextMenuTarget")
          @@context_menu_target = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.msg(cls, "alloc"), "init") unless cls.null?
        end

        private def handle_context_click(sender : Void*) : Nil
          MacOS::ObjCRuntime.with_autorelease_pool do
            tag = MacOS::ObjCRuntime.msg_long(sender, "tag")
            @@context_result = @@item_map[tag]?
          end
        rescue ex
          Log.error { "click handler: #{ex.message}" }
        end
      end
    end
  end
end
