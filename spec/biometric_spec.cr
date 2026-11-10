require "./spec_helper"

describe NativeDesktop::Biometrics do
  it "models capability information" do
    info = NativeDesktop::BiometricInfo.new(
      available: true,
      modality: NativeDesktop::BiometricModality::Fingerprint,
      reason_supported: false,
    )
    info.available?.should be_true
    info.modality.should eq(NativeDesktop::BiometricModality::Fingerprint)
    info.reason_supported?.should be_false
  end

  it "models authentication results" do
    NativeDesktop::BiometricResult.new(true).success?.should be_true
    failure = NativeDesktop::BiometricResult.new(false, "canceled")
    failure.success?.should be_false
    failure.error.should eq("canceled")
  end

  it "rejects an empty prompt reason before invoking the platform" do
    expect_raises(ArgumentError) { NativeDesktop.biometric.authenticate("") }
  end

  it "returns a consistent platform capability snapshot" do
    info = NativeDesktop.biometric.info
    info.modality.should_not be_nil if info.available?
  end
end
