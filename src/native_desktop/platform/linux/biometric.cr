@[Link("gio-2.0")]
lib LibNativeDesktopBiometricGIO
  fun proxy_new = g_dbus_proxy_new_for_bus_sync(bus_type : Int32, flags : UInt32, info : Void*, name : UInt8*, path : UInt8*, interface : UInt8*, cancellable : Void*, error : Void**) : Void*
  fun call = g_dbus_proxy_call_sync(proxy : Void*, method : UInt8*, parameters : Void*, flags : UInt32, timeout : Int32, cancellable : Void*, error : Void**) : Void*
  fun connection = g_dbus_proxy_get_connection(proxy : Void*) : Void*
  fun subscribe = g_dbus_connection_signal_subscribe(connection : Void*, sender : UInt8*, interface : UInt8*, member : UInt8*, path : UInt8*, arg0 : UInt8*, flags : UInt32, callback : Void*, data : Void*, destroy : Void*) : UInt32
  fun unsubscribe = g_dbus_connection_signal_unsubscribe(connection : Void*, id : UInt32) : Nil
  fun string = g_variant_new_string(value : UInt8*) : Void*
  fun tuple = g_variant_new_tuple(children : Void**, count : LibC::SizeT) : Void*
  fun child = g_variant_get_child_value(value : Void*, index : LibC::SizeT) : Void*
  fun children = g_variant_n_children(value : Void*) : LibC::SizeT
  fun string_value = g_variant_get_string(value : Void*, length : LibC::SizeT*) : UInt8*
  fun boolean = g_variant_get_boolean(value : Void*) : Int32
  fun unref = g_variant_unref(value : Void*) : Nil
end

@[Link("gobject-2.0")]
lib LibNativeDesktopBiometricGObject
  fun unref = g_object_unref(object : Void*) : Nil
end

@[Link("glib-2.0")]
lib LibNativeDesktopBiometricGLib
  struct Error
    domain : UInt32
    code : Int32
    message : UInt8*
  end

  fun error_free = g_error_free(error : Void*) : Nil
  fun iterate = g_main_context_iteration(context : Void*, block : Int32) : Int32
  fun username = g_get_user_name : UInt8*
end

module NativeDesktop::Platform::Biometrics
  extend self

  SERVICE       = "net.reactivated.Fprint"
  MANAGER_PATH  = "/net/reactivated/Fprint/Manager"
  MANAGER_IFACE = "net.reactivated.Fprint.Manager"
  DEVICE_IFACE  = "net.reactivated.Fprint.Device"

  class Verification
    property? done = false
    property? success = false
  end

  def info : BiometricInfo
    available = enrolled_device_path != nil
    BiometricInfo.new(available, available ? BiometricModality::Fingerprint : nil, false)
  end

  def authenticate(reason : String, window : ::NativeDesktop::Window?) : BiometricResult
    path = enrolled_device_path
    return BiometricResult.new(false, "No enrolled fingerprint is available") unless path

    proxy = device_proxy(path)
    return BiometricResult.new(false, "Cannot access the fingerprint device") if proxy.null?
    begin
      verify(proxy, path)
    ensure
      LibNativeDesktopBiometricGObject.unref(proxy)
    end
  end

  private def enrolled_device_path : String?
    path = default_device_path
    return nil unless path
    proxy = device_proxy(path)
    return nil if proxy.null?
    begin
      result, error = call(proxy, "ListEnrolledFingers", string_tuple(current_username))
      free_error(error)
      return nil if result.null?
      begin
        list = LibNativeDesktopBiometricGIO.child(result, 0_u64)
        return nil if list.null?
        begin
          LibNativeDesktopBiometricGIO.children(list) > 0 ? path : nil
        ensure
          LibNativeDesktopBiometricGIO.unref(list)
        end
      ensure
        LibNativeDesktopBiometricGIO.unref(result)
      end
    ensure
      LibNativeDesktopBiometricGObject.unref(proxy)
    end
  end

  private def default_device_path : String?
    error = Pointer(LibNativeDesktopBiometricGLib::Error).null
    proxy = LibNativeDesktopBiometricGIO.proxy_new(1, 0_u32, nil, SERVICE, MANAGER_PATH, MANAGER_IFACE, nil, pointerof(error).as(Void**))
    if proxy.null?
      free_error(error)
      return nil
    end
    begin
      result, call_error = call(proxy, "GetDefaultDevice")
      free_error(call_error)
      return nil if result.null?
      begin
        variant_string(result)
      ensure
        LibNativeDesktopBiometricGIO.unref(result)
      end
    ensure
      LibNativeDesktopBiometricGObject.unref(proxy)
    end
  end

  private def verify(proxy : Void*, path : String) : BiometricResult
    connection = LibNativeDesktopBiometricGIO.connection(proxy)
    verification = Verification.new
    data = Box.box(verification)
    subscription = LibNativeDesktopBiometricGIO.subscribe(
      connection, nil, DEVICE_IFACE, "VerifyStatus", path, nil, 0_u32,
      ->(_connection : Void*, _sender : UInt8*, _path : UInt8*, _interface : UInt8*, _signal : UInt8*, parameters : Void*, user_data : Void*) {
        handle_status(parameters, user_data)
      }.pointer,
      data, nil,
    )
    claimed = false
    started = false
    begin
      result = invoke(proxy, "Claim", string_tuple(current_username))
      return result unless result.success?
      claimed = true
      sleep 300.milliseconds

      result = invoke(proxy, "VerifyStart", string_tuple("any"), 60_000)
      return result unless result.success?
      started = true

      deadline = Time.instant + 30.seconds
      until verification.done? || Time.instant >= deadline
        LibNativeDesktopBiometricGLib.iterate(nil, 0)
        sleep 10.milliseconds
      end

      return BiometricResult.new(false, "Fingerprint verification timed out") unless verification.done?
      verification.success? ? BiometricResult.new(true) : BiometricResult.new(false, "Fingerprint did not match")
    ensure
      LibNativeDesktopBiometricGIO.unsubscribe(connection, subscription)
      invoke(proxy, "VerifyStop") if started && !verification.done?
      invoke(proxy, "Release") if claimed
    end
  end

  private def handle_status(parameters : Void*, data : Void*) : Nil
    return if parameters.null? || data.null?
    status = LibNativeDesktopBiometricGIO.child(parameters, 0_u64)
    return if status.null?
    verification = Box(Verification).unbox(data)
    begin
      value = LibNativeDesktopBiometricGIO.string_value(status, nil)
      verification.success = !value.null? && String.new(value) == "verify-match"
    ensure
      LibNativeDesktopBiometricGIO.unref(status)
    end

    done = LibNativeDesktopBiometricGIO.child(parameters, 1_u64)
    if done.null?
      verification.done = true
    else
      begin
        verification.done = LibNativeDesktopBiometricGIO.boolean(done) != 0
      ensure
        LibNativeDesktopBiometricGIO.unref(done)
      end
    end
  end

  private def device_proxy(path : String) : Void*
    error = Pointer(LibNativeDesktopBiometricGLib::Error).null
    proxy = LibNativeDesktopBiometricGIO.proxy_new(1, 0_u32, nil, SERVICE, path, DEVICE_IFACE, nil, pointerof(error).as(Void**))
    free_error(error)
    proxy
  end

  private def invoke(proxy : Void*, method : String, parameters : Void* = Pointer(Void).null, timeout = -1) : BiometricResult
    result, error = call(proxy, method, parameters, timeout)
    if result.null?
      message = error.null? ? "#{method} failed" : String.new(error.value.message)
      free_error(error)
      return BiometricResult.new(false, message)
    end
    LibNativeDesktopBiometricGIO.unref(result)
    free_error(error)
    BiometricResult.new(true)
  end

  private def call(proxy : Void*, method : String, parameters : Void* = Pointer(Void).null, timeout = -1) : {Void*, Pointer(LibNativeDesktopBiometricGLib::Error)}
    error = Pointer(LibNativeDesktopBiometricGLib::Error).null
    result = LibNativeDesktopBiometricGIO.call(proxy, method, parameters, 0_u32, timeout, nil, pointerof(error).as(Void**))
    {result, error}
  end

  private def string_tuple(value : String) : Void*
    string = LibNativeDesktopBiometricGIO.string(value)
    LibNativeDesktopBiometricGIO.tuple(pointerof(string), 1_u64)
  end

  private def variant_string(value : Void*) : String?
    child = LibNativeDesktopBiometricGIO.child(value, 0_u64)
    return nil if child.null?
    begin
      pointer = LibNativeDesktopBiometricGIO.string_value(child, nil)
      pointer.null? ? nil : String.new(pointer)
    ensure
      LibNativeDesktopBiometricGIO.unref(child)
    end
  end

  private def current_username : String
    pointer = LibNativeDesktopBiometricGLib.username
    pointer.null? ? "" : String.new(pointer)
  end

  private def free_error(error : Pointer(LibNativeDesktopBiometricGLib::Error)) : Nil
    LibNativeDesktopBiometricGLib.error_free(error.as(Void*)) unless error.null?
  end
end
