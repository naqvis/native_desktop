require "log"

# Shared UTF-16 string conversion helpers for Windows platform modules.
# Centralizes string encoding/decoding to avoid duplication and errors.

module NativeDesktop
  module Platform
    module Windows
      module StringHelpers
        extend self

        # Convert a Crystal String to a null-terminated UTF-16LE array.
        # Returns an Array(UInt16) suitable for passing to Win32 APIs.
        def to_utf16(s : String) : Array(UInt16)
          encoded = s.encode("UTF-16LE")
          result = Array(UInt16).new(encoded.size // 2 + 1, 0_u16)
          (encoded.size // 2).times do |i|
            result[i] = IO::ByteFormat::LittleEndian.decode(UInt16, encoded[i * 2, 2])
          end
          result
        end

        # Convert a null-terminated UTF-16LE pointer to a Crystal String.
        def from_utf16(ptr : UInt16*) : String
          return "" if ptr.null?

          len = 0
          while ptr[len] != 0_u16
            len += 1
          end

          return "" if len == 0

          bytes = Bytes.new(len * 2)
          len.times { |i| IO::ByteFormat::LittleEndian.encode(ptr[i], bytes[i * 2, 2]) }
          String.new(bytes, "UTF-16LE")
        end

        # Convert a Crystal String to UTF-16LE bytes with null terminator.
        # Returns Bytes suitable for memory operations.
        def to_utf16_bytes(s : String) : Bytes
          encoded = s.encode("UTF-16LE")
          # Append null terminator (2 bytes)
          encoded + Bytes[0, 0]
        end

        # Execute a block with a temporary UTF-16 string pointer.
        # Automatically manages memory and ensures proper cleanup.
        def with_utf16(s : String, & : UInt16* ->)
          utf16 = to_utf16(s)
          yield utf16.to_unsafe
        end

        # Execute a block with a temporary UTF-16 bytes pointer.
        # Automatically manages memory and ensures proper cleanup.
        def with_utf16_bytes(s : String, & : UInt16* ->)
          bytes = to_utf16_bytes(s)
          yield bytes.to_unsafe.as(UInt16*)
        end
      end
    end
  end
end
