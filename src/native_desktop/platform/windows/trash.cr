require "./win32_common"
require "./string_helpers"

module NativeDesktop::Platform::Trash
  extend self

  FO_DELETE                = 0x0003_u32
  FOF_ALLOWUNDO            = 0x0040_u16
  FOF_NOCONFIRMATION       = 0x0010_u16
  FOF_SILENT               = 0x0004_u16
  FOF_NOERRORUI            = 0x0400_u16
  COINIT_APARTMENTTHREADED =    0x2_u32
  RPC_E_CHANGED_MODE       = 0x80010106_u32.unsafe_as(Int32)

  @[Link("shell32")]
  lib LibNativeDesktopTrash
    struct Operation
      hwnd : Void*
      function : UInt32
      from : UInt16*
      to : UInt16*
      flags : UInt16
      aborted : Int32
      mappings : Void*
      progress_title : UInt16*
    end

    fun perform = SHFileOperationW(operation : Operation*) : Int32
  end

  def move(path : String) : Nil
    initialized = false
    result = Windows::LibOLE.CoInitializeEx(nil, COINIT_APARTMENTTHREADED)
    if result >= 0
      initialized = true
    elsif result != RPC_E_CHANGED_MODE
      raise TrashError.new("could not initialize the Windows shell", :trash_failed)
    end

    begin
      from = Windows::StringHelpers.to_utf16(path)
      from << 0_u16
      operation = LibNativeDesktopTrash::Operation.new
      operation.hwnd = Pointer(Void).null
      operation.function = FO_DELETE
      operation.from = from.to_unsafe
      operation.to = Pointer(UInt16).null
      operation.flags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI
      operation.aborted = 0
      operation.mappings = Pointer(Void).null
      operation.progress_title = Pointer(UInt16).null

      result = LibNativeDesktopTrash.perform(pointerof(operation))
      raise TrashError.new("the Windows trash operation was canceled", :trash_failed) if operation.aborted != 0
      return if result == 0
      code = case result
             when 2, 3 then :file_not_found
             when 5    then :permission_denied
             else           :trash_failed
             end
      raise TrashError.new("Windows could not move #{path} to the Recycle Bin (code #{result})", code)
    ensure
      Windows::LibOLE.CoUninitialize if initialized
    end
  end
end
