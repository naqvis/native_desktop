require "./spec_helper"

class SpecNotificationEventSource < NativeDesktop::NotificationEventSource
  getter? stopped = false
  @emit : Proc(NativeDesktop::NotificationEvent, Nil)?

  def start(&emit : NativeDesktop::NotificationEvent ->) : Nil
    @emit = emit
  end

  def fire(event : NativeDesktop::NotificationEvent) : Nil
    @emit.not_nil!.call(event)
  end

  def stop : Nil
    @stopped = true
  end
end

describe NativeDesktop::NotificationRequest do
  it "stores notification values" do
    action = NativeDesktop::NotificationAction.new("open", "Open")
    request = NativeDesktop::NotificationRequest.new(
      "build-complete",
      "Build complete",
      "The application is ready.",
      urgency: NativeDesktop::NotificationUrgency::Low,
      timeout: 5.seconds,
      actions: [action]
    )

    request.id.should eq("build-complete")
    request.title.should eq("Build complete")
    request.body.should eq("The application is ready.")
    request.urgency.low?.should be_true
    request.timeout.should eq(5.seconds)
    request.actions.should eq([action])
  end

  it "rejects missing identifiers and titles" do
    expect_raises(ArgumentError) { NativeDesktop::NotificationRequest.new("", "Title") }
    expect_raises(ArgumentError) { NativeDesktop::NotificationRequest.new("id", "") }
  end
end

describe NativeDesktop::Notifications do
  after_each do
    NativeDesktop.notifications.clear_event_handlers
    NativeDesktop::Runtime.detach
  end

  it "installs the bundled platform event source" do
    NativeDesktop.notifications.event_source_installed?.should be_true
  end

  it "requires an attached GUI runtime" do
    NativeDesktop::Runtime.detach
    request = NativeDesktop::NotificationRequest.new("id", "Title")

    expect_raises(NativeDesktop::RuntimeError) do
      NativeDesktop.notifications.show("Example", request)
    end
  end

  it "delivers events from an installed source and stops it on removal" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    events = [] of NativeDesktop::NotificationEvent
    source = SpecNotificationEventSource.new
    registration = NativeDesktop.notifications.install_event_source(source)
    NativeDesktop.notifications.on_event { |event| events << event }
    source.fire(NativeDesktop::NotificationEvent.new(
      "download",
      NativeDesktop::NotificationEventTypes::ActionSelected,
      "open"
    ))
    events.first.type.should eq(NativeDesktop::NotificationEventTypes::ActionSelected)
    events.first.action_id.should eq("open")
    registration.close
    source.stopped?.should be_true
    NativeDesktop.notifications.event_source_installed?.should be_true
  end

  it "accepts extension-defined event types" do
    NativeDesktop::NotificationEventType["extension.notification"].value.should eq("extension.notification")
  end

  it "removes only the handler owned by a registration" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    first = [] of NativeDesktop::NotificationEvent
    second = [] of NativeDesktop::NotificationEvent
    registration = NativeDesktop.notifications.on_event { |event| first << event }
    NativeDesktop.notifications.on_event { |event| second << event }

    registration.close
    event = NativeDesktop::NotificationEvent.new("scoped", NativeDesktop::NotificationEventTypes::Activated)
    NativeDesktop.notifications.emit(event)

    first.should be_empty
    second.should eq([event])
  end
end
