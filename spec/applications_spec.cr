require "./spec_helper"

describe NativeDesktop::Applications do
  it "returns a foreground name or nil without shelling out" do
    NativeDesktop.applications.foreground_name.should be_a(String | Nil)
  end

  it "rejects an empty open target" do
    expect_raises(ArgumentError) { NativeDesktop.applications.open("") }
  end
end
