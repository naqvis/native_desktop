require "./spec_helper"

class SpecActivationSource < NativeDesktop::ActivationSource
  getter? stopped = false
  @emit : Proc(NativeDesktop::Activation, Nil)?

  def start(&emit : NativeDesktop::Activation ->) : Nil
    @emit = emit
  end

  def fire(event : NativeDesktop::Activation) : Nil
    @emit.not_nil!.call(event)
  end

  def stop : Nil
    @stopped = true
  end
end

describe NativeDesktop::Activations do
  after_each do
    NativeDesktop.activations.clear_handlers
    NativeDesktop.activations.clear_pending
  end

  it "queues cold-start events and replays them to the first handler" do
    event = NativeDesktop::Activation.url("example:test")
    NativeDesktop.activations.emit(event)
    NativeDesktop.activations.pending.should eq([event])

    received = [] of NativeDesktop::Activation
    NativeDesktop.activations.on_event { |value| received << value }
    received.should eq([event])
    NativeDesktop.activations.pending.should be_empty
  end

  it "classifies command-line arguments through an application callback" do
    received = [] of NativeDesktop::Activation
    NativeDesktop.activations.on_event { |value| received << value }
    NativeDesktop.activations.capture_arguments(["example:test", __FILE__, "not-an-activation"]) do |argument|
      if argument == "example:test"
        NativeDesktop::Activation.url(argument)
      elsif argument == __FILE__
        NativeDesktop::Activation.files([argument])
      end
    end
    received.map(&.type).should contain(NativeDesktop::ActivationTypes::URL)
    received.map(&.type).should contain(NativeDesktop::ActivationTypes::Files)
  end

  it "accepts extension-defined activation types through an installed source" do
    source = SpecActivationSource.new
    type = NativeDesktop::ActivationType["extension.activation"]
    received = [] of NativeDesktop::Activation
    registration = NativeDesktop.activations.install(source)
    NativeDesktop.activations.on_event { |event| received << event }
    source.fire(NativeDesktop::Activation.new(type, ["payload"]))
    received.first.type.should eq(type)
    registration.close
    source.stopped?.should be_true
    NativeDesktop.activations.source_installed?.should be_true
  end

  it "removes only the handler owned by a registration" do
    first = [] of NativeDesktop::Activation
    second = [] of NativeDesktop::Activation
    registration = NativeDesktop.activations.on_event(replay_pending: false) { |event| first << event }
    NativeDesktop.activations.on_event(replay_pending: false) { |event| second << event }

    registration.close
    event = NativeDesktop::Activation.url("example:scoped")
    NativeDesktop.activations.emit(event)

    first.should be_empty
    second.should eq([event])
  end
end
