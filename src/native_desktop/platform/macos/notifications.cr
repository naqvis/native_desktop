{% if flag?(:darwin) %}
  module NativeDesktop::Platform::Notifications
    extend self
    alias ObjC = NativeDesktop::Platform::MacOS::ObjC

    @[Link(ldflags: "#{__DIR__}/notifications.mm -framework UserNotifications -framework Foundation -lc++")]
    lib LibNotifications
      fun request_permission = native_desktop_notifications_request_permission : LibC::Int
      fun permission_granted = native_desktop_notifications_permission_granted : LibC::Int
      fun set_event_callback = native_desktop_notifications_set_event_callback(callback : Void*) : Nil
    end

    @@modern : Bool? = nil

    def request_permission(application_name : String) : Bool
      return true unless modern?
      LibNotifications.request_permission != 0
    end

    def permission_state : PermissionState
      return PermissionState::Unknown unless modern?
      LibNotifications.permission_granted != 0 ? PermissionState::Granted : PermissionState::Unknown
    end

    def show(application_name : String, request : NotificationRequest) : Nil
      if modern?
        show_modern(request)
      else
        show_legacy(request)
      end
    rescue ex
      @@modern = false
      show_legacy(request)
    end

    def close(id : String) : Nil
      if modern?
        ObjC.pool do
          identifiers = ObjC.msg(ObjC.klass("NSArray"), "arrayWithObject:", ObjC.string(id))
          ObjC.msg(modern_center, "removeDeliveredNotificationsWithIdentifiers:", identifiers)
        end
      else
        close_legacy(id)
      end
    rescue
    end

    private def modern? : Bool
      cached = @@modern
      return cached unless cached.nil?

      bundle = ObjC.msg(ObjC.klass("NSBundle"), "mainBundle")
      bundle_path = ObjC.to_s(ObjC.msg(bundle, "bundlePath"))
      return @@modern = false unless bundle_path.try(&.ends_with?(".app"))

      klass = ObjC.klass("UNUserNotificationCenter")
      @@modern = !klass.null? && !ObjC.msg(klass, "currentNotificationCenter").null?
    rescue
      @@modern = false
    end

    private def modern_center : Void*
      ObjC.msg(ObjC.klass("UNUserNotificationCenter"), "currentNotificationCenter")
    end

    private def legacy_center : Void*
      ObjC.msg(ObjC.klass("NSUserNotificationCenter"), "defaultUserNotificationCenter")
    end

    private def show_modern(request : NotificationRequest) : Nil
      LibNotifications.permission_granted
      ObjC.pool do
        content = ObjC.msg(ObjC.msg(ObjC.klass("UNMutableNotificationContent"), "alloc"), "init")
        ObjC.msg(content, "setTitle:", ObjC.string(request.title))
        ObjC.msg(content, "setBody:", ObjC.string(request.body))

        native_request = ObjC.msg(
          ObjC.klass("UNNotificationRequest"),
          "requestWithIdentifier:content:trigger:",
          ObjC.string(request.id),
          content,
          Pointer(Void).null
        )
        ObjC.msg(modern_center, "addNotificationRequest:withCompletionHandler:", native_request, Pointer(Void).null)
      end
    end

    private def show_legacy(request : NotificationRequest) : Nil
      ObjC.pool do
        notification = ObjC.msg(ObjC.msg(ObjC.klass("NSUserNotification"), "alloc"), "init")
        ObjC.msg(notification, "setTitle:", ObjC.string(request.title))
        ObjC.msg(notification, "setInformativeText:", ObjC.string(request.body))
        ObjC.msg(notification, "setIdentifier:", ObjC.string(request.id))
        if action = request.actions.first?
          ObjC.msg(notification, "setActionButtonTitle:", ObjC.string(action.label))
          ObjC.msg_long(notification, "setHasActionButton:", 1)
        end
        ObjC.msg(legacy_center, "deliverNotification:", notification)
      end
    end

    private def close_legacy(id : String) : Nil
      ObjC.pool do
        center = legacy_center
        delivered = ObjC.msg(center, "deliveredNotifications")
        ObjC.long(delivered, "count").times do |index|
          notification = ObjC.msg_index(delivered, "objectAtIndex:", index.to_u64)
          next unless ObjC.to_s(ObjC.msg(notification, "identifier")) == id
          ObjC.msg(center, "removeDeliveredNotification:", notification)
          break
        end
      end
    end
  end

  class NativeDesktop::Platform::NotificationEventSource < NativeDesktop::NotificationEventSource
    @@emit : Proc(NativeDesktop::NotificationEvent, Nil)?

    def start(&emit : NativeDesktop::NotificationEvent ->) : Nil
      @@emit = emit
      callback = ->(identifier : UInt8*, action : UInt8*) {
        id = identifier.null? ? "" : String.new(identifier)
        unless id.empty?
          action_id = action.null? ? nil : String.new(action)
          action_id = nil if action_id.try(&.empty?)
          type = action_id ? NotificationEventTypes::ActionSelected : NotificationEventTypes::Activated
          @@emit.try(&.call(NotificationEvent.new(id, type, action_id)))
        end
      }
      NativeDesktop::Platform::Notifications::LibNotifications.set_event_callback(callback.pointer)
    end

    def stop : Nil
      NativeDesktop::Platform::Notifications::LibNotifications.set_event_callback(Pointer(Void).null)
      @@emit = nil
    end
  end

  NativeDesktop::Notifications.install_event_source(NativeDesktop::Platform::NotificationEventSource.new)
{% end %}
