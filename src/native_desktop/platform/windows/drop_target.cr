require "./string_helpers"
require "./win32_common"

module NativeDesktop::Platform
  class WindowsDropTargetAdapter < NativeDesktop::DropTargetAdapter
    @[Link("ole32")]
    @[Link("shell32")]
    lib LibDropTarget
      union MediumValue
        global : Void*
      end

      struct FormatEtc
        format : UInt16
        target_device : Void*
        aspect : UInt32
        index : Int32
        medium : UInt32
      end

      struct StgMedium
        medium : UInt32
        value : MediumValue
        release : Void*
      end

      struct PointL
        x : Int32
        y : Int32
      end

      fun OleInitialize(reserved : Void*) : Int32
      fun OleUninitialize : Nil
      fun RegisterDragDrop(window : Void*, target : Void*) : Int32
      fun RevokeDragDrop(window : Void*) : Int32
      fun ReleaseStgMedium(medium : StgMedium*) : Nil
      fun CoTaskMemAlloc(size : UInt64) : Void*
      fun CoTaskMemFree(memory : Void*) : Nil
      fun GlobalLock(memory : Void*) : Void*
      fun GlobalUnlock(memory : Void*) : Int32
      fun DragQueryFileW(drop : Void*, index : UInt32, path : UInt16*, size : UInt32) : UInt32
    end

    S_OK          =           0_i32
    S_FALSE       =           1_i32
    E_NOINTERFACE = -2147467262_i32
    E_POINTER     = -2147467261_i32
    DV_E_FORMAT   = -2147221404_i32

    CF_UNICODETEXT   = 13_u16
    CF_HDROP         = 15_u16
    DVASPECT_CONTENT =  1_u32
    TYMED_HGLOBAL    =  1_u32
    DROP_EFFECT_COPY =  1_u32

    IUNKNOWN_IID = Bytes[
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46,
    ]
    IDROP_TARGET_IID = Bytes[
      0x22, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46,
    ]

    @@vtable = Pointer(Void).null.as(Pointer(Void*))

    @window = Pointer(Void).null
    @object = Pointer(Void).null
    @emit : Proc(NativeDesktop::DropEvent, Bool)?
    @kinds = Set(NativeDesktop::DragKind).new
    @ole_initialized = false

    def attach(window : NativeDesktop::Window, kinds : Set(NativeDesktop::DragKind), &emit : NativeDesktop::DropEvent -> Bool) : Nil
      @window = window.handle
      @kinds = kinds
      @emit = emit

      result = LibDropTarget.OleInitialize(Pointer(Void).null)
      unless result == S_OK || result == S_FALSE
        raise NativeDesktop::Error.new("OLE initialization failed (HRESULT #{result})", :drop_target_unavailable)
      end
      @ole_initialized = true

      build_vtable if @@vtable.null?
      @object = allocate_object
      if @object.null?
        raise NativeDesktop::Error.new("could not allocate the OLE drop target", :drop_target_unavailable)
      end

      result = LibDropTarget.RegisterDragDrop(@window, @object)
      unless result == S_OK
        raise NativeDesktop::Error.new("RegisterDragDrop failed (HRESULT #{result})", :drop_target_attach_failed)
      end
    rescue ex : NativeDesktop::Error
      close
      raise ex
    end

    def close : Nil
      LibDropTarget.RevokeDragDrop(@window) unless @window.null?
      release(@object) unless @object.null?
      LibDropTarget.OleUninitialize if @ole_initialized
      @window = Pointer(Void).null
      @object = Pointer(Void).null
      @ole_initialized = false
      @emit = nil
    end

    protected def receive(data_object : Void*, point : LibDropTarget::PointL) : Bool
      payloads = file_payloads(data_object)
      if payloads.empty? && @kinds.any? { |kind| kind.text? || kind.url? }
        if text = unicode_text(data_object)
          kind = uri?(text) && @kinds.includes?(NativeDesktop::DragKind::URL) ? NativeDesktop::DragKind::URL : NativeDesktop::DragKind::Text
          payloads << NativeDesktop::DragPayload.new(kind, text) if @kinds.includes?(kind)
        end
      end
      return false if payloads.empty?
      client_point = Windows::LibUser32::Point.new(x: point.x, y: point.y)
      Windows::LibUser32.ScreenToClient(@window, pointerof(client_point))
      @emit.try(&.call(NativeDesktop::DropEvent.new(
        payloads,
        NativeDesktop::Point.new(client_point.x, client_point.y)
      ))) || false
    rescue
      false
    end

    def self.query_interface(object : Void*, iid : Void*, result : Void**) : Int32
      return E_POINTER if result.null?
      result.value = Pointer(Void).null
      return E_NOINTERFACE unless iid?(iid, IUNKNOWN_IID) || iid?(iid, IDROP_TARGET_IID)
      result.value = object
      add_ref(object)
      S_OK
    end

    def self.add_ref(object : Void*) : UInt32
      references = object.as(Pointer(Int32))[2] + 1
      object.as(Pointer(Int32))[2] = references
      references.to_u32!
    end

    def self.release(object : Void*) : UInt32
      references = object.as(Pointer(Int32))[2] - 1
      object.as(Pointer(Int32))[2] = references
      LibDropTarget.CoTaskMemFree(object) if references == 0
      references.to_u32!
    end

    def self.adapter(object : Void*) : WindowsDropTargetAdapter
      Box(WindowsDropTargetAdapter).unbox(object.as(Pointer(Void*))[2])
    end

    private def self.iid?(candidate : Void*, expected : Bytes) : Bool
      return false if candidate.null?
      bytes = candidate.as(UInt8*)
      16.times { |index| return false unless bytes[index] == expected[index] }
      true
    end

    private def build_vtable : Nil
      table = LibDropTarget.CoTaskMemAlloc(7_u64 * sizeof(Void*)).as(Pointer(Void*))
      if table.null?
        raise NativeDesktop::Error.new("could not allocate the OLE drop-target vtable", :drop_target_unavailable)
      end
      table[0] = ->(object : Void*, iid : Void*, result : Void**) : Int32 {
        WindowsDropTargetAdapter.query_interface(object, iid, result)
      }.pointer
      table[1] = ->(object : Void*) : UInt32 { WindowsDropTargetAdapter.add_ref(object) }.pointer
      table[2] = ->(object : Void*) : UInt32 { WindowsDropTargetAdapter.release(object) }.pointer
      table[3] = ->(_object : Void*, _data : Void*, _keys : UInt32, _point : LibDropTarget::PointL, effect : UInt32*) : Int32 {
        effect.value = DROP_EFFECT_COPY unless effect.null?
        S_OK
      }.pointer
      table[4] = ->(_object : Void*, _keys : UInt32, _point : LibDropTarget::PointL, effect : UInt32*) : Int32 {
        effect.value = DROP_EFFECT_COPY unless effect.null?
        S_OK
      }.pointer
      table[5] = ->(_object : Void*) : Int32 { S_OK }.pointer
      table[6] = ->(object : Void*, data : Void*, _keys : UInt32, point : LibDropTarget::PointL, effect : UInt32*) : Int32 {
        accepted = WindowsDropTargetAdapter.adapter(object).receive(data, point)
        effect.value = accepted ? DROP_EFFECT_COPY : 0_u32 unless effect.null?
        S_OK
      }.pointer
      @@vtable = table
    end

    private def allocate_object : Void*
      object = LibDropTarget.CoTaskMemAlloc(24_u64)
      return object if object.null?
      object.as(Pointer(Void*)).value = @@vtable.as(Void*)
      object.as(Pointer(Int32))[2] = 1
      object.as(Pointer(Void*))[2] = Box.box(self)
      object
    end

    private def release(object : Void*) : Nil
      self.class.release(object)
    end

    private def file_payloads(data_object : Void*) : Array(NativeDesktop::DragPayload)
      return [] of NativeDesktop::DragPayload unless @kinds.any? { |kind| kind.file? || kind.image? }
      with_medium(data_object, CF_HDROP) do |memory|
        count = LibDropTarget.DragQueryFileW(memory, UInt32::MAX, Pointer(UInt16).null, 0)
        Array(NativeDesktop::DragPayload).new(count.to_i) do |index|
          length = LibDropTarget.DragQueryFileW(memory, index.to_u32, Pointer(UInt16).null, 0)
          buffer = Slice(UInt16).new(length.to_i + 1, 0_u16)
          LibDropTarget.DragQueryFileW(memory, index.to_u32, buffer.to_unsafe, buffer.size.to_u32)
          path = Windows::StringHelpers.from_utf16(buffer.to_unsafe)
          kind = @kinds.includes?(NativeDesktop::DragKind::File) ? NativeDesktop::DragKind::File : NativeDesktop::DragKind::Image
          NativeDesktop::DragPayload.new(kind, path)
        end
      end || [] of NativeDesktop::DragPayload
    end

    private def unicode_text(data_object : Void*) : String?
      with_medium(data_object, CF_UNICODETEXT) do |memory|
        pointer = LibDropTarget.GlobalLock(memory)
        next nil if pointer.null?
        begin
          Windows::StringHelpers.from_utf16(pointer.as(UInt16*))
        ensure
          LibDropTarget.GlobalUnlock(memory)
        end
      end
    end

    private def with_medium(data_object : Void*, format : UInt16, &block : Void* -> T) : T? forall T
      request = LibDropTarget::FormatEtc.new
      request.format = format
      request.target_device = Pointer(Void).null
      request.aspect = DVASPECT_CONTENT
      request.index = -1
      request.medium = TYMED_HGLOBAL
      medium = LibDropTarget::StgMedium.new

      vtable = data_object.as(Pointer(Void*)).value.as(Pointer(Void*))
      get_data = Proc(Void*, LibDropTarget::FormatEtc*, LibDropTarget::StgMedium*, Int32).new(
        vtable[3],
        Pointer(Void).null
      )
      return nil unless get_data.call(data_object, pointerof(request), pointerof(medium)) == S_OK
      begin
        yield medium.value.global
      ensure
        LibDropTarget.ReleaseStgMedium(pointerof(medium))
      end
    end

    private def uri?(value : String) : Bool
      value.matches?(/\A[a-zA-Z][a-zA-Z0-9+.-]*:/)
    end
  end
end

NativeDesktop::DropTargets.register { NativeDesktop::Platform::WindowsDropTargetAdapter.new }
NativeDesktop::Capabilities.register(
  NativeDesktop::Features::DropTarget,
  NativeDesktop::CapabilityState::Supported
)
