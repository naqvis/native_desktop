require "log"

@[Link("gtk-3", pkg_config: "gtk+-3.0")]
@[Link("gdk-3", pkg_config: "gdk-3.0")]
lib LibGTKDrag
  fun gtk_drag_begin_with_coordinates(
    widget : Void*, targets : Void*, actions : UInt32,
    button : Int32, event : Void*, x : Int32, y : Int32,
  ) : Void*
  fun gtk_drag_source_set(
    widget : Void*, start_button_mask : UInt32,
    targets : Void*, n_targets : Int32, actions : UInt32,
  ) : Nil
  fun gtk_drag_source_set_target_list(widget : Void*, target_list : Void*) : Nil
  fun gtk_drag_source_unset(widget : Void*) : Nil
  fun gtk_target_list_new(targets : Void*, n_targets : UInt32) : Void*
  fun gtk_target_list_add_text_targets(list : Void*, info : UInt32) : Nil
  fun gtk_target_list_add_uri_targets(list : Void*, info : UInt32) : Nil
  fun gtk_target_list_unref(list : Void*) : Nil
  fun gtk_selection_data_set_text(selection_data : Void*, text : UInt8*, len : Int32) : Int32
  fun gtk_selection_data_set_uris(selection_data : Void*, uris : UInt8**) : UInt32
  fun gtk_get_current_event : Void*
  fun gdk_event_free(event : Void*) : Nil
  fun gdk_event_get_button(event : Void*, button : UInt32*) : Int32
  fun gdk_event_get_coords(event : Void*, x : Float64*, y : Float64*) : Int32
end

@[Link("gobject-2.0")]
lib LibGObjectDrag
  fun g_signal_connect_data(instance : Void*, signal : UInt8*, callback : Void*, data : Void*, destroy_data : Void*, flags : Int32) : UInt64
  fun g_signal_handler_disconnect(instance : Void*, handler_id : UInt64) : Nil
end

@[Link("glib-2.0")]
lib LibGLibDrag
  fun g_filename_to_uri(filename : UInt8*, hostname : UInt8*, error : Void**) : UInt8*
  fun g_free(memory : Void*) : Nil
end

module NativeDesktop::Platform
  class DragSource
    GDK_ACTION_COPY  =   1_u32
    GDK_BUTTON1_MASK = 256_u32

    @payload : NativeDesktop::DragPayload?
    @drag_handler_id = 0_u64
    @data_handler_id = 0_u64
    @target_list = Pointer(Void).null
    @callback_data = Pointer(Void).null

    def initialize(@window : Void*)
      @callback_data = Box.box(self)
    end

    def start(payload : NativeDesktop::DragPayload) : Bool
      return false if @window.null?
      cleanup(false)

      event = LibGTKDrag.gtk_get_current_event
      unowned_targets = Pointer(Void).null
      begin
        targets = LibGTKDrag.gtk_target_list_new(Pointer(Void).null, 0_u32)
        return false if targets.null?
        unowned_targets = targets

        if payload.kind.text?
          LibGTKDrag.gtk_target_list_add_text_targets(targets, 0_u32)
        else
          LibGTKDrag.gtk_target_list_add_uri_targets(targets, 0_u32)
        end

        LibGTKDrag.gtk_drag_source_set(@window, GDK_BUTTON1_MASK, Pointer(Void).null, 0, GDK_ACTION_COPY)
        LibGTKDrag.gtk_drag_source_set_target_list(@window, targets)
        @target_list = targets
        unowned_targets = Pointer(Void).null
        @payload = payload

        @data_handler_id = LibGObjectDrag.g_signal_connect_data(
          @window, "drag-data-get".to_unsafe,
          ->(_widget : Void*, _context : Void*, data : Void*, _info : UInt32, _time : UInt32, user_data : Void*) {
            Box(DragSource).unbox(user_data).provide_drag_data(data)
            0
          }.pointer,
          @callback_data, Pointer(Void).null, 0_i32,
        )
        @drag_handler_id = LibGObjectDrag.g_signal_connect_data(
          @window, "drag-end".to_unsafe,
          ->(_widget : Void*, _context : Void*, user_data : Void*) {
            Box(DragSource).unbox(user_data).finish_drag
            0
          }.pointer,
          @callback_data, Pointer(Void).null, 0_i32,
        )

        button, x, y = event.null? ? {1, 0, 0} : drag_event_position(event)
        context = LibGTKDrag.gtk_drag_begin_with_coordinates(
          @window, targets, GDK_ACTION_COPY, button, event, x, y,
        )
        if context.null?
          cleanup(false)
          return false
        end
        true
      ensure
        LibGTKDrag.gdk_event_free(event) unless event.null?
        LibGTKDrag.gtk_target_list_unref(unowned_targets) unless unowned_targets.null?
      end
    rescue ex
      cleanup(false)
      Log.error { "start_drag[Linux] failed: #{ex.message}" }
      false
    end

    def close : Nil
      cleanup(true)
    end

    protected def finish_drag : Nil
      cleanup(false)
    end

    protected def provide_drag_data(selection_data : Void*) : Nil
      return unless item = @payload

      if item.kind.text?
        LibGTKDrag.gtk_selection_data_set_text(selection_data, item.value.to_unsafe, item.value.bytesize)
        return
      end

      uri = item.kind.url? ? item.value : filename_uri(item.value)
      return unless uri
      null = Pointer(UInt8).null
      uris = [uri.to_unsafe, null]
      LibGTKDrag.gtk_selection_data_set_uris(selection_data, uris.to_unsafe)
    end

    private def filename_uri(path : String) : String?
      native = LibGLibDrag.g_filename_to_uri(path.to_unsafe, Pointer(UInt8).null, Pointer(Void*).null)
      return nil if native.null?
      begin
        String.new(native)
      ensure
        LibGLibDrag.g_free(native.as(Void*))
      end
    end

    private def cleanup(clear_window : Bool) : Nil
      widget = @window
      unless widget.null?
        LibGObjectDrag.g_signal_handler_disconnect(widget, @data_handler_id) unless @data_handler_id == 0
        LibGObjectDrag.g_signal_handler_disconnect(widget, @drag_handler_id) unless @drag_handler_id == 0
        LibGTKDrag.gtk_drag_source_unset(widget)
      end
      LibGTKDrag.gtk_target_list_unref(@target_list) unless @target_list.null?

      @data_handler_id = 0_u64
      @drag_handler_id = 0_u64
      @target_list = Pointer(Void).null
      @payload = nil
      @window = Pointer(Void).null if clear_window
    end

    private def drag_event_position(event : Void*) : {Int32, Int32, Int32}
      button = 1_u32
      LibGTKDrag.gdk_event_get_button(event, pointerof(button))
      x = 0.0
      y = 0.0
      unless LibGTKDrag.gdk_event_get_coords(event, pointerof(x), pointerof(y)) != 0
        x = 0.0
        y = 0.0
      end
      {button.to_i32, x.to_i32, y.to_i32}
    end
  end
end
