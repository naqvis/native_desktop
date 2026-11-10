require "log"

module NativeDesktop::Platform
  class DragSource
    @[Link("ole32")]
    lib LibWin32Drag
      union Medium
        h_global : Void*
        file_name : UInt16*
      end

      struct FormatEtc
        cf_format : UInt16
        target_device : Void*
        aspect : UInt32
        index : Int32
        medium : UInt32
      end

      struct StgMedium
        medium : UInt32
        value : Medium
        release : Void*
      end

      fun DoDragDrop(data_object : Void*, drop_source : Void*, allowed_effects : UInt32, effect : UInt32*) : Int32
      fun OleInitialize(reserved : Void*) : Int32
      fun OleUninitialize : Nil
      fun CoTaskMemAlloc(size : UInt64) : Void*
      fun CoTaskMemFree(memory : Void*) : Nil
      fun GlobalAlloc(flags : UInt32, size : UInt64) : Void*
      fun GlobalLock(memory : Void*) : Void*
      fun GlobalUnlock(memory : Void*) : Int32
      fun GlobalFree(memory : Void*) : Void*
    end

    S_OK                          =           0_i32
    S_FALSE                       =           1_i32
    DRAGDROP_S_CANCEL             =           1_i32
    DRAGDROP_S_DROP               =           2_i32
    E_NOTIMPL                     = -2147467263_i32
    E_NOINTERFACE                 = -2147467262_i32
    E_POINTER                     = -2147467261_i32
    E_OUTOFMEMORY                 = -2147024882_i32
    DV_E_FORMATETC                = -2147221404_i32
    DRAGDROP_S_USEDEFAULTCURSORS  =           0_i32
    DND_GMEM_MOVEABLE             =      0x0002_u32
    GMEM_ZEROINIT                 =      0x0040_u32
    CF_UNICODETEXT                =          13_u16
    CF_HDROP                      =          15_u16
    TYMED_HGLOBAL                 =           1_u32
    DVASPECT_CONTENT              =           1_u32
    DROPEFFECT_COPY               =           1_u32
    MK_LBUTTON                    =           1_u32
    VTBL_QUERY_INTERFACE          =               0
    VTBL_ADD_REF                  =               1
    VTBL_RELEASE                  =               2
    VTBL_QUERY_CONTINUE_DRAG      =               3
    VTBL_GIVE_FEEDBACK            =               4
    VTBL_GET_DATA                 =               3
    VTBL_GET_DATA_HERE            =               4
    VTBL_QUERY_GET_DATA           =               5
    VTBL_GET_CANONICAL_FORMAT_ETC =               6
    VTBL_SET_DATA                 =               7
    VTBL_ENUM_FORMAT_ETC          =               8
    VTBL_D_ADVISE                 =               9
    VTBL_D_UNADVISE               =              10
    VTBL_ENUM_D_ADVISE            =              11

    IUNKNOWN_IID     = Bytes[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]
    IDROP_SOURCE_IID = Bytes[0x21, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]
    IDATA_OBJECT_IID = Bytes[0x0E, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]

    @@drop_source_vtable = Pointer(Void).null.as(Pointer(Void*))
    @@data_object_vtable = Pointer(Void).null.as(Pointer(Void*))

    def initialize(@window : Void*)
    end

    def start(payload : NativeDesktop::DragPayload) : Bool
      return false if @window.null?

      ole_result = LibWin32Drag.OleInitialize(Pointer(Void).null)
      return false unless ole_result == S_OK || ole_result == S_FALSE

      begin
        build_drop_source_vtable if @@drop_source_vtable.null?
        build_data_object_vtable if @@data_object_vtable.null?
        return false if @@drop_source_vtable.null? || @@data_object_vtable.null?

        drop_source = allocate_object(@@drop_source_vtable, Pointer(Void).null)
        return false if drop_source.null?

        data_pointer = Box.box(payload)
        data_object = allocate_object(@@data_object_vtable, data_pointer)
        if data_object.null?
          release_object(drop_source)
          return false
        end

        begin
          effect = 0_u32
          result = LibWin32Drag.DoDragDrop(data_object, drop_source, DROPEFFECT_COPY, pointerof(effect))
          result == DRAGDROP_S_DROP && (effect & DROPEFFECT_COPY) != 0
        ensure
          release_object(data_object)
          release_object(drop_source)
        end
      ensure
        LibWin32Drag.OleUninitialize
      end
    rescue ex
      Log.error { "start_drag[Windows] failed: #{ex.message}" }
      false
    end

    def close : Nil
      @window = Pointer(Void).null
    end

    private def allocate_object(vtable : Pointer(Void*), data : Void*) : Void*
      object = LibWin32Drag.CoTaskMemAlloc(24_u64)
      return Pointer(Void).null if object.null?
      object.as(Pointer(Void*)).value = vtable.as(Void*)
      object.as(Pointer(Int32))[2] = 1
      object.as(Pointer(Void*))[2] = data
      object
    end

    private def release_object(object : Void*) : UInt32
      references = object.as(Pointer(Int32))[2] - 1
      object.as(Pointer(Int32))[2] = references
      LibWin32Drag.CoTaskMemFree(object) if references == 0
      references.to_u32!
    end

    # :nodoc:
    def self.com_add_ref(object : Void*) : UInt32
      references = object.as(Pointer(Int32))[2] + 1
      object.as(Pointer(Int32))[2] = references
      references.to_u32!
    end

    # :nodoc:
    def self.com_release(object : Void*) : UInt32
      references = object.as(Pointer(Int32))[2] - 1
      object.as(Pointer(Int32))[2] = references
      LibWin32Drag.CoTaskMemFree(object) if references == 0
      references.to_u32!
    end

    # :nodoc:
    def self.iid?(candidate : Void*, expected : Bytes) : Bool
      return false if candidate.null?
      bytes = candidate.as(UInt8*)
      16.times { |index| return false unless bytes[index] == expected[index] }
      true
    end

    # :nodoc:
    def self.query_interface(object : Void*, iid : Void*, result : Void**, supported : Bytes) : Int32
      return E_POINTER if result.null?
      result.value = Pointer(Void).null
      return E_NOINTERFACE unless iid?(iid, IUNKNOWN_IID) || iid?(iid, supported)
      result.value = object
      com_add_ref(object)
      S_OK
    end

    private def build_drop_source_vtable : Nil
      vtable = LibWin32Drag.CoTaskMemAlloc(5_u64 * sizeof(Void*)).as(Pointer(Void*))
      return if vtable.null?

      vtable[VTBL_QUERY_INTERFACE] = ->(object : Void*, iid : Void*, result : Void**) : Int32 {
        DragSource.query_interface(object, iid, result, IDROP_SOURCE_IID)
      }.pointer
      vtable[VTBL_ADD_REF] = ->(object : Void*) : UInt32 { DragSource.com_add_ref(object) }.pointer
      vtable[VTBL_RELEASE] = ->(object : Void*) : UInt32 { DragSource.com_release(object) }.pointer
      vtable[VTBL_QUERY_CONTINUE_DRAG] = ->(_object : Void*, escape : Int32, key_state : UInt32) : Int32 {
        if escape != 0
          DRAGDROP_S_CANCEL
        elsif (key_state & MK_LBUTTON) == 0
          DRAGDROP_S_DROP
        else
          S_OK
        end
      }.pointer
      vtable[VTBL_GIVE_FEEDBACK] = ->(_object : Void*, _effect : UInt32) : Int32 {
        DRAGDROP_S_USEDEFAULTCURSORS
      }.pointer
      @@drop_source_vtable = vtable
    end

    # :nodoc:
    def self.payload(object : Void*) : NativeDesktop::DragPayload?
      pointer = object.as(Pointer(Void*))[2]
      return nil if pointer.null?
      Box(NativeDesktop::DragPayload).unbox(pointer)
    end

    # :nodoc:
    def self.supported?(payload : NativeDesktop::DragPayload, format : LibWin32Drag::FormatEtc) : Bool
      return false unless format.aspect == DVASPECT_CONTENT
      return false unless format.index == -1
      return false if (format.medium & TYMED_HGLOBAL) == 0

      case payload.kind
      when .file?, .image?
        format.cf_format == CF_HDROP
      when .text?, .url?
        format.cf_format == CF_UNICODETEXT
      else
        false
      end
    end

    private def build_data_object_vtable : Nil
      vtable = LibWin32Drag.CoTaskMemAlloc(12_u64 * sizeof(Void*)).as(Pointer(Void*))
      return if vtable.null?

      vtable[VTBL_QUERY_INTERFACE] = ->(object : Void*, iid : Void*, result : Void**) : Int32 {
        DragSource.query_interface(object, iid, result, IDATA_OBJECT_IID)
      }.pointer
      vtable[VTBL_ADD_REF] = ->(object : Void*) : UInt32 { DragSource.com_add_ref(object) }.pointer
      vtable[VTBL_RELEASE] = ->(object : Void*) : UInt32 { DragSource.com_release(object) }.pointer
      vtable[VTBL_GET_DATA] = ->(object : Void*, requested : LibWin32Drag::FormatEtc*, medium : LibWin32Drag::StgMedium*) : Int32 {
        return E_POINTER if requested.null? || medium.null?
        item = DragSource.payload(object)
        return DV_E_FORMATETC unless item && DragSource.supported?(item, requested.value)
        if item.kind.file? || item.kind.image?
          DragSource.provide_file_drop(item.value, medium)
        else
          DragSource.provide_unicode_text(item.value, medium)
        end
      }.pointer
      vtable[VTBL_GET_DATA_HERE] = ->(_object : Void*, _requested : Void*, _medium : Void*) : Int32 { E_NOTIMPL }.pointer
      vtable[VTBL_QUERY_GET_DATA] = ->(object : Void*, requested : LibWin32Drag::FormatEtc*) : Int32 {
        return E_POINTER if requested.null?
        item = DragSource.payload(object)
        item && DragSource.supported?(item, requested.value) ? S_OK : DV_E_FORMATETC
      }.pointer
      vtable[VTBL_GET_CANONICAL_FORMAT_ETC] = ->(_object : Void*, _input : Void*, _output : Void*) : Int32 { E_NOTIMPL }.pointer
      vtable[VTBL_SET_DATA] = ->(_object : Void*, _format : Void*, _medium : Void*, _release : Int32) : Int32 { E_NOTIMPL }.pointer
      vtable[VTBL_ENUM_FORMAT_ETC] = ->(_object : Void*, _direction : UInt32, result : Void**) : Int32 {
        result.value = Pointer(Void).null unless result.null?
        E_NOTIMPL
      }.pointer
      vtable[VTBL_D_ADVISE] = ->(_object : Void*, _format : Void*, _flags : UInt32, _sink : Void*, _connection : UInt32*) : Int32 { E_NOTIMPL }.pointer
      vtable[VTBL_D_UNADVISE] = ->(_object : Void*, _connection : UInt32) : Int32 { E_NOTIMPL }.pointer
      vtable[VTBL_ENUM_D_ADVISE] = ->(_object : Void*, result : Void**) : Int32 {
        result.value = Pointer(Void).null unless result.null?
        E_NOTIMPL
      }.pointer
      @@data_object_vtable = vtable
    end

    # :nodoc:
    def self.provide_unicode_text(value : String, medium : LibWin32Drag::StgMedium*) : Int32
      units = value.to_utf16
      size = (units.size + 1) * sizeof(UInt16)
      memory = LibWin32Drag.GlobalAlloc(DND_GMEM_MOVEABLE | GMEM_ZEROINIT, size.to_u64)
      return E_OUTOFMEMORY if memory.null?

      locked = LibWin32Drag.GlobalLock(memory)
      if locked.null?
        LibWin32Drag.GlobalFree(memory)
        return E_OUTOFMEMORY
      end
      target = locked.as(UInt16*)
      units.each_with_index { |unit, index| target[index] = unit }
      target[units.size] = 0_u16
      LibWin32Drag.GlobalUnlock(memory)
      DragSource.set_medium(medium, memory)
      S_OK
    end

    # :nodoc:
    def self.provide_file_drop(path : String, medium : LibWin32Drag::StgMedium*) : Int32
      units = path.to_utf16
      header_size = 20
      size = header_size + (units.size + 2) * sizeof(UInt16)
      memory = LibWin32Drag.GlobalAlloc(DND_GMEM_MOVEABLE | GMEM_ZEROINIT, size.to_u64)
      return E_OUTOFMEMORY if memory.null?

      locked = LibWin32Drag.GlobalLock(memory)
      if locked.null?
        LibWin32Drag.GlobalFree(memory)
        return E_OUTOFMEMORY
      end
      locked.as(Pointer(UInt32)).value = header_size.to_u32
      locked.as(Pointer(UInt32))[4] = 1_u32
      target = (locked + header_size).as(UInt16*)
      units.each_with_index { |unit, index| target[index] = unit }
      target[units.size] = 0_u16
      target[units.size + 1] = 0_u16
      LibWin32Drag.GlobalUnlock(memory)
      DragSource.set_medium(medium, memory)
      S_OK
    end

    # :nodoc:
    def self.set_medium(target : LibWin32Drag::StgMedium*, memory : Void*) : Nil
      value = LibWin32Drag::Medium.new
      value.h_global = memory
      result = LibWin32Drag::StgMedium.new
      result.medium = TYMED_HGLOBAL
      result.value = value
      result.release = Pointer(Void).null
      target.value = result
    end
  end
end
