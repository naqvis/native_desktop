module NativeDesktop
  # Kind of biometric credential exposed by the operating system.
  enum BiometricModality
    Fingerprint
    Face
    Unknown
  end

  # Current biometric authentication capability.
  record BiometricInfo,
    available : Bool,
    modality : BiometricModality?,
    reason_supported : Bool do
    def available? : Bool
      available
    end

    def reason_supported? : Bool
      reason_supported
    end
  end

  # Outcome of an authentication request. Cancellation and rejection are
  # ordinary results rather than exceptions.
  record BiometricResult, success : Bool, error : String? = nil do
    def success? : Bool
      success
    end
  end

  # Operating-system biometric authentication.
  module Biometrics
    extend self

    @@authentication_lock = Mutex.new

    def info : BiometricInfo
      Platform::Biometrics.info
    end

    def available? : Bool
      info.available?
    end

    def modality : BiometricModality?
      info.modality
    end

    # Displays the native authentication prompt. *window* is a non-owning
    # owner reference used by platforms whose prompt must be attached.
    def authenticate(reason : String, window : Window? = nil) : BiometricResult
      raise ArgumentError.new("authentication reason cannot be empty") if reason.empty?
      @@authentication_lock.synchronize { Platform::Biometrics.authenticate(reason, window) }
    end
  end
end

module NativeDesktop
  class BiometricPermissionProvider < PlatformPermissionProvider
    def initialize
      super(PermissionIds::Biometrics)
    end

    def status : PermissionInfo
      state = Biometrics.info.available? ? PermissionState::Granted : PermissionState::Unavailable
      PermissionInfo.new(id, state, false, settings_available?)
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::Biometrics, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Permissions.register(NativeDesktop::BiometricPermissionProvider.new)

{% if flag?(:darwin) %}
  require "./platform/macos/biometric"
{% elsif flag?(:linux) %}
  require "./platform/linux/biometric"
{% elsif flag?(:windows) %}
  require "./platform/windows/biometric"
{% end %}
