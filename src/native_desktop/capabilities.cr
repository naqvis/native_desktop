module NativeDesktop
  # Open identifier for a desktop capability. Applications and extension
  # shards may define identifiers without changing native_desktop.
  native_desktop_open_id(FeatureId, "feature identifier")

  # Identifiers implemented by the bundled services. This module is a
  # convenience catalog, not a closed set.
  module Features
    WindowControls      = FeatureId["window.controls"]
    WindowEffects       = FeatureId["window.effects"]
    Displays            = FeatureId["displays"]
    Clipboard           = FeatureId["clipboard"]
    Dialogs             = FeatureId["dialogs"]
    Notifications       = FeatureId["notifications"]
    NotificationActions = FeatureId["notifications.actions"]
    DropTarget          = FeatureId["drag.drop-target"]
    GlobalShortcuts     = FeatureId["shortcuts.global"]
    TaskbarProgress     = FeatureId["taskbar.progress"]
    TaskbarBadge        = FeatureId["taskbar.badge"]
    TaskbarOverlay      = FeatureId["taskbar.overlay"]
    SpeechSynthesis     = FeatureId["speech.synthesis"]
    SpeechRecognition   = FeatureId["speech.recognition"]
    Biometrics          = FeatureId["biometrics"]
    HardwareEnumeration = FeatureId["hardware.enumeration"]
    HardwareMonitoring  = FeatureId["hardware.monitoring"]
    SessionLifecycle    = FeatureId["session.lifecycle"]
    URLActivations      = FeatureId["activations.url"]
    FileActivations     = FeatureId["activations.files"]
  end

  enum CapabilityState
    Supported
    Unsupported
    Unavailable
    PermissionRequired
    HostIntegrationRequired
  end

  record Capability,
    feature : FeatureId,
    state : CapabilityState,
    reason : String? = nil do
    def supported? : Bool
      state.supported?
    end
  end

  # Extensible capability registry. Each service or platform backend owns its
  # registration; the core registry contains no platform policy.
  module Capabilities
    extend self

    alias Resolver = Proc(FeatureId, Capability)
    @@lock = Mutex.new
    @@resolvers = {} of FeatureId => Array(Resolver)

    def register(feature : FeatureId, state : CapabilityState, reason : String? = nil) : Nil
      register(feature) { |id| Capability.new(id, state, reason) }
    end

    def register(feature : FeatureId, &resolver : FeatureId -> Capability) : Nil
      @@lock.synchronize { (@@resolvers[feature] ||= [] of Resolver) << resolver }
    end

    # Removes the most recently registered resolver, revealing an earlier
    # provider when one exists.
    def unregister(feature : FeatureId) : Nil
      @@lock.synchronize do
        if resolvers = @@resolvers[feature]?
          resolvers.pop?
          @@resolvers.delete(feature) if resolvers.empty?
        end
      end
    end

    def status(feature : FeatureId | String | Symbol) : Capability
      id = feature.is_a?(FeatureId) ? feature : FeatureId[feature]
      resolver = @@lock.synchronize { @@resolvers[id]?.try(&.last?) }
      return resolver.call(id) if resolver
      Capability.new(id, CapabilityState::Unavailable, "no capability provider is registered")
    end

    def supported?(feature : FeatureId | String | Symbol) : Bool
      status(feature).supported?
    end

    def all : Array(Capability)
      entries = @@lock.synchronize do
        @@resolvers.compact_map { |feature, resolvers| {feature, resolvers.last} unless resolvers.empty? }
      end
      entries.map { |feature, resolver| resolver.call(feature) }
    end
  end
end
