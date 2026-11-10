{% if flag?(:windows) %}
  require "./win32_common"

  module NativeDesktop::Platform::Clipboard
    extend self

    CF_UNICODETEXT = 13_u32
    CF_DIB         =  8_u32

    @@html_format : UInt32?
    @@rtf_format : UInt32?

    private def with_clipboard(&block : -> T) : T forall T
      opened = false
      5.times do |attempt|
        if Windows::LibUser32.OpenClipboard(Pointer(Void).null) != 0
          opened = true
          break
        end
        sleep 10.milliseconds if attempt < 4
      end
      raise Error.new("OpenClipboard failed", :clipboard_error) unless opened
      begin
        block.call
      ensure
        Windows::LibUser32.CloseClipboard
      end
    end

    private def registered_format(name : String) : UInt32
      units = name.to_utf16
      buffer = Slice(UInt16).new(units.size + 1, 0_u16)
      units.each_with_index { |unit, index| buffer[index] = unit }
      Windows::LibUser32.RegisterClipboardFormatW(buffer.to_unsafe)
    end

    private def html_format : UInt32
      @@html_format ||= registered_format("HTML Format")
    end

    private def rtf_format : UInt32
      @@rtf_format ||= registered_format("Rich Text Format")
    end

    private def read_bytes(format : UInt32) : Bytes?
      return nil if Windows::LibUser32.IsClipboardFormatAvailable(format) == 0
      with_clipboard do
        memory = Windows::LibUser32.GetClipboardData(format)
        next nil if memory.null?
        pointer = Windows::LibKernel32.GlobalLock(memory)
        next nil if pointer.null?
        size = Windows::LibKernel32.GlobalSize(memory).to_i
        begin
          bytes = Bytes.new(pointer.as(UInt8*), size)
          terminator = bytes.index(0_u8) || bytes.size
          bytes[0, terminator].dup
        ensure
          Windows::LibKernel32.GlobalUnlock(memory)
        end
      end
    end

    private def write_bytes(format : UInt32, data : Bytes) : Nil
      with_clipboard do
        Windows::LibUser32.EmptyClipboard
        write_bytes_open(format, data)
      end
    end

    private def write_bytes_open(format : UInt32, data : Bytes) : Nil
      memory = Windows::LibKernel32.GlobalAlloc(Windows::LibKernel32::GMEM_MOVEABLE, data.size + 1)
      raise Error.new("GlobalAlloc failed", :clipboard_error) if memory.null?
      locked = Windows::LibKernel32.GlobalLock(memory)
      if locked.null?
        Windows::LibKernel32.GlobalFree(memory)
        raise Error.new("GlobalLock failed", :clipboard_error)
      end
      pointer = locked.as(UInt8*)
      data.copy_to(Slice.new(pointer, data.size))
      pointer[data.size] = 0_u8
      Windows::LibKernel32.GlobalUnlock(memory)
      if Windows::LibUser32.SetClipboardData(format, memory).null?
        Windows::LibKernel32.GlobalFree(memory)
        raise Error.new("SetClipboardData failed", :clipboard_error)
      end
    end

    private def write_text_open(text : String) : Nil
      units = text.to_utf16
      size = (units.size + 1) * sizeof(UInt16)
      memory = Windows::LibKernel32.GlobalAlloc(Windows::LibKernel32::GMEM_MOVEABLE, size)
      raise Error.new("GlobalAlloc failed", :clipboard_error) if memory.null?
      locked = Windows::LibKernel32.GlobalLock(memory)
      if locked.null?
        Windows::LibKernel32.GlobalFree(memory)
        raise Error.new("GlobalLock failed", :clipboard_error)
      end
      pointer = locked.as(UInt16*)
      units.each_with_index { |unit, index| pointer[index] = unit }
      pointer[units.size] = 0_u16
      Windows::LibKernel32.GlobalUnlock(memory)
      if Windows::LibUser32.SetClipboardData(CF_UNICODETEXT, memory).null?
        Windows::LibKernel32.GlobalFree(memory)
        raise Error.new("SetClipboardData failed", :clipboard_error)
      end
    end

    def read_text : String
      with_clipboard do
        memory = Windows::LibUser32.GetClipboardData(CF_UNICODETEXT)
        next "" if memory.null?
        pointer = Windows::LibKernel32.GlobalLock(memory)
        next "" if pointer.null?
        begin
          String.from_utf16(pointer.as(UInt16*))[0]
        ensure
          Windows::LibKernel32.GlobalUnlock(memory)
        end
      end
    end

    def write_text(text : String) : Nil
      with_clipboard do
        Windows::LibUser32.EmptyClipboard
        write_text_open(text)
      end
    end

    def read_image : Bytes?
      return nil if Windows::LibUser32.IsClipboardFormatAvailable(CF_DIB) == 0
      with_clipboard do
        memory = Windows::LibUser32.GetClipboardData(CF_DIB)
        next nil if memory.null?
        pointer = Windows::LibKernel32.GlobalLock(memory)
        next nil if pointer.null?
        size = Windows::LibKernel32.GlobalSize(memory).to_i
        begin
          Bytes.new(pointer.as(UInt8*), size).dup
        ensure
          Windows::LibKernel32.GlobalUnlock(memory)
        end
      end
    end

    def write_image(data : Bytes) : Nil
      with_clipboard do
        Windows::LibUser32.EmptyClipboard
        memory = Windows::LibKernel32.GlobalAlloc(Windows::LibKernel32::GMEM_MOVEABLE, data.size)
        raise Error.new("GlobalAlloc failed", :clipboard_error) if memory.null?
        locked = Windows::LibKernel32.GlobalLock(memory)
        if locked.null?
          Windows::LibKernel32.GlobalFree(memory)
          raise Error.new("GlobalLock failed", :clipboard_error)
        end
        pointer = locked.as(UInt8*)
        data.copy_to(Slice.new(pointer, data.size))
        Windows::LibKernel32.GlobalUnlock(memory)
        if Windows::LibUser32.SetClipboardData(CF_DIB, memory).null?
          Windows::LibKernel32.GlobalFree(memory)
          raise Error.new("SetClipboardData failed", :clipboard_error)
        end
      end
    end

    def read_html : String?
      read_bytes(html_format).try { |bytes| String.new(bytes) }
    end

    def write_html(html : String) : Nil
      template = "Version:0.9\r\nStartHTML:00000000\r\nEndHTML:00000000\r\nStartFragment:00000000\r\nEndFragment:00000000\r\n"
      start_html = template.bytesize
      start_marker = "<!--StartFragment-->"
      end_marker = "<!--EndFragment-->"
      body = start_marker + html + end_marker
      start_fragment = start_html + start_marker.bytesize
      end_fragment = start_fragment + html.bytesize
      end_html = start_html + body.bytesize
      header = "Version:0.9\r\nStartHTML:#{start_html.to_s.rjust(8, '0')}\r\nEndHTML:#{end_html.to_s.rjust(8, '0')}\r\nStartFragment:#{start_fragment.to_s.rjust(8, '0')}\r\nEndFragment:#{end_fragment.to_s.rjust(8, '0')}\r\n"
      with_clipboard do
        Windows::LibUser32.EmptyClipboard
        write_bytes_open(html_format, (header + body).to_slice)
        write_text_open(html.gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip)
      end
    end

    def read_rtf : String?
      read_bytes(rtf_format).try { |bytes| String.new(bytes) }
    end

    def write_rtf(rtf : String) : Nil
      write_bytes(rtf_format, rtf.to_slice)
    end

    def clear : Nil
      with_clipboard { Windows::LibUser32.EmptyClipboard }
    end

    def version : UInt64
      Windows::LibUser32.GetClipboardSequenceNumber.to_u64
    end
  end
{% end %}
