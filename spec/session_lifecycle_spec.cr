require "./spec_helper"

class SpecSessionEventSource < NativeDesktop::SessionEventSource
  getter? closed = false

  def process_event(event : Void*, &emit : NativeDesktop::SessionEvent ->) : Bool
    emit.call(NativeDesktop::SessionEvent.new(NativeDesktop::SessionEventType["extension.session-event"]))
    true
  end

  def close : Nil
    @closed = true
  end
end

describe NativeDesktop::SessionLifecycle do
  after_each do
    NativeDesktop.session.clear
  end

  it "delivers host-forwarded lifecycle events without an attached runtime" do
    events = [] of NativeDesktop::SessionEvent
    NativeDesktop.session.on_event { |event| events << event }
    NativeDesktop.session.emit(NativeDesktop::SessionEventTypes::Suspend)
    events.first.type.should eq(NativeDesktop::SessionEventTypes::Suspend)
  end

  it "delegates opaque native events to installed sources" do
    source = SpecSessionEventSource.new
    events = [] of NativeDesktop::SessionEvent
    registration = NativeDesktop.session.install(source)
    NativeDesktop.session.on_event { |event| events << event }
    NativeDesktop.session.process_event(Pointer(Void).null).should be_true
    events.first.type.should eq(NativeDesktop::SessionEventType["extension.session-event"])
    registration.close
    source.closed?.should be_true
  end

  it "removes only the handler owned by a registration" do
    first = [] of NativeDesktop::SessionEvent
    second = [] of NativeDesktop::SessionEvent
    registration = NativeDesktop.session.on_event { |event| first << event }
    NativeDesktop.session.on_event { |event| second << event }

    registration.close
    event = NativeDesktop::SessionEvent.new(NativeDesktop::SessionEventTypes::Lock)
    NativeDesktop.session.emit(event)

    first.should be_empty
    second.should eq([event])
  end
end
