require "./spec_helper"

class SpecPermissionProvider < NativeDesktop::PermissionProvider
  def initialize(id : NativeDesktop::PermissionId, @state = NativeDesktop::PermissionState::Granted)
    super(id)
  end

  def status : NativeDesktop::PermissionInfo
    NativeDesktop::PermissionInfo.new(id, @state)
  end
end

describe NativeDesktop::Permissions do
  it "registers the platform accessibility provider" do
    info = NativeDesktop.permissions.status(NativeDesktop::PermissionIds::Accessibility)
    info.permission.should eq(NativeDesktop::PermissionIds::Accessibility)
    info.state.unknown?.should be_false
  end

  it "accepts extension-defined permission providers" do
    id = NativeDesktop::PermissionId["example.permission"]
    NativeDesktop.permissions.register(SpecPermissionProvider.new(id))
    NativeDesktop.permissions.status(id).state.granted?.should be_true
  ensure
    NativeDesktop.permissions.unregister(id.not_nil!)
  end

  it "stacks providers and restores the previous provider" do
    id = NativeDesktop::PermissionId["example.permission-override"]
    NativeDesktop.permissions.register(SpecPermissionProvider.new(id, NativeDesktop::PermissionState::Denied))
    NativeDesktop.permissions.register(SpecPermissionProvider.new(id, NativeDesktop::PermissionState::Granted))
    NativeDesktop.permissions.status(id).state.granted?.should be_true
    NativeDesktop.permissions.unregister(id)
    NativeDesktop.permissions.status(id).state.denied?.should be_true
  ensure
    NativeDesktop.permissions.unregister(id.not_nil!)
  end

  it "returns an unavailable state for unregistered permissions" do
    id = NativeDesktop::PermissionId["example.missing"]

    info = NativeDesktop.permissions.status(id)
    info.permission.should eq(id)
    info.state.unavailable?.should be_true
    info.can_request.should be_false
    info.settings_available.should be_false

    NativeDesktop.permissions.request(id).state.unavailable?.should be_true
    NativeDesktop.permissions.open_settings(id).should be_false
  end
end
