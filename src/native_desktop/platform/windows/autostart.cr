require "./win32_common"

{% if flag?(:windows) %}
  module NativeDesktop::Platform::Autostart
    extend self
    ROOT            = Pointer(Void).new(0x80000001_u64)
    DEFAULT_KEY     = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
    KEY_QUERY_VALUE = 0x0001_u32
    KEY_SET_VALUE   = 0x0002_u32
    REG_SZ          =      1_u32
    FILE_NOT_FOUND  =      2_i32

    def enable(entry : AutostartEntry) : Nil
      arguments = entry.arguments.dup
      arguments << "--minimized" if entry.minimized
      command = ([quote(entry.executable.to_s)] + arguments.map { |argument| quote(argument) }).join(' ')
      with_key(KEY_SET_VALUE, create: true) { |key| set_value(key, entry.name, command) }
    rescue ex
      raise Error.new("failed to enable autostart for #{entry.name.inspect}: #{ex.message}", :autostart_failed)
    end

    def disable(name : String) : Nil
      with_key(KEY_SET_VALUE) do |key|
        buffer = wide(name)
        status = Windows::LibAdvApi32.RegDeleteValueW(key, buffer.to_unsafe)
        unless status == 0 || status == FILE_NOT_FOUND
          raise Error.new("RegDeleteValueW failed (#{status})", :autostart_failed)
        end
      end
    end

    def enabled?(name : String) : Bool
      found = false
      with_key(KEY_QUERY_VALUE) do |key|
        buffer = wide(name)
        type = LibC::RegistryRoutineFlags::NONE
        size = 0_u32
        found = LibC.RegQueryValueExW(key.as(LibC::HKEY), buffer.to_unsafe, nil, pointerof(type), nil, pointerof(size)) == 0
      end
      found
    rescue
      false
    end

    private def key_path : String
      value = ENV["NATIVE_DESKTOP_AUTOSTART_KEY"]? || ENV["WEBVIEW_AUTOSTART_KEY"]? || DEFAULT_KEY
      value.starts_with?("HKCU\\") ? value[5..] : value
    end

    private def with_key(access : UInt32, create = false, &block : Void* ->) : Nil
      path = wide(key_path)
      key = Pointer(Void).null
      status = if create
                 Windows::LibAdvApi32.RegCreateKeyExW(ROOT, path.to_unsafe, 0, Pointer(UInt16).null, 0, access, Pointer(Void).null, pointerof(key), Pointer(UInt32).null)
               else
                 native = Pointer(Void).null.as(LibC::HKEY)
                 result = LibC.RegOpenKeyExW(LibC::HKEY_CURRENT_USER, path.to_unsafe, 0, LibC::REGSAM.new(access.to_i32!), pointerof(native))
                 key = native.as(Void*)
                 result
               end
      raise Error.new("could not open autostart registry key (#{status})", :autostart_failed) unless status == 0
      begin
        block.call(key)
      ensure
        LibC.RegCloseKey(key.as(LibC::HKEY))
      end
    end

    private def set_value(key : Void*, name : String, value : String) : Nil
      name_buffer = wide(name)
      value_buffer = wide(value)
      status = Windows::LibAdvApi32.RegSetValueExW(key, name_buffer.to_unsafe, 0, REG_SZ, value_buffer.to_unsafe.as(UInt8*), (value_buffer.size * 2).to_u32)
      raise Error.new("RegSetValueExW failed (#{status})", :autostart_failed) unless status == 0
    end

    private def quote(value : String) : String
      return %("") if value.empty?
      return value unless value.each_char.any? { |character| character.whitespace? || character == '"' }

      String.build do |result|
        result << '"'
        backslashes = 0
        value.each_char do |character|
          if character == '\\'
            backslashes += 1
          elsif character == '"'
            result << "\\" * (backslashes * 2 + 1)
            result << '"'
            backslashes = 0
          else
            result << "\\" * backslashes
            result << character
            backslashes = 0
          end
        end
        result << "\\" * (backslashes * 2)
        result << '"'
      end
    end

    private def wide(value : String) : Slice(UInt16)
      units = value.to_utf16
      Slice(UInt16).new(units.size + 1, 0_u16).tap { |buffer| units.each_with_index { |unit, index| buffer[index] = unit } }
    end
  end
{% end %}
