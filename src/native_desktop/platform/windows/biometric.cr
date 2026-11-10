require "./win32_common"

module NativeDesktop::Platform::Biometrics
  extend self

  @[Link("winbio")]
  lib LibNativeDesktopWinBio
    FACTOR_FINGERPRINT = 0x00000008_u32
    IDENTITY_SID       =          3_u32

    struct Identity
      type : UInt32
      sid_size : UInt32
      sid_data : UInt8[68]
    end

    fun units = WinBioEnumBiometricUnits(factor : UInt32, schemas : Void**, count : LibC::SizeT*) : Int32
    fun enrolled = WinBioGetEnrolledFactors(owner : Identity*, factors : UInt32*) : Int32
    fun free = WinBioFree(address : Void*) : Nil
  end

  TOKEN_READ = 0x00020008_u32
  TOKEN_USER =          1_u32

  struct SIDAndAttributes
    sid : Void*
    attributes : UInt32
  end

  struct TokenUser
    user : SIDAndAttributes
  end

  @[Link("runtimeobject")]
  lib LibNativeDesktopBiometricWinRT
    fun initialize = RoInitialize(type : UInt32) : Int32
    fun uninitialize = RoUninitialize : Nil
    fun factory = RoGetActivationFactory(class_name : Void*, iid : UInt8*, result : Void**) : Int32
    fun string = WindowsCreateString(source : UInt16*, length : UInt32, result : Void**) : Int32
    fun delete_string = WindowsDeleteString(value : Void*) : Int32
  end

  def pump_messages : Nil
    message = uninitialized UInt64[6]
    while Windows::LibUser32.PeekMessageW(message.to_unsafe.as(Void*), nil, 0, 0, 1_u32) != 0
      Windows::LibUser32.TranslateMessage(message.to_unsafe.as(Void*))
      Windows::LibUser32.DispatchMessageW(message.to_unsafe.as(Void*))
    end
    Windows::LibUser32.MsgWaitForMultipleObjects(0_u32, nil, 0, 50_u32, 0x04FF_u32)
  end

  CLASS_NAME   = "Windows.Security.Credentials.UI.UserConsentVerifier"
  COINIT_STA   = 0_u32
  S_OK         = 0_i32
  S_FALSE      = 1_i32
  CHANGED_MODE = 0x80010106_u32.unsafe_as(Int32)

  IID_INTEROP      = Bytes[0xC3, 0x50, 0xE0, 0x39, 0x74, 0x4E, 0x1A, 0x44, 0x8D, 0xC0, 0xB8, 0x11, 0x04, 0xDF, 0x94, 0x9C]
  IID_ASYNC_RESULT = Bytes[0xFD, 0x6F, 0x59, 0xFD, 0x18, 0x23, 0x8F, 0x55, 0x9D, 0xBE, 0xD2, 0x1D, 0xF4, 0x37, 0x64, 0xA5]
  IID_ASYNC_INFO   = Bytes[0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46]

  def info : BiometricInfo
    available = fingerprint_hardware? && fingerprint_enrolled?
    BiometricInfo.new(available, available ? BiometricModality::Fingerprint : nil, true)
  end

  def authenticate(reason : String, window : ::NativeDesktop::Window?) : BiometricResult
    return BiometricResult.new(false, "No enrolled Windows fingerprint is available") unless info.available?
    owner = window.try(&.handle) || Windows::LibUser32.GetForegroundWindow
    status, error = request_consent(owner, reason)
    status == 0 ? BiometricResult.new(true) : BiometricResult.new(false, error || status_error(status))
  end

  private def current_identity : LibNativeDesktopWinBio::Identity?
    token = Pointer(Void).null
    return nil if Windows::LibAdvApi32.OpenProcessToken(Windows::LibKernel32.GetCurrentProcess, TOKEN_READ, pointerof(token)) == 0
    begin
      returned = 0_u32
      Windows::LibAdvApi32.GetTokenInformation(token, TOKEN_USER, nil, 0_u32, pointerof(returned))
      return nil if returned == 0
      buffer = Bytes.new(returned)
      return nil if Windows::LibAdvApi32.GetTokenInformation(token, TOKEN_USER, buffer.to_unsafe.as(Void*), returned, pointerof(returned)) == 0

      sid = buffer.to_unsafe.as(Pointer(Pointer(Void))).value
      size = Windows::LibAdvApi32.GetLengthSid(sid)
      return nil if size == 0 || size > 68
      identity = LibNativeDesktopWinBio::Identity.new
      identity.type = LibNativeDesktopWinBio::IDENTITY_SID
      identity.sid_size = size
      return nil if Windows::LibAdvApi32.CopySid(size, identity.sid_data.to_unsafe.as(Void*), sid) == 0
      identity
    ensure
      Windows::LibKernel32.CloseHandle(token)
    end
  end

  private def fingerprint_hardware? : Bool
    schemas = Pointer(Void).null
    count = LibC::SizeT.new(0)
    result = LibNativeDesktopWinBio.units(LibNativeDesktopWinBio::FACTOR_FINGERPRINT, pointerof(schemas), pointerof(count))
    LibNativeDesktopWinBio.free(schemas) unless schemas.null?
    result == 0 && count > 0
  end

  private def fingerprint_enrolled? : Bool
    id_val = current_identity
    return false unless id_val
    identity = id_val.as(LibNativeDesktopWinBio::Identity)
    factors = 0_u32
    result = LibNativeDesktopWinBio.enrolled(pointerof(identity), pointerof(factors))
    result == 0 && (factors & LibNativeDesktopWinBio::FACTOR_FINGERPRINT) != 0
  end

  private def request_consent(owner : Void*, reason : String) : {Int32, String?}
    initialized = false
    result = LibNativeDesktopBiometricWinRT.initialize(COINIT_STA)
    if result == S_OK || result == S_FALSE
      initialized = true
    elsif result != CHANGED_MODE
      return {-1, "Windows Runtime initialization failed (#{hresult(result)})"}
    end

    class_name = Pointer(Void).null
    reason_string = Pointer(Void).null
    factory = Pointer(Void).null
    operation = Pointer(Void).null
    async_info = Pointer(Void).null
    begin
      result = hstring(CLASS_NAME, pointerof(class_name))
      return {-1, "Could not create the Windows Runtime class string (#{hresult(result)})"} if result < 0
      result = LibNativeDesktopBiometricWinRT.factory(class_name, IID_INTEROP.to_unsafe, pointerof(factory))
      return {-1, "Could not access Windows Hello (#{hresult(result)})"} if result < 0 || factory.null?
      result = hstring(reason, pointerof(reason_string))
      return {-1, "Could not create the Windows Hello prompt text (#{hresult(result)})"} if result < 0
      result = request_for_window(factory, owner, reason_string, pointerof(operation))
      return {-1, "Could not start Windows Hello verification (#{hresult(result)})"} if result < 0 || operation.null?
      result = query_interface(operation, IID_ASYNC_INFO, pointerof(async_info))
      return {-1, "Could not observe Windows Hello verification (#{hresult(result)})"} if result < 0 || async_info.null?

      status = wait_for_completion(async_info)
      return {6, nil} if status == 2
      return {-1, "Windows Hello verification failed asynchronously"} unless status == 1
      verification = 0_i32
      result = get_results(operation, pointerof(verification))
      return {-1, "Could not read the Windows Hello result (#{hresult(result)})"} if result < 0
      {verification, nil}
    ensure
      release(async_info) unless async_info.null?
      release(operation) unless operation.null?
      release(factory) unless factory.null?
      LibNativeDesktopBiometricWinRT.delete_string(reason_string) unless reason_string.null?
      LibNativeDesktopBiometricWinRT.delete_string(class_name) unless class_name.null?
      LibNativeDesktopBiometricWinRT.uninitialize if initialized
    end
  end

  private def hstring(value : String, result : Void**) : Int32
    utf16 = value.encode("UTF-16LE")
    LibNativeDesktopBiometricWinRT.string(utf16.to_unsafe.as(UInt16*), (utf16.bytesize // 2).to_u32, result)
  end

  private def query_interface(object : Void*, iid : Bytes, result : Void**) : Int32
    Proc(Void*, UInt8*, Void**, Int32).new(function(object, 0), Pointer(Void).null).call(object, iid.to_unsafe, result)
  end

  private def release(object : Void*) : UInt32
    Proc(Void*, UInt32).new(function(object, 2), Pointer(Void).null).call(object)
  end

  private def request_for_window(factory : Void*, owner : Void*, reason : Void*, result : Void**) : Int32
    Proc(Void*, Void*, Void*, UInt8*, Void**, Int32).new(function(factory, 6), Pointer(Void).null).call(factory, owner, reason, IID_ASYNC_RESULT.to_unsafe, result)
  end

  private def wait_for_completion(info : Void*) : Int32
    status = 0_i32
    while status == 0
      return -1 if Proc(Void*, Int32*, Int32).new(function(info, 7), Pointer(Void).null).call(info, pointerof(status)) < 0
      pump_messages
    end
    status
  end

  private def get_results(operation : Void*, result : Int32*) : Int32
    Proc(Void*, Int32*, Int32).new(function(operation, 8), Pointer(Void).null).call(operation, result)
  end

  private def function(object : Void*, index : Int32) : Void*
    object.as(Pointer(Void*)).value.as(Pointer(Void*))[index]
  end

  private def status_error(status : Int32) : String
    case status
    when 1 then "Windows Hello device is not present"
    when 2 then "Windows Hello is not configured for the current user"
    when 3 then "Windows Hello is disabled by policy"
    when 4 then "Windows Hello device is busy"
    when 5 then "Windows Hello retry limit was exhausted"
    when 6 then "Windows Hello verification was canceled"
    else        "Windows Hello verification failed (#{status})"
    end
  end

  private def hresult(value : Int32) : String
    "0x#{value.unsafe_as(UInt32).to_s(16).rjust(8, '0')}"
  end
end
