@[Link("gio-2.0")]
lib LibNativeDesktopSessionGIO
  fun bus_get = g_bus_get_sync(bus_type : Int32, cancellable : Void*, error : Void**) : Void*
  fun subscribe = g_dbus_connection_signal_subscribe(
    connection : Void*,
    sender : UInt8*,
    interface : UInt8*,
    member : UInt8*,
    path : UInt8*,
    arg0 : UInt8*,
    flags : UInt32,
    callback : Void*,
    data : Void*,
    destroy : Void*,
  ) : UInt32
  fun unsubscribe = g_dbus_connection_signal_unsubscribe(connection : Void*, id : UInt32) : Nil
  fun child = g_variant_get_child_value(value : Void*, index : LibC::SizeT) : Void*
  fun boolean = g_variant_get_boolean(value : Void*) : Int32
  fun unref = g_variant_unref(value : Void*) : Nil
end

@[Link("gobject-2.0")]
lib LibNativeDesktopSessionGObject
  fun unref = g_object_unref(object : Void*) : Nil
end

module NativeDesktop::Platform::Linux
  # Receives systemd-logind lifecycle signals from the system bus. The source
  # is installed only when the bus is available, so non-systemd hosts can
  # provide another SessionEventSource through the public registry.
  class LogindSessionEventSource < NativeDesktop::SessionEventSource
    SYSTEM_BUS = 1
    SERVICE    = "org.freedesktop.login1"
    MANAGER    = "org.freedesktop.login1.Manager"
    SESSION    = "org.freedesktop.login1.Session"
    ROOT_PATH  = "/org/freedesktop/login1"

    @connection = Pointer(Void).null
    @subscriptions = [] of UInt32
    @emit : Proc(NativeDesktop::SessionEvent, Nil)? = nil
    @callback_data = Pointer(Void).null

    def available? : Bool
      return true unless @connection.null?
      error = Pointer(Void).null
      @connection = LibNativeDesktopSessionGIO.bus_get(
        SYSTEM_BUS,
        Pointer(Void).null,
        pointerof(error)
      )
      !@connection.null?
    end

    def start(&emit : NativeDesktop::SessionEvent ->) : Nil
      return unless available?
      @emit = emit
      @callback_data = Box.box(self)
      subscribe(MANAGER, "PrepareForSleep", ROOT_PATH)
      subscribe(MANAGER, "PrepareForShutdown", ROOT_PATH)
      if path = current_session_path
        subscribe(SESSION, "Lock", path)
        subscribe(SESSION, "Unlock", path)
      end
    end

    def process_event(event : Void*, &emit : NativeDesktop::SessionEvent ->) : Bool
      false
    end

    def close : Nil
      unless @connection.null?
        @subscriptions.each do |id|
          LibNativeDesktopSessionGIO.unsubscribe(@connection, id)
        end
        LibNativeDesktopSessionGObject.unref(@connection)
      end
      @subscriptions.clear
      @connection = Pointer(Void).null
      @callback_data = Pointer(Void).null
      @emit = nil
    end

    protected def receive(member : String, parameters : Void*) : Nil
      type = case member
             when "PrepareForSleep"
               boolean_parameter(parameters) ? NativeDesktop::SessionEventTypes::Suspend : NativeDesktop::SessionEventTypes::Resume
             when "PrepareForShutdown"
               boolean_parameter(parameters) ? NativeDesktop::SessionEventTypes::Shutdown : nil
             when "Lock"
               NativeDesktop::SessionEventTypes::Lock
             when "Unlock"
               NativeDesktop::SessionEventTypes::Unlock
             end
      @emit.try(&.call(NativeDesktop::SessionEvent.new(type))) if type
    end

    private def subscribe(interface : String, member : String, path : String? = nil) : Nil
      id = LibNativeDesktopSessionGIO.subscribe(
        @connection,
        SERVICE,
        interface,
        member,
        path,
        Pointer(UInt8).null,
        0_u32,
        ->(_connection : Void*, _sender : UInt8*, _path : UInt8*, _interface : UInt8*, signal : UInt8*, parameters : Void*, data : Void*) {
          source = Box(LogindSessionEventSource).unbox(data)
          source.receive(String.new(signal), parameters)
        }.pointer,
        @callback_data,
        Pointer(Void).null
      )
      @subscriptions << id unless id == 0
    end

    private def boolean_parameter(parameters : Void*) : Bool
      value = LibNativeDesktopSessionGIO.child(parameters, 0)
      return false if value.null?
      begin
        LibNativeDesktopSessionGIO.boolean(value) != 0
      ensure
        LibNativeDesktopSessionGIO.unref(value)
      end
    end

    private def current_session_path : String?
      id = ENV["XDG_SESSION_ID"]?
      return nil unless id && id.matches?(/\A[A-Za-z0-9_]+\z/)
      "#{ROOT_PATH}/session/#{id}"
    end
  end
end

linux_session_source = NativeDesktop::Platform::Linux::LogindSessionEventSource.new
if linux_session_source.available?
  NativeDesktop::SessionLifecycle.install(linux_session_source)
end
