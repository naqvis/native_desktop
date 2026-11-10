require "log"
require "./objc_runtime"

module NativeDesktop
  module Platform
    module MacOS
      module Toolbar
        extend self

        NSToolbarDisplayModeDefault      = 0_i64
        NSToolbarDisplayModeIconAndLabel = 1_i64
        NSToolbarDisplayModeIconOnly     = 2_i64
        NSToolbarDisplayModeLabelOnly    = 3_i64

        @@native : Void* = Pointer(Void).null
        @@toolbar : Void* = Pointer(Void).null
        @@delegate_instance : Void* = Pointer(Void).null
        @@toolbar_delegate_class_registered = false
        @@items : Array(::NativeDesktop::ToolbarItem) = [] of ::NativeDesktop::ToolbarItem
        @@actions : Hash(String, Proc(Nil)?) = {} of String => Proc(Nil)?
        @@view_map : Hash(Void*, String) = {} of Void* => String

        def register(native : Void*, _content : Void*?, feature : ::NativeDesktop::Toolbar) : Nil
          @@native = native
          rebuild_toolbar(feature.items, feature.style)
        end

        def update_items(items : Array(::NativeDesktop::ToolbarItem)) : Nil
          return if @@native.null?
          ObjCRuntime.with_autorelease_pool do
            rebuild_toolbar(items)
          end
        end

        def visible=(visible : Bool) : Nil
          return if @@toolbar.null?
          ObjCRuntime.with_autorelease_pool do
            o = ObjCRuntime
            o.msg_int(@@toolbar, "setVisible:", visible ? 1_i64 : 0_i64)
          end
        end

        def title=(title : String) : Nil
          return if @@toolbar.null?
          ObjCRuntime.with_autorelease_pool do
            o = ObjCRuntime
            o.msg(@@toolbar, "setDisplayMode:", NSToolbarDisplayModeDefault)
          end
        end

        private def rebuild_toolbar(items : Array(::NativeDesktop::ToolbarItem), style : ::NativeDesktop::ToolbarStyle = ::NativeDesktop::ToolbarStyle::Default) : Nil
          ObjCRuntime.with_autorelease_pool do
            o = ObjCRuntime
            return if @@native.null?

            if !@@toolbar.null?
              o.msg_void(@@native, "setToolbar:", Pointer(Void).null)
              o.msg_void(@@toolbar, "setDelegate:", Pointer(Void).null)
            end
            if !@@delegate_instance.null?
              o.msg_void(@@delegate_instance, "release")
            end

            @@items = items
            @@actions.clear
            items.each { |item| @@actions[item.id] = item.action }

            ensure_toolbar_delegate_class
            del_cls = ObjCRuntime.get_class("NativeDesktopToolbarDelegate")
            @@delegate_instance = o.msg(o.msg(del_cls, "alloc"), "init")

            tb = o.msg(
              o.msg(o.get_class("NSToolbar"), "alloc"),
              "initWithIdentifier:", ObjCRuntime.nsstring("NativeDesktopToolbar"),
            )

            o.msg_void(tb, "setDelegate:", @@delegate_instance)

            display = case style
                      when ::NativeDesktop::ToolbarStyle::Default     then NSToolbarDisplayModeIconAndLabel
                      when ::NativeDesktop::ToolbarStyle::Dark        then NSToolbarDisplayModeIconAndLabel
                      when ::NativeDesktop::ToolbarStyle::Light       then NSToolbarDisplayModeIconAndLabel
                      when ::NativeDesktop::ToolbarStyle::Transparent then NSToolbarDisplayModeIconAndLabel
                      else                                                 NSToolbarDisplayModeIconAndLabel
                      end
            o.msg_int(tb, "setDisplayMode:", display)
            o.msg_int(tb, "setAllowsUserCustomization:", 0_i64)
            o.msg_int(tb, "setAutosavesConfiguration:", 0_i64)
            o.msg_int(tb, "setShowsBaselineSeparator:", 1_i64)

            o.msg_void(@@native, "setToolbar:", tb)
            o.msg_int(@@native, "setShowsToolbarButton:", 0_i64)
            o.msg_void(tb, "validateVisibleItems")

            @@toolbar = tb
            Log.debug { "Toolbar[macOS]: rebuilt NSToolbar with #{@@items.size} items" }
          end
        end

        def cleanup : Nil
          ObjCRuntime.with_autorelease_pool do
            o = ObjCRuntime
            o.msg_void(@@native, "setToolbar:", Pointer(Void).null) unless @@native.null?
            o.msg_void(@@toolbar, "setDelegate:", Pointer(Void).null) unless @@toolbar.null?
            o.msg_void(@@delegate_instance, "release") unless @@delegate_instance.null?
          end
          @@native = Pointer(Void).null
          @@toolbar = Pointer(Void).null
          @@delegate_instance = Pointer(Void).null
          @@items.clear
          @@actions.clear
          @@view_map.clear
        end

        private def ensure_toolbar_delegate_class : Nil
          return if @@toolbar_delegate_class_registered

          ns_object = ObjCRuntime.get_class("NSObject")
          cls = LibNativeDesktopObjCRuntime.allocate_class_pair(ns_object, "NativeDesktopToolbarDelegate", 0)

          if cls.null?
            @@toolbar_delegate_class_registered = true
            return
          end

          add_item_for_identifier(cls)
          add_default_identifiers(cls)
          add_allowed_identifiers(cls)
          add_item_clicked(cls)

          LibNativeDesktopObjCRuntime.register_class_pair(cls)
          @@toolbar_delegate_class_registered = true
        end

        private def add_item_for_identifier(cls : Void*) : Nil
          sel = ObjCRuntime.sel("toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:")
          imp = ->(_self_obj : Void*, _cmd : Void*, _tb : Void*, id_str : Void*, _flag : Int64) : Void* {
            create_toolbar_item(id_str)
          }
          LibNativeDesktopObjCRuntime.add_method(cls, sel, imp.pointer, "@@:@@B")
        end

        private def add_default_identifiers(cls : Void*) : Nil
          sel = ObjCRuntime.sel("toolbarDefaultItemIdentifiers:")
          imp = ->(_self_obj : Void*, _cmd : Void*, _tb : Void*) : Void* {
            ids = @@items.map(&.id)
            ObjCRuntime.nsarray_from_strings(ids)
          }
          LibNativeDesktopObjCRuntime.add_method(cls, sel, imp.pointer, "@@:@")
        end

        private def add_allowed_identifiers(cls : Void*) : Nil
          sel = ObjCRuntime.sel("toolbarAllowedItemIdentifiers:")
          imp = ->(_self_obj : Void*, _cmd : Void*, _tb : Void*) : Void* {
            ids = @@items.map(&.id)
            ObjCRuntime.nsarray_from_strings(ids)
          }
          LibNativeDesktopObjCRuntime.add_method(cls, sel, imp.pointer, "@@:@")
        end

        private def add_item_clicked(cls : Void*) : Nil
          sel = ObjCRuntime.sel("toolbarItemClicked:")
          imp = ->(_self_obj : Void*, _cmd : Void*, sender : Void*) {
            handle_item_click(sender)
          }
          LibNativeDesktopObjCRuntime.add_method(cls, sel, imp.pointer, "v@:@")
        end

        private def create_toolbar_item(id_str : Void*) : Void*
          ObjCRuntime.with_autorelease_pool do
            o = ObjCRuntime
            id_crystal = o.nsstring_to_s(id_str)
            return Pointer(Void).null unless id_crystal

            item_data = @@items.find { |item| item.id == id_crystal }
            return Pointer(Void).null unless item_data

            item = o.msg(
              o.msg(o.get_class("NSToolbarItem"), "alloc"),
              "initWithItemIdentifier:", id_str,
            )

            case item_data.type
            when ::NativeDesktop::ToolbarItemType::Toggle
              btn = o.msg(o.msg(o.get_class("NSButton"), "alloc"), "init")
              o.msg_int(btn, "setButtonType:", 1_i64)
              o.msg_void(btn, "setTitle:", ObjCRuntime.nsstring(item_data.label))
              o.msg_int(btn, "setState:", item_data.checked ? 1_i64 : 0_i64)
              o.msg_int(btn, "setBezelStyle:", 8_i64)
              o.msg_void(btn, "setTarget:", @@delegate_instance)
              o.msg_void(btn, "setAction:", ObjCRuntime.sel("toolbarItemClicked:"))
              if img = create_nsimage_from_source(item_data.icon)
                o.msg_void(btn, "setImage:", img) unless img.null?
                o.msg_int(btn, "setImagePosition:", 2_i64)
              end
              o.msg_void(btn, "sizeToFit")
              o.msg_void(item, "setLabel:", ObjCRuntime.nsstring(item_data.label))
              o.msg_void(item, "setView:", btn)
              @@view_map[btn] = id_crystal
            when ::NativeDesktop::ToolbarItemType::Dropdown
              popup = o.msg(o.msg(o.get_class("NSPopUpButton"), "alloc"), "init")
              item_data.options.each do |opt|
                o.msg_void(popup, "addItemWithTitle:", ObjCRuntime.nsstring(opt))
              end
              o.msg_int(popup, "selectItemAtIndex:", item_data.selected_index.to_i64)
              o.msg_int(popup, "setBezelStyle:", 8_i64)
              o.msg_void(popup, "setTarget:", @@delegate_instance)
              o.msg_void(popup, "setAction:", ObjCRuntime.sel("toolbarItemClicked:"))
              if img = create_nsimage_from_source(item_data.icon)
                o.msg_void(popup, "setImage:", img) unless img.null?
              end
              o.msg_void(popup, "sizeToFit")
              o.msg_void(item, "setLabel:", ObjCRuntime.nsstring(item_data.label))
              o.msg_void(item, "setView:", popup)
              @@view_map[popup] = id_crystal
            when ::NativeDesktop::ToolbarItemType::Color
              btn = o.msg(o.msg(o.get_class("NSButton"), "alloc"), "init")
              o.msg_int(btn, "setBezelStyle:", 6_i64)
              unless item_data.color.empty?
                clr = ns_color_from_hex(item_data.color)
                img = o.msg(o.msg(o.get_class("NSImage"), "alloc"), "initWithSize:", 20.0, 20.0)
                o.msg_void(img, "lockFocus")
                o.msg_void(clr, "set") unless clr.null?
                path = o.msg(o.get_class("NSBezierPath"), "bezierPathWithRect:", 0.0, 0.0, 20.0, 20.0)
                o.msg_void(path, "fill")
                o.msg_void(img, "unlockFocus")
                o.msg_void(btn, "setImage:", img)
                o.msg_int(btn, "setImagePosition:", 2_i64)
              end
              o.msg_void(btn, "setTarget:", @@delegate_instance)
              o.msg_void(btn, "setAction:", ObjCRuntime.sel("toolbarItemClicked:"))
              o.msg_void(btn, "sizeToFit")
              o.msg_void(item, "setLabel:", ObjCRuntime.nsstring(item_data.label))
              o.msg_void(item, "setView:", btn)
              @@view_map[btn] = id_crystal
            else
              o.msg_void(item, "setLabel:", ObjCRuntime.nsstring(item_data.label))
              if img = create_nsimage_from_source(item_data.icon)
                o.msg_void(item, "setImage:", img) unless img.null?
              end
              o.msg_void(item, "setTarget:", @@delegate_instance)
              o.msg_void(item, "setAction:", ObjCRuntime.sel("toolbarItemClicked:"))
            end

            o.msg_int(item, "setEnabled:", item_data.enabled ? 1_i64 : 0_i64)
            item
          end
        rescue
          Pointer(Void).null
        end

        # Dispatch an IconSource to the right NSImage creation helper.
        private def create_nsimage_from_source(icon : ::NativeDesktop::ToolbarIcon?) : Void*
          return Pointer(Void).null unless icon
          if b = icon.bytes
            data = ObjCRuntime.msg_data_with_bytes(
              ObjCRuntime.get_class("NSData"),
              "dataWithBytes:length:",
              b.to_unsafe.as(Void*),
              b.size.to_u64,
            )
            return Pointer(Void).null if data.null?
            ObjCRuntime.msg(
              ObjCRuntime.msg(ObjCRuntime.get_class("NSImage"), "alloc"),
              "initWithData:",
              data,
            )
          elsif n = icon.name
            create_nsimage_from_name(n)
          else
            Pointer(Void).null
          end
        end

        private def create_nsimage_from_name(name : String) : Void*
          o = ObjCRuntime

          if name.starts_with?("/") || name.starts_with?(".")
            ns_path = ObjCRuntime.nsstring(name)
            img = o.msg(
              o.msg(o.get_class("NSImage"), "alloc"),
              "initWithContentsOfFile:", ns_path,
            )
            return img unless img.null?
          end

          sf_name = ObjCRuntime.nsstring(name)
          _cfg = o.msg(o.get_class("NSImageSymbolConfiguration"), "alloc")
          _cfg = o.msg(_cfg, "init")
          img = o.msg(
            o.get_class("NSImage"),
            "imageWithSystemSymbolName:accessibilityDescription:",
            sf_name, ObjCRuntime.nsstring(""),
          )
          img
        end

        private def ns_color_from_hex(hex : String) : Void*
          return Pointer(Void).null if hex.empty? || hex.size < 6
          s = hex.lstrip('#')
          r = s[0..1].to_i(16) / 255.0
          g = s[2..3].to_i(16) / 255.0
          b = s[4..5].to_i(16) / 255.0
          ObjCRuntime.with_autorelease_pool do
            o = ObjCRuntime
            o.msg(o.get_class("NSColor"), "colorWithRed:green:blue:alpha:", r, g, b, 1.0)
          end
        rescue
          Pointer(Void).null
        end

        private def handle_item_click(sender : Void*) : Nil
          ObjCRuntime.with_autorelease_pool do
            o = ObjCRuntime
            id_crystal = @@view_map[sender]?
            unless id_crystal
              id_str = o.msg(sender, "itemIdentifier")
              id_crystal = o.nsstring_to_s(id_str)
            end
            return unless id_crystal

            item_data = @@items.find { |item| item.id == id_crystal }
            if item_data && item_data.type == ::NativeDesktop::ToolbarItemType::Color
              o.msg_void(o.msg(o.get_class("NSApplication"), "sharedApplication"), "orderFrontColorPanel:", sender)
              panel = o.msg(o.get_class("NSColorPanel"), "sharedColorPanel")
              unless panel.null?
                unless item_data.color.empty?
                  clr = ns_color_from_hex(item_data.color)
                  o.msg_void(panel, "setColor:", clr) unless clr.null?
                end
                unless @@native.null?
                  wf = o.msg_rect(@@native, "frame")
                  pf = o.msg_rect(panel, "frame")
                  o.msg_void(panel, "setFrameOrigin:", wf.x + (wf.w - pf.w) / 2.0, wf.y + (wf.h - pf.h) / 2.0)
                end
              end
            end

            if action = @@actions[id_crystal]?
              action.try(&.call)
            end
          end
        rescue ex
          Log.error { "Toolbar item click error: #{ex.message}" }
        end
      end
    end
  end
end
