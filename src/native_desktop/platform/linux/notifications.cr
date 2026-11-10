{% if flag?(:linux) %}
  module NativeDesktop::Platform::Notifications
    extend self

    @[Link("notify", pkg_config: "libnotify")]
    lib LibNotify
      type Notification = Void*

      fun notify_init(app_name : UInt8*) : Int32
      fun notify_notification_new(summary : UInt8*, body : UInt8*, icon : UInt8*) : Notification
      fun notify_notification_set_urgency(notification : Notification, urgency : Int32) : Nil
      fun notify_notification_set_timeout(notification : Notification, timeout : Int32) : Nil
      fun notify_notification_add_action(notification : Notification, action : UInt8*, label : UInt8*, callback : Void*, user_data : Void*, free_func : Void*) : Nil
      fun notify_notification_show(notification : Notification, error : Void**) : Int32
      fun notify_notification_close(notification : Notification, error : Void**) : Int32
    end

    @[Link("gobject-2.0")]
    lib LibGObjectNotify
      fun g_signal_connect_data(instance : Void*, signal : UInt8*, callback : Void*, data : Void*, destroy_data : Void*, flags : Int32) : UInt64
    end

    @@initialized = false
    @@active = {} of String => LibNotify::Notification
    @@temporary_icons = [] of String
    @@ids = {} of LibNotify::Notification => String

    def request_permission(application_name : String) : Bool
      return true if @@initialized
      @@initialized = LibNotify.notify_init(application_name) != 0
    end

    def permission_state : PermissionState
      @@initialized ? PermissionState::Granted : PermissionState::Unknown
    end

    def show(application_name : String, request : NotificationRequest) : Nil
      request_permission(application_name) unless @@initialized

      notification = LibNotify.notify_notification_new(
        request.title,
        request.body,
        icon_argument(request.icon) || "dialog-information"
      )
      @@active[request.id] = notification
      @@ids[notification] = request.id

      LibNotify.notify_notification_set_urgency(notification, request.urgency.value)
      timeout = request.timeout.try(&.total_milliseconds.to_i) || -1
      LibNotify.notify_notification_set_timeout(notification, timeout)

      request.actions.each do |action|
        LibNotify.notify_notification_add_action(
          notification,
          action.id,
          action.label,
          (->(native : LibNotify::Notification, selected : UInt8*, _data : Void*) {
            if id = @@ids[native]?
              action_id = selected.null? ? nil : String.new(selected)
              NativeDesktop::Platform::NotificationEventSource.emit(
                NotificationEvent.new(id, NotificationEventTypes::ActionSelected, action_id)
              )
            end
          }).pointer.as(Void*),
          Pointer(Void).null,
          Pointer(Void).null
        )
      end

      LibGObjectNotify.g_signal_connect_data(
        notification.as(Void*),
        "closed",
        (->(native : LibNotify::Notification, _data : Void*) {
          if id = @@ids.delete(native)
            NativeDesktop::Platform::NotificationEventSource.emit(
              NotificationEvent.new(id, NotificationEventTypes::Dismissed)
            )
          end
          0
        }).pointer,
        Pointer(Void).null,
        Pointer(Void).null,
        0_i32
      )

      error = Pointer(Void).null
      result = LibNotify.notify_notification_show(notification, pointerof(error))
      raise Error.new("libnotify failed to display notification", :notification_failed) if result == 0
    end

    def close(id : String) : Nil
      notification = @@active.delete(id)
      return unless notification

      error = Pointer(Void).null
      LibNotify.notify_notification_close(notification, pointerof(error))
      @@ids.delete(notification)
    end

    private def icon_argument(icon : NotificationIcon?) : String?
      return nil unless icon
      if bytes = icon.bytes
        key = icon.key || "notification"
        filename = "native-desktop-notification-#{key.gsub('/', '_')}.png"
        path = File.join(Dir.tempdir, filename)
        unless File.exists?(path)
          File.write(path, bytes)
          @@temporary_icons << path
        end
        "file://#{path}"
      else
        icon.name
      end
    end
  end

  class NativeDesktop::Platform::NotificationEventSource < NativeDesktop::NotificationEventSource
    @@emit : Proc(NativeDesktop::NotificationEvent, Nil)?

    def start(&emit : NativeDesktop::NotificationEvent ->) : Nil
      @@emit = emit
    end

    def self.emit(event : NativeDesktop::NotificationEvent) : Nil
      @@emit.try(&.call(event))
    end

    def stop : Nil
      @@emit = nil
    end
  end

  NativeDesktop::Notifications.install_event_source(NativeDesktop::Platform::NotificationEventSource.new)
{% end %}
