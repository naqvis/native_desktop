{% if flag?(:windows) %}
  require "./win32_common"

  module NativeDesktop::Platform::Applications
    extend self

    def foreground_name : String?
      window = Windows::LibUser32.GetForegroundWindow
      return nil if window.null?
      buffer = Slice(UInt16).new(1024)
      length = Windows::LibUser32.GetWindowModuleFileNameW(window, buffer.to_unsafe, buffer.size.to_u32)
      return nil if length == 0
      File.basename(String.from_utf16(buffer[0, length.to_i])).sub(/\.exe$/i, "")
    rescue
      nil
    end

    def open(target : String, application : String?) : Nil
      target_buffer = wide(target)
      result = if application
                 application_buffer = wide(application)
                 Windows::LibShell32.ShellExecuteW(Pointer(Void).null, Pointer(UInt16).null, application_buffer.to_unsafe, target_buffer.to_unsafe, Pointer(UInt16).null, 1)
               else
                 Windows::LibShell32.ShellExecuteW(Pointer(Void).null, Pointer(UInt16).null, target_buffer.to_unsafe, Pointer(UInt16).null, Pointer(UInt16).null, 1)
               end
      raise Error.new("failed to open #{target.inspect}", :open_failed) if result.address <= 32
    end

    private def wide(value : String) : Slice(UInt16)
      units = value.to_utf16
      Slice(UInt16).new(units.size + 1, 0_u16).tap do |buffer|
        units.each_with_index { |unit, index| buffer[index] = unit }
      end
    end
  end
{% end %}
