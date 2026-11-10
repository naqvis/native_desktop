{% if flag?(:darwin) %}
  require "./objc"

  module NativeDesktop::Platform::Clipboard
    extend self

    private def pasteboard : Void*
      MacOS::ObjC.msg(MacOS::ObjC.klass("NSPasteboard"), "generalPasteboard")
    end

    private def read(type : String) : String?
      MacOS::ObjC.to_s(MacOS::ObjC.msg(pasteboard, "stringForType:", MacOS::ObjC.string(type)))
    end

    private def write(value : String, type : String) : Nil
      board = pasteboard
      MacOS::ObjC.msg(board, "clearContents")
      MacOS::ObjC.msg(board, "setString:forType:", MacOS::ObjC.string(value), MacOS::ObjC.string(type))
    end

    def read_text : String
      MacOS::ObjC.pool { read("public.utf8-plain-text") || "" }
    end

    def write_text(text : String) : Nil
      MacOS::ObjC.pool { write(text, "public.utf8-plain-text") }
    end

    def read_html : String?
      MacOS::ObjC.pool { read("public.html") }
    end

    def write_html(html : String) : Nil
      MacOS::ObjC.pool do
        board = pasteboard
        MacOS::ObjC.msg(board, "clearContents")
        MacOS::ObjC.msg(board, "setString:forType:", MacOS::ObjC.string(html), MacOS::ObjC.string("public.html"))
        plain = html.gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip
        MacOS::ObjC.msg(board, "setString:forType:", MacOS::ObjC.string(plain), MacOS::ObjC.string("public.utf8-plain-text"))
      end
    end

    def read_rtf : String?
      MacOS::ObjC.pool { read("public.rtf") }
    end

    def write_rtf(rtf : String) : Nil
      MacOS::ObjC.pool { write(rtf, "public.rtf") }
    end

    def read_image : Bytes?
      MacOS::ObjC.pool do
        data = MacOS::ObjC.msg(pasteboard, "dataForType:", MacOS::ObjC.string("public.png"))
        next nil if data.null?
        size = MacOS::ObjC.long(data, "length")
        next nil if size <= 0
        source = MacOS::ObjC.msg(data, "bytes").as(UInt8*)
        result = Bytes.new(size)
        Bytes.new(source, size).copy_to(result)
        result
      end
    end

    def write_image(data : Bytes) : Nil
      MacOS::ObjC.pool do
        board = pasteboard
        MacOS::ObjC.msg(board, "clearContents")
        MacOS::ObjC.msg(board, "setData:forType:", MacOS::ObjC.data(data), MacOS::ObjC.string("public.png"))
      end
    end

    def clear : Nil
      MacOS::ObjC.pool { MacOS::ObjC.msg(pasteboard, "clearContents") }
    end

    def version : UInt64
      MacOS::ObjC.pool { MacOS::ObjC.long(pasteboard, "changeCount").to_u64 }
    end
  end
{% end %}
