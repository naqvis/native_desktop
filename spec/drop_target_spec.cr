require "./spec_helper"

class SpecDropTargetAdapter < NativeDesktop::DropTargetAdapter
  getter close_count = 0
  @emit : Proc(NativeDesktop::DropEvent, Bool)?

  def attach(window : NativeDesktop::Window, kinds : Set(NativeDesktop::DragKind), &emit : NativeDesktop::DropEvent -> Bool) : Nil
    @emit = emit
  end

  def fire(event : NativeDesktop::DropEvent) : Bool
    @emit.not_nil!.call(event)
  end

  def close : Nil
    @close_count += 1
  end
end

describe NativeDesktop::DropTarget do
  after_each { NativeDesktop::Runtime.detach }

  it "filters forwarded drops and cleans up its adapter once" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    window = NativeDesktop::Window.attach(Pointer(Void).new(1_u64))
    received = [] of NativeDesktop::DropEvent
    adapter = SpecDropTargetAdapter.new
    target = NativeDesktop::DropTarget.new(window, adapter, [NativeDesktop::DragKind::File]) { |event| received << event }
    event = NativeDesktop::DropEvent.new([
      NativeDesktop::DragPayload.text("ignored"),
      NativeDesktop::DragPayload.file(__FILE__),
    ])
    adapter.fire(event).should be_true
    received.first.payloads.map(&.kind).should eq([NativeDesktop::DragKind::File])
    target.close
    target.close
    target.closed?.should be_true
    adapter.close_count.should eq(1)
  end

  it "accepts extension-defined drop operations" do
    NativeDesktop::DropOperation["extension.drop"].value.should eq("extension.drop")
  end

  it "layers adapter providers and restores the previous provider" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    window = NativeDesktop::Window.attach(Pointer(Void).new(1_u64))
    outer_adapter = SpecDropTargetAdapter.new
    inner_adapter = SpecDropTargetAdapter.new
    outer = NativeDesktop::DropTargets.register { outer_adapter }
    inner = NativeDesktop::DropTargets.register { inner_adapter }

    begin
      inner_events = [] of NativeDesktop::DropEvent
      inner_target = NativeDesktop::DropTarget.new(window, [NativeDesktop::DragKind::Text]) { |event| inner_events << event }
      inner_adapter.fire(NativeDesktop::DropEvent.new([NativeDesktop::DragPayload.text("inner")])).should be_true
      inner_events.first.payloads.first.value.should eq("inner")
      inner_target.close

      inner.close
      outer_events = [] of NativeDesktop::DropEvent
      outer_target = NativeDesktop::DropTarget.new(window, [NativeDesktop::DragKind::Text]) { |event| outer_events << event }
      outer_adapter.fire(NativeDesktop::DropEvent.new([NativeDesktop::DragPayload.text("outer")])).should be_true
      outer_events.first.payloads.first.value.should eq("outer")
      outer_target.close
    ensure
      inner.close
      outer.close
    end
  end
end
