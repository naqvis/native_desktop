module NativeDesktop::Platform::Permissions
  extend self

  WINDOWS_SETTINGS = {
    PermissionIds::Notifications     => "ms-settings:notifications",
    PermissionIds::Accessibility     => "ms-settings:easeofaccess",
    PermissionIds::Microphone        => "ms-settings:privacy-microphone",
    PermissionIds::SpeechRecognition => "ms-settings:privacy-speech",
    PermissionIds::Biometrics        => "ms-settings:signinoptions-launchfaceenrollment",
  }

  def open_settings(id : PermissionId) : Bool
    return false unless target = WINDOWS_SETTINGS[id]?
    NativeDesktop::Applications.open(target)
    true
  rescue
    false
  end

  def settings_available?(id : PermissionId) : Bool
    WINDOWS_SETTINGS.has_key?(id)
  end
end

module NativeDesktop::Platform::Windows
  class AccessibilityPermissionProvider < NativeDesktop::PlatformPermissionProvider
    def initialize
      super(NativeDesktop::PermissionIds::Accessibility)
    end

    def status : NativeDesktop::PermissionInfo
      PermissionInfo.new(id, PermissionState::Granted, false, settings_available?)
    end
  end
end

NativeDesktop::Permissions.register(NativeDesktop::Platform::Windows::AccessibilityPermissionProvider.new)
