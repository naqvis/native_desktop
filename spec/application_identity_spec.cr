require "./spec_helper"

describe NativeDesktop::Application do
  it "stores application identity and produces actionable diagnostics" do
    identity = NativeDesktop::ApplicationIdentity.new(
      "dev.example.native-desktop",
      "Native Desktop",
      Path[Process.executable_path.not_nil!].expand
    )
    NativeDesktop.application.configure(identity)
    NativeDesktop.application.identity.should eq(identity)
    NativeDesktop.application.diagnostics.should_not be_empty
  end

  it "supports extension-owned diagnostic providers" do
    NativeDesktop.application.register_diagnostics("example.diagnostics") do
      [NativeDesktop::Diagnostic.new("example.problem", "Example diagnostic")]
    end
    NativeDesktop.application.diagnostics.map(&.id).should contain("example.problem")
  ensure
    NativeDesktop.application.unregister_diagnostics("example.diagnostics")
  end
end
