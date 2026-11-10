require "log"

@[Link("gtk-3", pkg_config: "gtk+-3.0")]
lib LibGTKContext
  fun gtk_menu_new : Void*
  fun gtk_menu_item_new_with_label(label : UInt8*) : Void*
  fun gtk_menu_shell_append(menu_shell : Void*, child : Void*) : Nil
  fun gtk_check_menu_item_new_with_label(label : UInt8*) : Void*
  fun gtk_check_menu_item_set_active(check_menu_item : Void*, is_active : Int32) : Nil
  fun gtk_menu_item_set_submenu(menu_item : Void*, submenu : Void*) : Nil
  fun gtk_separator_menu_item_new : Void*

  fun gtk_widget_get_window(widget : Void*) : Void*

  fun gtk_menu_attach_to_widget(menu : Void*, attach_widget : Void*, detacher : Void*) : Nil
  fun gtk_menu_popup_at_pointer(menu : Void*, trigger_event : Void*) : Nil
  fun gtk_widget_show_all(widget : Void*) : Nil
  fun gtk_widget_set_sensitive(widget : Void*, sensitive : Int32) : Nil
end

@[Link("gobject-2.0")]
lib LibGObjectContext
  fun g_signal_connect_data(instance : Void*, signal : UInt8*, callback : Void*, data : Void*, destroy_data : Void*, flags : Int32) : UInt64
end

@[Link("glib-2.0")]
lib LibGLibContext
  fun g_get_monotonic_time : Int64
  fun g_main_context_iteration(context : Void*, may_block : Int32) : Int32
end

@[Link("gdk-3", pkg_config: "gdk-3.0")]
lib LibGDKContext
  fun gdk_display_get_default : Void*
  fun gdk_event_new(type : Int32) : Void*
  fun gdk_window_get_origin(window : Void*, x : Int32*, y : Int32*) : Int32
  fun gdk_display_get_default_seat(display : Void*) : Void*
  fun gdk_seat_get_pointer(seat : Void*) : Void*

  @[Packed]
  # :nodoc:
  struct GdkEventButton
    event_type : Int32
    _pad0 : Int32
    window : Void*
    send_event : Int8
    _pad1 : UInt8[3]
    time : UInt32
    x : Float64
    y : Float64
    axes : Void*
    state : UInt32
    button : UInt32
    device : Void*
    x_root : Float64
    y_root : Float64
  end
end

GDK_BUTTON_PRESS = 4

module NativeDesktop
  module Platform
    module Linux
      module ContextMenu
        extend self

        @@context_done = false
        @@context_result : String? = nil
        @@context_flat_ids : Array(String) = [] of String
        @@context_next_id : Int32 = 0

        @@popup_event : Void* = Pointer(Void).null

        def available? : Bool
          true
        end

        def show_context_menu(
          items : Array(NativeDesktop::ContextMenuItem),
          x : Int32,
          y : Int32,
          window_ptr : Void*,
        ) : String?
          @@context_done = false
          @@context_result = nil
          @@context_flat_ids.clear
          @@context_next_id = 0

          menu = LibGTKContext.gtk_menu_new
          return nil if menu.null?

          build_widgets(items, menu)

          LibGTKContext.gtk_widget_show_all(menu)

          LibGObjectContext.g_signal_connect_data(
            menu,
            "deactivate",
            ->(_widget : Void*, _data : Void*) {
              @@context_done = true
              nil
            }.pointer,
            Pointer(Void).null,
            Pointer(Void).null,
            0
          )

          LibGTKContext.gtk_menu_attach_to_widget(menu, window_ptr, Pointer(Void).null)

          gdk_window = LibGTKContext.gtk_widget_get_window(window_ptr)

          if gdk_window.null?
            LibGTKContext.gtk_menu_popup_at_pointer(menu, Pointer(Void).null)
          else
            win_ox = uninitialized Int32
            win_oy = uninitialized Int32

            LibGDKContext.gdk_window_get_origin(
              gdk_window,
              pointerof(win_ox),
              pointerof(win_oy)
            )

            event = LibGDKContext.gdk_event_new(GDK_BUTTON_PRESS)

            unless event.null?
              btn = Pointer(LibGDKContext::GdkEventButton).new(event.address)

              btn.value.event_type = GDK_BUTTON_PRESS
              btn.value.window = gdk_window
              btn.value.send_event = 0_i8
              btn.value.time = (LibGLibContext.g_get_monotonic_time // 1000).to_u32
              btn.value.x = x.to_f64
              btn.value.y = y.to_f64
              btn.value.x_root = (win_ox + x).to_f64
              btn.value.y_root = (win_oy + y).to_f64
              btn.value.state = 0_u32
              btn.value.button = 3_u32

              display = LibGDKContext.gdk_display_get_default

              unless display.null?
                seat = LibGDKContext.gdk_display_get_default_seat(display.as(Void*))

                unless seat.null?
                  device = LibGDKContext.gdk_seat_get_pointer(seat)
                  btn.value.device = device
                end
              end

              @@popup_event = event

              LibGTKContext.gtk_menu_popup_at_pointer(menu, event)
            end
          end

          limit = Time.instant + 30.seconds

          until @@context_done
            break if Time.instant > limit
            LibGLibContext.g_main_context_iteration(nil, 1)
          end

          100.times do
            LibGLibContext.g_main_context_iteration(nil, 0)
          end

          result = @@context_result

          @@context_result = nil

          result
        rescue ex
          Log.error { "ContextMenu[Linux]: #{ex.message}" }
          nil
        end

        private def build_widgets(
          items : Array(NativeDesktop::ContextMenuItem),
          parent : Void*,
        ) : Nil
          items.each do |item|
            case item.type
            in .separator?
              sep = LibGTKContext.gtk_separator_menu_item_new

              LibGTKContext.gtk_menu_shell_append(
                parent,
                sep
              )
            in .normal?, .checkbox?
              gtk_item =
                if item.checked?
                  ci = LibGTKContext.gtk_check_menu_item_new_with_label(item.label)
                  LibGTKContext.gtk_check_menu_item_set_active(ci, 1)
                  ci
                else
                  LibGTKContext.gtk_menu_item_new_with_label(item.label)
                end

              LibGTKContext.gtk_widget_set_sensitive(
                gtk_item,
                item.enabled? ? 1 : 0
              )

              if submenu_items = item.submenu
                submenu = LibGTKContext.gtk_menu_new

                build_widgets(
                  submenu_items,
                  submenu
                )

                LibGTKContext.gtk_menu_item_set_submenu(
                  gtk_item,
                  submenu
                )
              else
                item_index = @@context_next_id
                @@context_next_id += 1

                @@context_flat_ids << item.id

                data_ptr = Pointer(Void).new(
                  item_index.to_u64
                )

                LibGObjectContext.g_signal_connect_data(
                  gtk_item,
                  "activate",
                  ->(_widget : Void*, data : Void*) {
                    idx = data.address.to_i32

                    if idx >= 0 && idx < @@context_flat_ids.size
                      @@context_result = @@context_flat_ids[idx]
                    end

                    @@context_done = true

                    nil
                  }.pointer,
                  data_ptr,
                  Pointer(Void).null,
                  0
                )
              end

              LibGTKContext.gtk_menu_shell_append(
                parent,
                gtk_item
              )
            end
          end
        end
      end
    end
  end
end
