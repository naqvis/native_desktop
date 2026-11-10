require "./win32_common"

module NativeDesktop
  module Platform
    module Windows
      # Shared HICON construction helpers used by both `Tray` and `Toolbar`
      # Windows backends. Dispatches an `IconSource` (bytes or theme name)
      # to the right Win32/GDI+ API, keeping a single GDI+ startup per
      # process.
      module IconHelpers
        extend self

        # GDI+ token for PNG → HICON conversion
        @@gdip_token : UInt64 = 0
        @@gdip_started = false

        # Start GDI+ once for the process.
        def ensure_gdiplus
          return if @@gdip_started
          # GdiplusStartupInput: GdiplusVersion(4) + padding(4) +
          # DebugEventCallback(8) + SuppressBackgroundThread(4) +
          # SuppressExternalCodecs(4) = 24
          input = Bytes.new(24, 0_u8)
          IO::ByteFormat::LittleEndian.encode(1_u32, input[0, 4])
          LibGdiplus.GdiplusStartup(pointerof(@@gdip_token), input.to_unsafe, Pointer(Void).null)
          @@gdip_started = true
        end

        # Call IUnknown::Release on a COM object (vtable index 2).
        # COM object layout: first qword is a pointer to the vtable;
        # vtable is an array of function pointers; Release is index 2.
        def com_release(obj : Void*) : Nil
          return if obj.null?
          vtable = obj.as(Pointer(Void*)).value
          release_ptr = vtable.as(Pointer(Void*))[2]
          release_fn = Proc(Void*, UInt32).new(release_ptr, Pointer(Void).null)
          release_fn.call(obj)
        end

        # Decode PNG/ICO bytes into an HICON via GDI+ (SHCreateMemStream ->
        # GdipCreateBitmapFromStream -> GdipCreateHICONFromBitmap).
        def load_icon_from_bytes(bytes : Bytes) : Void*
          ensure_gdiplus
          hicon = Pointer(Void).null
          stream = LibShlwapi.SHCreateMemStream(bytes.to_unsafe, bytes.size.to_u32)
          return hicon if stream.null?

          bitmap = Pointer(Void).null
          status = LibGdiplus.GdipCreateBitmapFromStream(stream, pointerof(bitmap))
          if status == 0 && !bitmap.null?
            LibGdiplus.GdipCreateHICONFromBitmap(bitmap, pointerof(hicon))
            LibGdiplus.GdipDisposeImage(bitmap)
          end
          com_release(stream) # Release the IStream (caller owns it)
          hicon
        end

        # Maps lowercase theme names to IDI_* resource IDs.
        THEME_TO_IDI = {
          "application" => 32512_u16, # IDI_APPLICATION
          "asterisk"    => 32516_u16, # IDI_ASTERISK
          "error"       => 32513_u16, # IDI_HAND / IDI_ERROR
          "question"    => 32514_u16, # IDI_QUESTION
          "warning"     => 32515_u16, # IDI_EXCLAMATION / IDI_WARNING
          "winlogo"     => 32517_u16, # IDI_WINLOGO
          "information" => 32516_u16, # IDI_INFORMATION
          "shield"      => 32518_u16, # IDI_SHIELD
        }

        # Load a stock system icon by theme name, falling back to
        # IDI_APPLICATION when the name isn't recognised.
        def load_icon_from_theme(name : String) : Void*
          idi = THEME_TO_IDI[name.downcase]? || 32512_u16 # IDI_APPLICATION fallback
          LibGDI32.LoadIconW(Pointer(Void).null, Pointer(UInt16).new(idi.to_u64))
        end

        # Dispatch an `IconSource` to the right HICON helper.
        def hicon_from_source(icon) : Void*
          return Pointer(Void).null unless icon
          if b = icon.bytes
            load_icon_from_bytes(b)
          elsif n = icon.name
            load_icon_from_theme(n)
          else
            Pointer(Void).null
          end
        end
      end
    end
  end
end
