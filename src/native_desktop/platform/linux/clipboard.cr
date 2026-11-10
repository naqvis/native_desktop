{% if flag?(:linux) %}
  module NativeDesktop::Platform::Clipboard
    extend self

    TEXT_INFO = 1_u32
    HTML_INFO = 2_u32
    RTF_INFO  = 3_u32
    PNG_INFO  = 4_u32

    @[Link("gtk-3", pkg_config: "gtk+-3.0")]
    lib LibGTKClipboard
      struct TargetEntry
        target : UInt8*
        flags : UInt32
        info : UInt32
      end

      fun gdk_atom_intern_static_string(name : UInt8*) : Void*
      fun gtk_clipboard_get(selection : Void*) : Void*
      fun gtk_clipboard_wait_for_contents(clipboard : Void*, target : Void*) : Void*
      fun gtk_clipboard_set_with_data(clipboard : Void*, targets : TargetEntry*, count : UInt32, get_func : Void*, clear_func : Void*, data : Void*) : Int32
      fun gtk_clipboard_clear(clipboard : Void*) : Nil
      fun gtk_clipboard_store(clipboard : Void*) : Nil
      fun gtk_selection_data_get_data(selection : Void*) : UInt8*
      fun gtk_selection_data_get_length(selection : Void*) : Int32
      fun gtk_selection_data_set(selection : Void*, type : Void*, format : Int32, data : UInt8*, length : Int32) : Nil
      fun gtk_selection_data_free(selection : Void*) : Nil
    end

    @@lock = Mutex.new
    @@payloads = {} of UInt32 => Bytes
    @@get_callback : (Void*, Void*, UInt32, Void* -> Nil)?
    @@clear_callback : (Void*, Void* -> Nil)?

    private def clipboard : Void*
      selection = LibGTKClipboard.gdk_atom_intern_static_string("CLIPBOARD")
      result = LibGTKClipboard.gtk_clipboard_get(selection)
      raise Error.new("GTK clipboard is unavailable", :clipboard_unavailable) if result.null?
      result
    end

    private def atom(type : String) : Void*
      LibGTKClipboard.gdk_atom_intern_static_string(type)
    end

    private def read(type : String) : Bytes?
      selection = LibGTKClipboard.gtk_clipboard_wait_for_contents(clipboard, atom(type))
      return nil if selection.null?
      begin
        length = LibGTKClipboard.gtk_selection_data_get_length(selection)
        return nil if length <= 0
        pointer = LibGTKClipboard.gtk_selection_data_get_data(selection)
        return nil if pointer.null?
        Bytes.new(pointer, length).dup
      ensure
        LibGTKClipboard.gtk_selection_data_free(selection)
      end
    end

    private def publish(entries : Array({String, UInt32, Bytes})) : Nil
      targets = entries.map do |type, info, _|
        target = LibGTKClipboard::TargetEntry.new
        target.target = type.to_unsafe
        target.flags = 0_u32
        target.info = info
        target
      end
      @@lock.synchronize do
        @@payloads = entries.to_h { |_, info, data| {info, data.dup} }
      end

      get_callback = @@get_callback ||= ->(_clipboard : Void*, selection : Void*, info : UInt32, _data : Void*) {
        payload = @@lock.synchronize { @@payloads[info]?.try(&.dup) }
        if payload
          content_type = case info
                         when TEXT_INFO then "text/plain;charset=utf-8"
                         when HTML_INFO then "text/html"
                         when RTF_INFO  then "text/rtf"
                         else                "image/png"
                         end
          LibGTKClipboard.gtk_selection_data_set(selection, atom(content_type), 8, payload.to_unsafe, payload.size)
        end
      }
      clear_callback = @@clear_callback ||= ->(_clipboard : Void*, _data : Void*) { @@lock.synchronize { @@payloads.clear } }

      result = LibGTKClipboard.gtk_clipboard_set_with_data(
        clipboard, targets.to_unsafe, targets.size.to_u32,
        get_callback.pointer, clear_callback.pointer, Pointer(Void).null
      )
      raise Error.new("GTK rejected clipboard data", :clipboard_error) if result == 0
      LibGTKClipboard.gtk_clipboard_store(clipboard)
    end

    def read_text : String
      read("text/plain;charset=utf-8").try { |data| String.new(data) } ||
        read("UTF8_STRING").try { |data| String.new(data) } || ""
    end

    def write_text(text : String) : Nil
      publish([{"text/plain;charset=utf-8", TEXT_INFO, text.to_slice}])
    end

    def read_html : String?
      read("text/html").try { |data| String.new(data) }
    end

    def write_html(html : String) : Nil
      plain = html.gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip
      publish([
        {"text/html", HTML_INFO, html.to_slice},
        {"text/plain;charset=utf-8", TEXT_INFO, plain.to_slice},
      ])
    end

    def read_rtf : String?
      read("text/rtf").try { |data| String.new(data) }
    end

    def write_rtf(rtf : String) : Nil
      publish([{"text/rtf", RTF_INFO, rtf.to_slice}])
    end

    def read_image : Bytes?
      read("image/png")
    end

    def write_image(data : Bytes) : Nil
      publish([{"image/png", PNG_INFO, data}])
    end

    def clear : Nil
      LibGTKClipboard.gtk_clipboard_clear(clipboard)
    end

    def version : UInt64
      read_text.hash.to_u64
    rescue
      0_u64
    end
  end
{% end %}
