require "./spec_helper"

describe NativeDesktop::SpeechSynthesizer do
  after_each { NativeDesktop::Runtime.detach }

  it "validates voice metadata" do
    voice = NativeDesktop::Voice.new("voice-id", "Example", "en-US")
    voice.language.should eq("en-US")
    voice.local?.should be_true
    voice.variant.should be_nil

    premium = NativeDesktop::Voice.new("premium-id", "Example", "en-US", variant: "premium")
    premium.variant.should eq("premium")

    expect_raises(ArgumentError) { NativeDesktop::Voice.new("", "Example", "en-US") }
    expect_raises(ArgumentError) { NativeDesktop::Voice.new("voice-id", "Example", "en-US", variant: "") }
  end

  it "validates synthesis options" do
    NativeDesktop::SynthesisOptions.new(rate: 0.1, pitch: 0.0, volume: 0.0)
    NativeDesktop::SynthesisOptions.new(rate: 10.0, pitch: 2.0, volume: 1.0)
    expect_raises(ArgumentError) { NativeDesktop::SynthesisOptions.new(rate: 0.0) }
    expect_raises(ArgumentError) { NativeDesktop::SynthesisOptions.new(pitch: 2.1) }
    expect_raises(ArgumentError) { NativeDesktop::SynthesisOptions.new(volume: 1.1) }

    options = NativeDesktop::SynthesisOptions.new
    expect_raises(ArgumentError) { options.rate = 0.0 }
  end

  it "maps Web Speech tuning values onto native ranges" do
    tuning = NativeDesktop::SynthesisTuning
    tuning.signed_rate(0.1, 100).should eq(-100)
    tuning.signed_rate(1.0, 100).should eq(0)
    tuning.signed_rate(10.0, 100).should eq(100)
    tuning.signed_pitch(0.0, 10).should eq(-10)
    tuning.signed_pitch(1.0, 10).should eq(0)
    tuning.signed_pitch(2.0, 10).should eq(10)
    tuning.dispatcher_volume(0.0).should eq(-100)
    tuning.dispatcher_volume(0.5).should eq(0)
    tuning.dispatcher_volume(1.0).should eq(100)
  end

  it "escapes text before wrapping it in platform synthesis markup" do
    NativeDesktop::SynthesisTuning.xml_escape(%(<speak "now"> & 'later')).should eq(
      "&lt;speak &quot;now&quot;&gt; &amp; &apos;later&apos;"
    )
  end

  it "requires the attached GUI runtime" do
    expect_raises(NativeDesktop::RuntimeError) { NativeDesktop.speech.voices }
  end

  it "cannot be reused after cleanup" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    speech = NativeDesktop.speech
    speech.cleanup
    speech.cleanup
    error = expect_raises(NativeDesktop::Error) { speech.voices }
    error.code.should eq(:speech_closed)
  end
end

describe NativeDesktop::SpeechRecognizer do
  after_each { NativeDesktop::Runtime.detach }

  it "validates recognition results" do
    result = NativeDesktop::RecognitionResult.new("hello", true, 0.8)
    result.transcript.should eq("hello")
    result.final?.should be_true
    result.confidence.should eq(0.8)
    expect_raises(ArgumentError) { NativeDesktop::RecognitionResult.new("", true) }
    expect_raises(ArgumentError) { NativeDesktop::RecognitionResult.new("hello", true, 1.1) }
  end

  it "requires the attached GUI runtime" do
    recognizer = NativeDesktop::SpeechRecognizer.new
    expect_raises(NativeDesktop::RuntimeError) { recognizer.available? }
  end

  it "is idle before the native recognizer is created" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    recognizer = NativeDesktop::SpeechRecognizer.new
    recognizer.listening?.should be_false
    recognizer.stop
    recognizer.abort
    recognizer.cleanup
    recognizer.cleanup
  end

  it "lists the languages supported by the system recognizer" do
    NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
    languages = NativeDesktop::SpeechRecognizer.new.languages

    languages.should eq(languages.uniq)
    languages.each(&.should_not(be_empty))
    {% if flag?(:linux) %}
      languages.should be_empty
    {% else %}
      languages.should_not be_empty
    {% end %}
  end

  {% if flag?(:linux) %}
    it "reports that the system recognizer is unavailable" do
      NativeDesktop::Runtime.attach_to_current_thread { |work| work.call }
      recognizer = NativeDesktop::SpeechRecognizer.new

      error = expect_raises(NativeDesktop::Error) { recognizer.start }
      error.code.should eq(:speech_recognition_unavailable)
      recognizer.cleanup
    end
  {% end %}
end
