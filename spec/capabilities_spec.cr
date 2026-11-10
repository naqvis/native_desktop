require "./spec_helper"

describe NativeDesktop::Capabilities do
  it "reports registered features with explicit support states" do
    values = NativeDesktop.capabilities.all
    values.should_not be_empty
    values.map(&.feature).uniq.size.should eq(values.size)
  end

  it "accepts extension-defined feature identifiers" do
    feature = NativeDesktop::FeatureId["example.extension"]
    NativeDesktop.capabilities.register(feature, NativeDesktop::CapabilityState::Supported)
    NativeDesktop.capabilities.status(feature).supported?.should be_true
  ensure
    NativeDesktop.capabilities.unregister(feature.not_nil!)
  end

  it "stacks overrides and restores the previous resolver" do
    feature = NativeDesktop::FeatureId["example.override"]
    NativeDesktop.capabilities.status(feature).state.unavailable?.should be_true
    NativeDesktop.capabilities.register(feature, NativeDesktop::CapabilityState::Unsupported)
    NativeDesktop.capabilities.register(feature, NativeDesktop::CapabilityState::Supported)
    NativeDesktop.capabilities.status(feature).supported?.should be_true
    NativeDesktop.capabilities.unregister(feature)
    NativeDesktop.capabilities.status(feature).state.unsupported?.should be_true
  ensure
    NativeDesktop.capabilities.unregister(feature.not_nil!)
  end
end
