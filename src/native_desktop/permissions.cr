module NativeDesktop
  # Open identifier for an operating-system permission.
  native_desktop_open_id(PermissionId, "permission identifier")

  module PermissionIds
    Notifications     = PermissionId["notifications"]
    Accessibility     = PermissionId["accessibility"]
    Microphone        = PermissionId["microphone"]
    SpeechRecognition = PermissionId["speech-recognition"]
    Biometrics        = PermissionId["biometrics"]
  end

  enum PermissionState
    Granted
    Denied
    NotDetermined
    Restricted
    Unsupported
    Unavailable
    Unknown
  end

  record PermissionInfo,
    permission : PermissionId,
    state : PermissionState,
    can_request : Bool = false,
    settings_available : Bool = false

  abstract class PermissionProvider
    getter id : PermissionId

    def initialize(@id : PermissionId)
    end

    abstract def status : PermissionInfo

    def request : PermissionInfo
      status
    end

    def open_settings : Bool
      false
    end
  end

  abstract class PlatformPermissionProvider < PermissionProvider
    def settings_available? : Bool
      Platform::Permissions.settings_available?(id)
    end

    def open_settings : Bool
      Platform::Permissions.open_settings(id)
    end
  end

  # Permission providers are registered by the service or platform that owns
  # them. Extension shards can add providers without modifying this module.
  module Permissions
    extend self
    @@lock = Mutex.new
    @@providers = {} of PermissionId => Array(PermissionProvider)

    def register(provider : PermissionProvider) : Nil
      @@lock.synchronize { (@@providers[provider.id] ||= [] of PermissionProvider) << provider }
    end

    # Removes the most recently registered provider, revealing an earlier
    # provider when one exists.
    def unregister(id : PermissionId | String | Symbol) : Nil
      key = id.is_a?(PermissionId) ? id : PermissionId[id]
      @@lock.synchronize do
        if providers = @@providers[key]?
          providers.pop?
          @@providers.delete(key) if providers.empty?
        end
      end
    end

    # Returns a benign `Unavailable` state when no provider is registered,
    # matching the graceful behavior of `Capabilities.status` for unknown
    # features.
    def status(id : PermissionId | String | Symbol) : PermissionInfo
      provider = provider_for(id)
      provider ? provider.status : PermissionInfo.new(key_for(id), PermissionState::Unavailable, false, false)
    end

    def request(id : PermissionId | String | Symbol) : PermissionInfo
      provider = provider_for(id)
      provider ? provider.request : PermissionInfo.new(key_for(id), PermissionState::Unavailable, false, false)
    end

    def open_settings(id : PermissionId | String | Symbol) : Bool
      provider = provider_for(id)
      provider ? provider.open_settings : false
    end

    private def key_for(id : PermissionId | String | Symbol) : PermissionId
      id.is_a?(PermissionId) ? id : PermissionId[id]
    end

    private def provider_for(id : PermissionId | String | Symbol) : PermissionProvider?
      key = key_for(id)
      @@lock.synchronize { @@providers[key]?.try(&.last?) }
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/permissions"
{% elsif flag?(:linux) %}
  require "./platform/linux/permissions"
{% elsif flag?(:windows) %}
  require "./platform/windows/permissions"
{% end %}
