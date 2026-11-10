require "./win32_common"

{% if flag?(:windows) %}
  require "digest/sha256"

  module NativeDesktop::Platform::FileAssociations
    extend self
    ROOT               = Pointer(Void).new(0x80000001_u64)
    KEY_SET_VALUE      =     0x0002_u32
    REG_SZ             =          1_u32
    FILE_NOT_FOUND     =          2_i32
    SHCNE_ASSOCCHANGED = 0x08000000_i32
    SHCNF_IDLIST       =     0x0000_u32

    def register(association : NativeDesktop::FileAssociation) : Nil
      ext = association.extension
      prog_id = prog_id(association)

      set_string("Software\\Classes\\#{ext}\\OpenWithProgids", prog_id, "")
      set_string("Software\\Classes\\#{prog_id}", "", association.type_name)
      set_string("Software\\Classes\\#{prog_id}\\shell\\open\\command", "", "\"#{association.executable}\" \"%1\"")
      notify_shell
    rescue ex : NativeDesktop::Error
      raise ex
    rescue ex
      raise NativeDesktop::Error.new("failed to register file type #{association.extension.inspect}: #{ex.message}", :file_association_failed)
    end

    def unregister(association : NativeDesktop::FileAssociation) : Nil
      prog_id = prog_id(association)

      delete_value("Software\\Classes\\#{association.extension}\\OpenWithProgids", prog_id)
      delete_tree("Software\\Classes\\#{prog_id}")
      notify_shell
    rescue ex : NativeDesktop::Error
      raise ex
    rescue ex
      raise NativeDesktop::Error.new("failed to unregister file type #{association.extension.inspect}: #{ex.message}", :file_association_failed)
    end

    # :nodoc:
    def prog_id(association : NativeDesktop::FileAssociation) : String
      digest = Digest::SHA256.hexdigest("#{association.application_id}\0#{association.extension}")
      "NativeDesktop.#{digest[0, 24]}"
    end

    private def delete_value(path : String, name : String) : Nil
      path_buffer = wide(path)
      native = Pointer(Void).null.as(LibC::HKEY)
      status = LibC.RegOpenKeyExW(
        LibC::HKEY_CURRENT_USER,
        path_buffer.to_unsafe,
        0,
        LibC::REGSAM::SET_VALUE,
        pointerof(native)
      )
      return if status == FILE_NOT_FOUND
      raise NativeDesktop::Error.new("RegOpenKeyExW failed (#{status})", :file_association_failed) unless status == 0
      begin
        name_buffer = wide(name)
        status = Windows::LibAdvApi32.RegDeleteValueW(native.as(Void*), name_buffer.to_unsafe)
        unless status == 0 || status == FILE_NOT_FOUND
          raise NativeDesktop::Error.new("RegDeleteValueW failed (#{status})", :file_association_failed)
        end
      ensure
        LibC.RegCloseKey(native)
      end
    end

    private def delete_tree(path : String) : Nil
      path_buffer = wide(path)
      status = Windows::LibAdvApi32.RegDeleteTreeW(ROOT, path_buffer.to_unsafe)
      unless status == 0 || status == FILE_NOT_FOUND
        raise NativeDesktop::Error.new("RegDeleteTreeW failed (#{status})", :file_association_failed)
      end
    end

    private def set_string(path : String, name : String, value : String) : Nil
      path_buffer = wide(path)
      key = Pointer(Void).null
      status = Windows::LibAdvApi32.RegCreateKeyExW(ROOT, path_buffer.to_unsafe, 0, Pointer(UInt16).null, 0, KEY_SET_VALUE, Pointer(Void).null, pointerof(key), Pointer(UInt32).null)
      raise NativeDesktop::Error.new("RegCreateKeyExW failed (#{status})", :file_association_failed) unless status == 0
      begin
        name_buffer = wide(name)
        value_buffer = wide(value)
        status = Windows::LibAdvApi32.RegSetValueExW(key, name_buffer.to_unsafe, 0, REG_SZ, value_buffer.to_unsafe.as(UInt8*), (value_buffer.size * 2).to_u32)
        raise NativeDesktop::Error.new("RegSetValueExW failed (#{status})", :file_association_failed) unless status == 0
      ensure
        LibC.RegCloseKey(key.as(LibC::HKEY))
      end
    end

    private def wide(value : String) : Slice(UInt16)
      units = value.to_utf16
      Slice(UInt16).new(units.size + 1, 0_u16).tap { |buffer| units.each_with_index { |unit, index| buffer[index] = unit } }
    end

    private def notify_shell : Nil
      Windows::LibShell32.SHChangeNotify(
        SHCNE_ASSOCCHANGED,
        SHCNF_IDLIST,
        Pointer(Void).null,
        Pointer(Void).null
      )
    end
  end
{% end %}
