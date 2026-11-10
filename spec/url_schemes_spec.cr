require "./spec_helper"

describe NativeDesktop::URLSchemes do
  it "accepts standard URI scheme syntax" do
    registration = NativeDesktop::URLSchemeRegistration.new("My-App+1.0", "Example", Path["/tmp/example"])
    registration.scheme.should eq("My-App+1.0")
  end

  it "rejects invalid schemes before touching the OS" do
    ["", "1app", "app_name", "app/name", "app scheme"].each do |scheme|
      expect_raises(ArgumentError) do
        NativeDesktop.url_schemes.register(NativeDesktop::URLSchemeRegistration.new(scheme, "Example", Path["/tmp/example"]))
      end
    end
  end

  it "rejects an empty application name and relative executable" do
    expect_raises(ArgumentError) do
      NativeDesktop.url_schemes.register(NativeDesktop::URLSchemeRegistration.new("example", " ", Path["/tmp/example"]))
    end
    expect_raises(ArgumentError) do
      NativeDesktop.url_schemes.register(NativeDesktop::URLSchemeRegistration.new("example", "Example", Path["relative"]))
    end
  end

  it "validates unregister requests" do
    expect_raises(ArgumentError) { NativeDesktop.url_schemes.unregister("not valid") }
  end
end
