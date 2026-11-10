module NativeDesktop::Platform::Permissions
  extend self

  MACOS_SETTINGS = {
    PermissionIds::Notifications     => "x-apple.systempreferences:com.apple.preference.notifications",
    PermissionIds::Accessibility     => "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
    PermissionIds::Microphone        => "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
    PermissionIds::SpeechRecognition => "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition",
    PermissionIds::Biometrics        => "x-apple.systempreferences:com.apple.preference.touchid",
  }

  def open_settings(id : PermissionId) : Bool
    return false unless target = MACOS_SETTINGS[id]?
    NativeDesktop::Applications.open(target)
    true
  rescue
    false
  end

  def settings_available?(id : PermissionId) : Bool
    MACOS_SETTINGS.has_key?(id)
  end
end

module NativeDesktop::Platform::MacOS
  @[Link(framework: "ApplicationServices")]
  lib LibAccessibilityPermission
    fun AXIsProcessTrusted : Int32
  end

  class AccessibilityPermissionProvider < NativeDesktop::PlatformPermissionProvider
    def initialize
      super(NativeDesktop::PermissionIds::Accessibility)
    end

    def status : NativeDesktop::PermissionInfo
      state = LibAccessibilityPermission.AXIsProcessTrusted != 0 ? PermissionState::Granted : PermissionState::Denied
      PermissionInfo.new(id, state, false, settings_available?)
    end
  end
end

NativeDesktop::Permissions.register(NativeDesktop::Platform::MacOS::AccessibilityPermissionProvider.new)
