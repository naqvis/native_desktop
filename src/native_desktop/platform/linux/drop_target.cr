require "uri"

@[Link("gtk-3", pkg_config: "gtk+-3.0")]
lib LibGTKDropTarget
  fun gtk_drag_dest_set(widget : Void*, defaults : UInt32, targets : Void*, count : Int32, actions : UInt32) : Nil
  fun gtk_drag_dest_set_target_list(widget : Void*, targets : Void*) : Nil
  fun gtk_drag_dest_unset(widget : Void*) : Nil
  fun gtk_target_list_new(targets : Void*, count : UInt32) : Void*
  fun gtk_target_list_add_text_targets(list : Void*, info : UInt32) : Nil
  fun gtk_target_list_add_uri_targets(list : Void*, info : UInt32) : Nil
  fun gtk_target_list_unref(list : Void*) : Nil
  fun gtk_selection_data_get_text(data : Void*) : UInt8*
  fun gtk_selection_data_get_uris(data : Void*) : UInt8**
  fun gtk_drag_finish(context : Void*, success : Int32, delete : Int32, time : UInt32) : Nil
end

@[Link("gobject-2.0")]
lib LibGObjectDropTarget
  fun g_signal_connect_data(instance : Void*, signal : UInt8*, callback : Void*, data : Void*, destroy_data : Void*, flags : Int32) : UInt64
  fun g_signal_handler_disconnect(instance : Void*, handler : UInt64) : Nil
end

@[Link("glib-2.0")]
lib LibGLibDropTarget
  fun g_free(value : Void*) : Nil
  fun g_strfreev(value : UInt8**) : Nil
  fun g_filename_from_uri(uri : UInt8*, hostname : UInt8**, error : Void**) : UInt8*
end

module NativeDesktop::Platform
  class GTKDropTargetAdapter < NativeDesktop::DropTargetAdapter
    TEXT_INFO        = 1_u32
    URI_INFO         = 2_u32
    ACTION_COPY      = 1_u32
    DEST_DEFAULT_ALL = 7_u32

    @window = Pointer(Void).null
    @target_list = Pointer(Void).null
    @handler_id = 0_u64
    @callback_data = Pointer(Void).null
    @emit : Proc(NativeDesktop::DropEvent, Bool)?
    @kinds = Set(NativeDesktop::DragKind).new

    def attach(window : NativeDesktop::Window, kinds : Set(NativeDesktop::DragKind), &emit : NativeDesktop::DropEvent -> Bool) : Nil
      @window = window.handle
      @kinds = kinds
      @emit = emit
      @callback_data = Box.box(self)
      @target_list = LibGTKDropTarget.gtk_target_list_new(Pointer(Void).null, 0_u32)
      LibGTKDropTarget.gtk_target_list_add_text_targets(@target_list, TEXT_INFO) if kinds.includes?(DragKind::Text)
      if kinds.any? { |kind| kind.file? || kind.image? || kind.url? }
        LibGTKDropTarget.gtk_target_list_add_uri_targets(@target_list, URI_INFO)
      end
      LibGTKDropTarget.gtk_drag_dest_set(@window, DEST_DEFAULT_ALL, Pointer(Void).null, 0, ACTION_COPY)
      LibGTKDropTarget.gtk_drag_dest_set_target_list(@window, @target_list)
      @handler_id = LibGObjectDropTarget.g_signal_connect_data(
        @window,
        "drag-data-received",
        ->(_widget : Void*, context : Void*, x : Int32, y : Int32, data : Void*, info : UInt32, time : UInt32, user_data : Void*) {
          adapter = Box(GTKDropTargetAdapter).unbox(user_data)
          accepted = adapter.receive(data, info, x, y)
          LibGTKDropTarget.gtk_drag_finish(context, accepted ? 1 : 0, 0, time)
          0
        }.pointer,
        @callback_data,
        Pointer(Void).null,
        0_i32
      )
    end

    def close : Nil
      unless @window.null?
        LibGObjectDropTarget.g_signal_handler_disconnect(@window, @handler_id) unless @handler_id == 0
        LibGTKDropTarget.gtk_drag_dest_unset(@window)
      end
      LibGTKDropTarget.gtk_target_list_unref(@target_list) unless @target_list.null?
      @window = Pointer(Void).null
      @target_list = Pointer(Void).null
      @handler_id = 0_u64
      @emit = nil
    end

    protected def receive(data : Void*, info : UInt32, x : Int32, y : Int32) : Bool
      payloads = info == TEXT_INFO ? text_payloads(data) : uri_payloads(data)
      return false if payloads.empty?
      @emit.try(&.call(DropEvent.new(payloads, Point.new(x, y)))) || false
    end

    private def text_payloads(data : Void*) : Array(DragPayload)
      pointer = LibGTKDropTarget.gtk_selection_data_get_text(data)
      return [] of DragPayload if pointer.null?
      begin
        [DragPayload.text(String.new(pointer))]
      ensure
        LibGLibDropTarget.g_free(pointer.as(Void*))
      end
    end

    private def uri_payloads(data : Void*) : Array(DragPayload)
      values = LibGTKDropTarget.gtk_selection_data_get_uris(data)
      return [] of DragPayload if values.null?
      begin
        payloads = [] of DragPayload
        index = 0
        until values[index].null?
          uri = String.new(values[index])
          if path = file_path(uri)
            kind = @kinds.includes?(DragKind::File) ? DragKind::File : DragKind::Image
            payloads << DragPayload.new(kind, path)
          elsif @kinds.includes?(DragKind::URL)
            payloads << DragPayload.url(uri)
          end
          index += 1
        end
        payloads
      ensure
        LibGLibDropTarget.g_strfreev(values)
      end
    end

    private def file_path(uri : String) : String?
      pointer = LibGLibDropTarget.g_filename_from_uri(uri, Pointer(UInt8*).null, Pointer(Void*).null)
      return nil if pointer.null?
      String.new(pointer).tap { LibGLibDropTarget.g_free(pointer.as(Void*)) }
    end
  end
end

NativeDesktop::DropTargets.register { NativeDesktop::Platform::GTKDropTargetAdapter.new }
NativeDesktop::Capabilities.register(NativeDesktop::Features::DropTarget, NativeDesktop::CapabilityState::Supported)
