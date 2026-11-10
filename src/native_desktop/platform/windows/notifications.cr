{% if flag?(:windows) %}
  require "./win32_common"

  module NativeDesktop::Platform::Notifications
    extend self

    NIF_MESSAGE          = 0x00000001_u32
    NIF_TIP              = 0x00000004_u32
    NIF_INFO             = 0x00000010_u32
    NIM_ADD              = 0x00000000_u32
    NIM_MODIFY           = 0x00000001_u32
    NIM_DELETE           = 0x00000002_u32
    NIIF_INFO            = 0x00000001_u32
    NIIF_ERROR           = 0x00000003_u32
    CALLBACK_MESSAGE     = 0x0000802A_u32
    NIN_BALLOONHIDE      = 0x00000403_u32
    NIN_BALLOONTIMEOUT   = 0x00000404_u32
    NIN_BALLOONUSERCLICK = 0x00000405_u32
    STRUCT_SIZE          =            952

    @@window = Pointer(Void).null
    @@data = Bytes.new(STRUCT_SIZE, 0_u8)
    @@icon_added = false
    @@current_id : String?

    def request_permission(application_name : String) : Bool
      true
    end

    def permission_state : PermissionState
      PermissionState::Granted
    end

    def show(application_name : String, request : NotificationRequest) : Nil
      @@current_id = request.id
      window = notification_window
      raise Error.new("Windows failed to create notification window", :notification_failed) if window.null?

      unless @@icon_added
        build_data(window, NIF_MESSAGE | NIF_TIP, application_name, "", "", 0_u32, nil)
        result = Windows::LibShell32.Shell_NotifyIconW(NIM_ADD, @@data.to_unsafe)
        raise Error.new("Windows failed to create notification icon", :notification_failed) if result == 0
        @@icon_added = true
      end

      info_flags = request.urgency.critical? ? NIIF_ERROR : NIIF_INFO
      build_data(window, NIF_INFO | NIF_TIP, application_name, request.title, request.body, info_flags, request.timeout)
      result = Windows::LibShell32.Shell_NotifyIconW(NIM_MODIFY, @@data.to_unsafe)
      raise Error.new("Windows failed to display notification", :notification_failed) if result == 0
    end

    def close(id : String) : Nil
      return unless @@icon_added
      build_data(@@window, 0_u32, "", "", "", 0_u32, nil)
      Windows::LibShell32.Shell_NotifyIconW(NIM_DELETE, @@data.to_unsafe)
      @@icon_added = false
    end

    private def notification_window : Void*
      return @@window unless @@window.null?

      instance = Windows::LibKernel32.GetModuleHandleW(nil)
      class_name = wide("NativeDesktopNotificationWindow")
      window_class = Bytes.new(80, 0_u8)
      IO::ByteFormat::LittleEndian.encode(80_u32, window_class[0, 4])
      procedure = (->notification_wndproc(Void*, UInt32, UInt64, Int64)).pointer.address.to_u64
      IO::ByteFormat::LittleEndian.encode(procedure, window_class[8, 8])
      IO::ByteFormat::LittleEndian.encode(instance.address, window_class[24, 8])
      IO::ByteFormat::LittleEndian.encode(class_name.to_unsafe.address, window_class[64, 8])
      Windows::LibUser32.RegisterClassExW(window_class.to_unsafe)

      @@window = Windows::LibUser32.CreateWindowExW(
        0_u32,
        class_name.to_unsafe,
        nil,
        0_u32,
        0,
        0,
        0,
        0,
        Pointer(Void).new(-3_i64.to_u64!),
        nil,
        instance,
        nil
      )
    end

    private def notification_wndproc(window : Void*, message : UInt32, w_param : UInt64, l_param : Int64) : Int64
      if message == CALLBACK_MESSAGE
        case l_param.to_u32! & 0xFFFF_u32
        when NIN_BALLOONUSERCLICK
          if id = @@current_id
            NativeDesktop::Platform::NotificationEventSource.emit(
              NotificationEvent.new(id, NotificationEventTypes::Activated)
            )
          end
          return 0_i64
        when NIN_BALLOONHIDE, NIN_BALLOONTIMEOUT
          if id = @@current_id
            NativeDesktop::Platform::NotificationEventSource.emit(
              NotificationEvent.new(id, NotificationEventTypes::Dismissed)
            )
          end
          return 0_i64
        end
      end
      Windows::LibUser32.DefWindowProcW(window, message, w_param, l_param)
    end

    private def build_data(
      window : Void*,
      flags : UInt32,
      tip : String,
      title : String,
      text : String,
      info_flags : UInt32,
      timeout : Time::Span?,
    ) : Nil
      @@data.fill(0_u8)
      IO::ByteFormat::LittleEndian.encode(STRUCT_SIZE.to_u32, @@data[0, 4])
      IO::ByteFormat::LittleEndian.encode(window.address, @@data[8, 8])
      IO::ByteFormat::LittleEndian.encode(2_u32, @@data[16, 4])
      IO::ByteFormat::LittleEndian.encode(flags, @@data[20, 4])
      IO::ByteFormat::LittleEndian.encode(CALLBACK_MESSAGE, @@data[24, 4]) if (flags & NIF_MESSAGE) != 0
      write_field(@@data, 40, 128, tip)
      write_field(@@data, 304, 256, text)
      if timeout
        milliseconds = timeout.total_milliseconds.clamp(10_000, 30_000).to_u32
        IO::ByteFormat::LittleEndian.encode(milliseconds, @@data[816, 4])
      end
      write_field(@@data, 820, 64, title)
      IO::ByteFormat::LittleEndian.encode(info_flags, @@data[948, 4])
    end

    private def write_field(buffer : Bytes, offset : Int32, maximum : Int32, value : String) : Nil
      encoded = value.to_utf16
      count = Math.min(encoded.size, maximum - 1)
      count.times do |index|
        IO::ByteFormat::LittleEndian.encode(encoded[index], buffer[offset + index * 2, 2])
      end
    end

    private def wide(value : String) : Slice(UInt16)
      units = value.to_utf16
      Slice(UInt16).new(units.size + 1, 0_u16).tap do |buffer|
        units.each_with_index { |unit, index| buffer[index] = unit }
      end
    end
  end

  class NativeDesktop::Platform::NotificationEventSource < NativeDesktop::NotificationEventSource
    @@emit : Proc(NativeDesktop::NotificationEvent, Nil)?

    def start(&emit : NativeDesktop::NotificationEvent ->) : Nil
      @@emit = emit
    end

    def self.emit(event : NativeDesktop::NotificationEvent) : Nil
      @@emit.try(&.call(event))
    end

    def stop : Nil
      @@emit = nil
    end
  end

  NativeDesktop::Notifications.install_event_source(NativeDesktop::Platform::NotificationEventSource.new)
{% end %}
