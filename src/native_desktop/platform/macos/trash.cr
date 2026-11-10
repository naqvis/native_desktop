require "./objc_runtime"

module NativeDesktop::Platform::Trash
  extend self

  NO_SUCH_FILE        =   4
  WRITE_NO_PERMISSION = 513

  def move(path : String) : Nil
    MacOS::ObjCRuntime.with_autorelease_pool do
      manager = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSFileManager"), "defaultManager")
      raise TrashError.new("NSFileManager is unavailable", :trash_failed) if manager.null?
      url = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSURL"), "fileURLWithPath:", MacOS::ObjCRuntime.nsstring(path))
      raise TrashError.new("could not create a file URL for #{path}", :trash_failed) if url.null?

      resulting_url = Pointer(Void).null
      error = Pointer(Void).null
      return if MacOS::ObjCRuntime.msg_bool_ptr(
                  manager,
                  "trashItemAtURL:resultingItemURL:error:",
                  url,
                  pointerof(resulting_url),
                  pointerof(error),
                ) != 0
      raise_error(path, error)
    end
  end

  private def raise_error(path : String, error : Void*) : NoReturn
    raise TrashError.new("could not move #{path} to trash", :trash_failed) if error.null?
    native_code = MacOS::ObjCRuntime.msg_long(error, "code")
    message = MacOS::ObjCRuntime.nsstring_to_s(MacOS::ObjCRuntime.msg(error, "localizedDescription")) || "unknown error"
    code = case native_code
           when NO_SUCH_FILE        then :file_not_found
           when WRITE_NO_PERMISSION then :permission_denied
           else                          :trash_failed
           end
    raise TrashError.new("could not move #{path} to trash: #{message}", code)
  end
end
