module NativeDesktop::Platform::Windows
  class SessionEventSource < NativeDesktop::SessionEventSource
    WM_POWERBROADCAST       = 0x0218_u32
    WM_WTSSESSION_CHANGE    = 0x02B1_u32
    WM_QUERYENDSESSION      = 0x0011_u32
    WM_ENDSESSION           = 0x0016_u32
    PBT_APMSUSPEND          =      4_u64
    PBT_APMRESUMESUSPEND    =      7_u64
    PBT_APMRESUMEAUTOMATIC  =     18_u64
    WTS_SESSION_LOCK        =      7_u64
    WTS_SESSION_UNLOCK      =      8_u64
    NOTIFY_FOR_THIS_SESSION =      0_u32
    @windows = Set(Void*).new

    def process_event(event : Void*, &emit : NativeDesktop::SessionEvent ->) : Bool
      return false if event.null?
      message = event.as(LibSessionLifecycle::WindowsMessage*).value
      register_window(message.window) unless message.window.null?
      type = case message.message
             when WM_POWERBROADCAST
               case message.w_param
               when PBT_APMSUSPEND                               then SessionEventTypes::Suspend
               when PBT_APMRESUMESUSPEND, PBT_APMRESUMEAUTOMATIC then SessionEventTypes::Resume
               end
             when WM_WTSSESSION_CHANGE
               case message.w_param
               when WTS_SESSION_LOCK   then SessionEventTypes::Lock
               when WTS_SESSION_UNLOCK then SessionEventTypes::Unlock
               end
             when WM_QUERYENDSESSION, WM_ENDSESSION
               SessionEventTypes::Shutdown
             end
      return false unless type
      emit.call(NativeDesktop::SessionEvent.new(type))
      message.message != WM_QUERYENDSESSION && message.message != WM_ENDSESSION
    end

    def close : Nil
      @windows.each { |window| LibSessionLifecycle.WTSUnRegisterSessionNotification(window) }
      @windows.clear
    end

    private def register_window(window : Void*) : Nil
      return if @windows.includes?(window)
      if LibSessionLifecycle.WTSRegisterSessionNotification(window, NOTIFY_FOR_THIS_SESSION) != 0
        @windows << window
      end
    end

    @[Link("wtsapi32")]
    lib LibSessionLifecycle
      fun WTSRegisterSessionNotification(window : Void*, flags : UInt32) : Int32
      fun WTSUnRegisterSessionNotification(window : Void*) : Int32

      struct WindowsPoint
        x : Int32
        y : Int32
      end

      struct WindowsMessage
        window : Void*
        message : UInt32
        w_param : UInt64
        l_param : Int64
        time : UInt32
        point : WindowsPoint
      end
    end
  end
end

NativeDesktop::SessionLifecycle.install(NativeDesktop::Platform::Windows::SessionEventSource.new)
