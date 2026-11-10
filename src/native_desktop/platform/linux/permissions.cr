module NativeDesktop::Platform::Permissions
  extend self

  def open_settings(id : PermissionId) : Bool
    false
  end

  def settings_available?(id : PermissionId) : Bool
    false
  end
end

module NativeDesktop::Platform::Linux
  class AccessibilityPermissionProvider < NativeDesktop::PlatformPermissionProvider
    def initialize
      super(NativeDesktop::PermissionIds::Accessibility)
    end

    def status : NativeDesktop::PermissionInfo
      PermissionInfo.new(id, PermissionState::Unsupported)
    end
  end
end

NativeDesktop::Permissions.register(NativeDesktop::Platform::Linux::AccessibilityPermissionProvider.new)
