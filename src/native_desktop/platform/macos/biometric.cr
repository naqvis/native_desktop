module NativeDesktop::Platform::Biometrics
  extend self

  @[Link(ldflags: "#{__DIR__}/biometric.m -framework LocalAuthentication -framework Foundation")]
  lib LibNativeDesktopBiometric
    fun available = native_desktop_biometric_available(type : Int32*) : Int32
    fun authenticate = native_desktop_biometric_authenticate(reason : UInt8*, error : UInt8**) : Int32
  end

  def info : BiometricInfo
    type = 0_i32
    available = LibNativeDesktopBiometric.available(pointerof(type)) == 1
    modality = if available
                 case type
                 when 1 then BiometricModality::Fingerprint
                 when 2 then BiometricModality::Face
                 else        BiometricModality::Unknown
                 end
               end
    BiometricInfo.new(available, modality, true)
  end

  def authenticate(reason : String, window : ::NativeDesktop::Window?) : BiometricResult
    error = Pointer(UInt8).null
    success = LibNativeDesktopBiometric.authenticate(reason, pointerof(error)) == 1
    return BiometricResult.new(true) if success

    message = if error.null?
                "Biometric authentication failed"
              else
                begin
                  String.new(error)
                ensure
                  LibC.free(error.as(Void*))
                end
              end
    BiometricResult.new(false, message)
  end
end
