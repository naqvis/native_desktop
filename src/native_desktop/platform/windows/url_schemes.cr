require "./win32_common"

{% if flag?(:windows) %}
  module NativeDesktop::Platform::URLSchemes
    extend self
    ROOT          = Pointer(Void).new(0x80000001_u64)
    KEY_SET_VALUE = 0x0002_u32
    REG_SZ        =      1_u32

    def register(scheme : String, name : String, executable : Path) : Nil
      root = "Software\\Classes\\#{scheme}"
      set_string(root, "", "URL:#{name} Protocol")
      set_string(root, "URL Protocol", "")
      set_string("#{root}\\shell\\open\\command", "", "\"#{executable}\" \"%1\"")
    rescue ex : Error
      raise ex
    rescue ex
      raise Error.new("failed to register URL scheme #{scheme.inspect}: #{ex.message}", :url_scheme_registration_failed)
    end

    def unregister(scheme : String) : Nil
      path = wide("Software\\Classes\\#{scheme}")
      Windows::LibAdvApi32.RegDeleteTreeW(ROOT, path.to_unsafe)
    end

    private def set_string(path : String, name : String, value : String) : Nil
      path_buffer = wide(path)
      key = Pointer(Void).null
      status = Windows::LibAdvApi32.RegCreateKeyExW(ROOT, path_buffer.to_unsafe, 0, Pointer(UInt16).null, 0, KEY_SET_VALUE, Pointer(Void).null, pointerof(key), Pointer(UInt32).null)
      raise Error.new("RegCreateKeyExW failed (#{status})", :url_scheme_registration_failed) unless status == 0
      begin
        name_buffer = wide(name)
        value_buffer = wide(value)
        status = Windows::LibAdvApi32.RegSetValueExW(key, name_buffer.to_unsafe, 0, REG_SZ, value_buffer.to_unsafe.as(UInt8*), (value_buffer.size * 2).to_u32)
        raise Error.new("RegSetValueExW failed (#{status})", :url_scheme_registration_failed) unless status == 0
      ensure
        LibC.RegCloseKey(key.as(LibC::HKEY))
      end
    end

    private def wide(value : String) : Slice(UInt16)
      units = value.to_utf16
      Slice(UInt16).new(units.size + 1, 0_u16).tap { |buffer| units.each_with_index { |unit, index| buffer[index] = unit } }
    end
  end
{% end %}
