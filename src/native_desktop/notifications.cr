module NativeDesktop
  # Importance assigned to a desktop notification.
  enum NotificationUrgency
    Low
    Normal
    Critical
  end

  # An action button displayed by a notification service that supports it.
  struct NotificationAction
    getter id : String
    getter label : String

    def initialize(@id : String, @label : String)
      raise ArgumentError.new("notification action id cannot be empty") if @id.empty?
      raise ArgumentError.new("notification action label cannot be empty") if @label.empty?
    end
  end

  # Icon data supplied to the native notification service.
  struct NotificationIcon
    getter bytes : Bytes?
    getter name : String?
    getter key : String?

    def self.bytes(value : Bytes, key : String? = nil) : self
      raise ArgumentError.new("icon bytes cannot be empty") if value.empty?
      new(value, nil, key)
    end

    def self.name(value : String) : self
      raise ArgumentError.new("icon name cannot be empty") if value.empty?
      new(nil, value, nil)
    end

    private def initialize(@bytes : Bytes?, @name : String?, @key : String?)
    end
  end

  # Values used to display a notification.
  struct NotificationRequest
    getter id : String
    getter title : String
    getter body : String
    getter icon : NotificationIcon?
    getter urgency : NotificationUrgency
    getter timeout : Time::Span?
    getter actions : Array(NotificationAction)

    def initialize(
      @id : String,
      @title : String,
      @body : String = "",
      @icon : NotificationIcon? = nil,
      @urgency : NotificationUrgency = NotificationUrgency::Normal,
      @timeout : Time::Span? = nil,
      @actions : Array(NotificationAction) = [] of NotificationAction,
    )
      raise ArgumentError.new("notification id cannot be empty") if @id.empty?
      raise ArgumentError.new("notification title cannot be empty") if @title.empty?
    end
  end

  native_desktop_open_id(NotificationEventType, "notification event type")

  module NotificationEventTypes
    Activated      = NotificationEventType["activated"]
    ActionSelected = NotificationEventType["action-selected"]
    Dismissed      = NotificationEventType["dismissed"]
    Failed         = NotificationEventType["failed"]
  end

  record NotificationEvent,
    id : String,
    type : NotificationEventType,
    action_id : String? = nil,
    error : Error? = nil

  abstract class NotificationEventSource
    abstract def start(&emit : NotificationEvent ->) : Nil

    def stop : Nil
    end
  end

  module Notifications
    extend self
    @@lock = Mutex.new
    @@handlers = [] of Proc(NotificationEvent, Nil)
    private record EventSource, id : UInt64, value : NotificationEventSource
    @@event_sources = [] of EventSource
    @@next_event_source_id = 0_u64

    def install_event_source(source : NotificationEventSource) : Registration
      source.start { |event| emit(event) }
      id = @@lock.synchronize do
        @@next_event_source_id += 1
        @@event_sources << EventSource.new(@@next_event_source_id, source)
        @@next_event_source_id
      end
      Registration.new { remove_event_source(id) }
    end

    def event_source_installed? : Bool
      @@lock.synchronize { !@@event_sources.empty? }
    end

    # Requests permission to display notifications for *application_name*.
    def request_permission(application_name : String) : Bool
      raise ArgumentError.new("application name cannot be empty") if application_name.empty?
      Runtime.dispatch_sync { Platform::Notifications.request_permission(application_name) }
    end

    # Displays or replaces a notification with the same id.
    def show(application_name : String, request : NotificationRequest) : Nil
      raise ArgumentError.new("application name cannot be empty") if application_name.empty?
      Runtime.dispatch_sync { Platform::Notifications.show(application_name, request) }
    rescue ex
      error = ex.is_a?(Error) ? ex : Error.new(ex.message || "notification failed", :notification_failed, ex)
      emit(NotificationEvent.new(request.id, NotificationEventTypes::Failed, error: error))
      raise ex
    end

    # Closes the notification identified by *id*.
    def close(id : String) : Nil
      return if id.empty?
      Runtime.dispatch_sync { Platform::Notifications.close(id) }
    end

    # Registers a process-wide notification lifecycle handler.
    def on_event(&handler : NotificationEvent ->) : Registration
      @@lock.synchronize { @@handlers << handler }
      Registration.new { remove_handler(handler) }
    end

    # Called by platform backends or hosts when the desktop activates or
    # dismisses a notification.
    def emit(event : NotificationEvent) : Nil
      handlers = @@lock.synchronize { @@handlers.dup }
      handlers.each do |handler|
        Runtime.dispatch { handler.call(event) }
      rescue ex
        Log.error(exception: ex) { "notification event handler failed" }
      end
    end

    def clear_event_handlers : Nil
      @@lock.synchronize { @@handlers.clear }
    end

    def remove_event_sources : Nil
      sources = @@lock.synchronize do
        values = @@event_sources.map(&.value)
        @@event_sources = [] of EventSource
        values
      end
      sources.each(&.stop)
    end

    protected def remove_event_source(id : UInt64) : Nil
      source = @@lock.synchronize do
        index = @@event_sources.index { |registered| registered.id == id }
        index ? @@event_sources.delete_at(index).value : nil
      end
      source.try(&.stop)
    end

    protected def remove_handler(handler : Proc(NotificationEvent, Nil)) : Nil
      @@lock.synchronize { @@handlers.delete(handler) }
    end
  end
end

module NativeDesktop
  # :nodoc:
  class NotificationPermissionProvider < PlatformPermissionProvider
    def initialize
      super(PermissionIds::Notifications)
    end

    def status : PermissionInfo
      state = Platform::Notifications.permission_state
      PermissionInfo.new(id, state, state.unknown? || state.not_determined?, settings_available?)
    end

    def request : PermissionInfo
      identity = Application.identity ||
                 raise Error.new("application identity is required to request notification permission", :application_identity_missing)
      granted = Notifications.request_permission(identity.name)
      PermissionInfo.new(id, granted ? PermissionState::Granted : PermissionState::Denied, false, settings_available?)
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::Notifications, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Capabilities.register(NativeDesktop::Features::NotificationActions) do |feature|
  if NativeDesktop::Notifications.event_source_installed?
    NativeDesktop::Capability.new(feature, NativeDesktop::CapabilityState::Supported)
  else
    NativeDesktop::Capability.new(
      feature,
      NativeDesktop::CapabilityState::HostIntegrationRequired,
      "install a notification event source for the GUI host"
    )
  end
end
NativeDesktop::Permissions.register(NativeDesktop::NotificationPermissionProvider.new)

{% if flag?(:darwin) %}
  require "./platform/macos/notifications"
{% elsif flag?(:linux) %}
  require "./platform/linux/notifications"
{% elsif flag?(:windows) %}
  require "./platform/windows/notifications"
{% else %}
  {% raise "native_desktop does not support this platform" %}
{% end %}
