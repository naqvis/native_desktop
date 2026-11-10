require "json"

module NativeDesktop
  # :nodoc:
  module SynthesisTuning
    extend self

    # Maps a Web Speech rate around its neutral value of 1.0 onto a native
    # signed range while preserving both public endpoints.
    def signed_rate(rate : Float64, magnitude : Int32) : Int32
      scaled = if rate <= 1.0
                 (rate - 1.0) / 0.9
               else
                 (rate - 1.0) / 9.0
               end
      (scaled * magnitude).round.to_i.clamp(-magnitude, magnitude)
    end

    def signed_pitch(pitch : Float64, magnitude : Int32) : Int32
      ((pitch - 1.0) * magnitude).round.to_i.clamp(-magnitude, magnitude)
    end

    # Speech Dispatcher expresses volume as -100..100 rather than 0..1.
    def dispatcher_volume(volume : Float64) : Int32
      (volume * 200.0 - 100.0).round.to_i.clamp(-100, 100)
    end

    def xml_escape(text : String) : String
      String.build(text.bytesize) do |io|
        text.each_char do |char|
          case char
          when '&'  then io << "&amp;"
          when '<'  then io << "&lt;"
          when '>'  then io << "&gt;"
          when '"'  then io << "&quot;"
          when '\'' then io << "&apos;"
          else           io << char
          end
        end
      end
    end
  end

  # A speech-synthesis voice installed on the host.
  struct Voice
    include JSON::Serializable

    getter id : String
    getter name : String
    getter lang : String
    getter? local : Bool

    # Platform voice variant, such as `compact`, `enhanced`, or `premium`.
    getter variant : String?

    def initialize(@id : String, @name : String, @lang : String, @local = true, @variant : String? = nil)
      raise ArgumentError.new("voice id cannot be empty") if id.empty?
      raise ArgumentError.new("voice name cannot be empty") if name.empty?
      raise ArgumentError.new("voice language cannot be empty") if lang.empty?
      raise ArgumentError.new("voice variant cannot be empty") if variant.try(&.empty?)
    end

    # BCP 47 language tag.
    def language : String
      lang
    end
  end

  # Tunable parameters for one utterance.
  struct SynthesisOptions
    getter voice : Voice?
    getter rate : Float64
    getter pitch : Float64
    getter volume : Float64

    def initialize(@voice : Voice? = nil, @rate = 1.0, @pitch = 1.0, @volume = 1.0)
      validate_rate(rate)
      validate_pitch(pitch)
      validate_volume(volume)
    end

    def voice=(voice : Voice?) : Voice?
      @voice = voice
    end

    def rate=(rate : Float64) : Float64
      validate_rate(rate)
      @rate = rate
    end

    def pitch=(pitch : Float64) : Float64
      validate_pitch(pitch)
      @pitch = pitch
    end

    def volume=(volume : Float64) : Float64
      validate_volume(volume)
      @volume = volume
    end

    private def validate_rate(rate : Float64) : Nil
      raise ArgumentError.new("speech rate must be between 0.1 and 10.0") unless rate.in?(0.1..10.0)
    end

    private def validate_pitch(pitch : Float64) : Nil
      raise ArgumentError.new("speech pitch must be between 0.0 and 2.0") unless pitch.in?(0.0..2.0)
    end

    private def validate_volume(volume : Float64) : Nil
      raise ArgumentError.new("speech volume must be between 0.0 and 1.0") unless volume.in?(0.0..1.0)
    end
  end

  # One partial or final transcript produced by the operating system.
  struct RecognitionResult
    include JSON::Serializable

    getter transcript : String
    getter? final : Bool
    getter confidence : Float64?

    def initialize(@transcript : String, @final : Bool, @confidence : Float64? = nil)
      raise ArgumentError.new("recognition transcript cannot be empty") if transcript.empty?
      if confidence = @confidence
        raise ArgumentError.new("recognition confidence must be between 0.0 and 1.0") unless confidence.in?(0.0..1.0)
      end
    end
  end

  # Microphone/speech-recognition authorization reported by the OS.
  enum SpeechRecognitionPermission
    Unknown
    Denied
    Granted
  end

  module Platform
    enum RecognitionEventKind
      Result
      Error
      Ended
    end

    # :nodoc:
    record RecognitionEvent,
      kind : RecognitionEventKind,
      text : String? = nil,
      final : Bool = false,
      confidence : Float64? = nil,
      code : Symbol? = nil
  end

  # Owns a platform text-to-speech engine. Call `#cleanup` when finished.
  class SpeechSynthesizer
    @native : Platform::SpeechSynthesizer?
    @closed = false

    def initialize
    end

    # Returns the voices available to the platform speech engine.
    def voices : Array(Voice)
      Runtime.dispatch_sync { native.voices }
    end

    # Starts speaking *text*. A new utterance replaces the current one.
    def speak(text : String, options : SynthesisOptions = SynthesisOptions.new) : Nil
      raise ArgumentError.new("speech text cannot be empty") if text.empty?
      Runtime.dispatch_sync { native.speak(text, options) }
    end

    def stop : Nil
      Runtime.dispatch_sync { native.stop }
    end

    def pause : Nil
      Runtime.dispatch_sync { native.pause }
    end

    def resume : Nil
      Runtime.dispatch_sync { native.resume }
    end

    def speaking? : Bool
      Runtime.dispatch_sync { native.speaking? }
    end

    # Releases the native engine. Further use raises `NativeDesktop::Error`.
    def cleanup : Nil
      Runtime.dispatch_sync do
        next if @closed
        @closed = true
        @native.try(&.cleanup)
        @native = nil
      end
    end

    private def native : Platform::SpeechSynthesizer
      raise Error.new("speech synthesizer has been closed", :speech_closed) if @closed
      @native ||= Platform::SpeechSynthesizer.new
    end
  end

  # Owns an operating-system speech recognizer. Linux currently reports the
  # service as unavailable because it has no standard system STT API.
  class SpeechRecognizer
    @native : Platform::SpeechRecognizer?
    @closed = false
    @generation = 0_u64
    @result_handlers = [] of Proc(RecognitionResult, Nil)
    @error_handlers = [] of Proc(Error, Nil)
    @end_handlers = [] of Proc(Nil)

    def initialize
    end

    # Returns the BCP 47 language tags supported by the system recognizer.
    # A listed language may still be temporarily unavailable.
    def languages : Array(String)
      Runtime.dispatch_sync { Platform::SpeechRecognizer.languages }
    end

    def available?(language : String = "en-US") : Bool
      raise ArgumentError.new("recognition language cannot be empty") if language.empty?
      Runtime.dispatch_sync { Platform::SpeechRecognizer.available?(language) }
    end

    def permission : SpeechRecognitionPermission
      Runtime.dispatch_sync { Platform::SpeechRecognizer.permission }
    end

    # Requests every OS permission needed for microphone recognition.
    def request_permission : SpeechRecognitionPermission
      Runtime.dispatch_sync { Platform::SpeechRecognizer.request_permission }
    end

    def start(language : String = "en-US", interim : Bool = true) : Nil
      raise ArgumentError.new("recognition language cannot be empty") if language.empty?

      Runtime.dispatch_sync do
        service = native
        if service.listening?
          raise Error.new("speech recognition is already active", :speech_recognition_active)
        end
        service.start(language, interim)
      end
      generation = @generation &+= 1
      begin
        Runtime.spawn_background { poll(generation) }
      rescue ex
        @generation &+= 1
        Runtime.dispatch_sync { @native.try(&.abort) } rescue nil
        raise ex
      end
    end

    def stop : Nil
      Runtime.dispatch_sync { @native.try(&.stop) }
    end

    def abort : Nil
      was_listening = Runtime.dispatch_sync { @native.try(&.listening?) || false }
      @generation &+= 1
      Runtime.dispatch_sync { @native.try(&.abort) }
      @end_handlers.each(&.call) if was_listening
    end

    def listening? : Bool
      Runtime.dispatch_sync { @native.try(&.listening?) || false }
    end

    def on_result(&block : RecognitionResult ->) : Nil
      @result_handlers << block
    end

    def on_error(&block : Error ->) : Nil
      @error_handlers << block
    end

    def on_end(&block : ->) : Nil
      @end_handlers << block
    end

    def cleanup : Nil
      @generation &+= 1
      Runtime.dispatch_sync do
        next if @closed
        @closed = true
        @native.try(&.cleanup)
        @native = nil
      end
    end

    private def native : Platform::SpeechRecognizer
      raise Error.new("speech recognizer has been closed", :speech_closed) if @closed
      @native ||= Platform::SpeechRecognizer.new
    end

    private def poll(generation : UInt64) : Nil
      loop do
        break unless generation == @generation
        event = Runtime.dispatch_sync { @native.try(&.poll) }
        if event
          case event.kind
          in Platform::RecognitionEventKind::Result
            result = RecognitionResult.new(event.text || "", event.final, event.confidence)
            @result_handlers.each(&.call(result))
          in Platform::RecognitionEventKind::Error
            error = Error.new(event.text || "speech recognition failed", event.code || :speech_recognition_failed)
            @error_handlers.each(&.call(error))
          in Platform::RecognitionEventKind::Ended
            @end_handlers.each(&.call)
            break
          end
        elsif !Runtime.dispatch_sync { @native.try(&.listening?) || false }
          break
        else
          sleep 20.milliseconds
        end
      end
    rescue ex
      error = ex.is_a?(Error) ? ex : Error.new(ex.message || "speech recognition failed", :speech_recognition_failed)
      @error_handlers.each(&.call(error))
    end
  end
end

module NativeDesktop
  class SpeechPermissionProvider < PlatformPermissionProvider
    def initialize(id : PermissionId)
      super(id)
    end

    def status : PermissionInfo
      recognizer = SpeechRecognizer.new
      state = permission_state(recognizer.permission)
      PermissionInfo.new(id, state, state.unknown?, settings_available?)
    ensure
      recognizer.try(&.cleanup)
    end

    def request : PermissionInfo
      recognizer = SpeechRecognizer.new
      state = permission_state(recognizer.request_permission)
      PermissionInfo.new(id, state, state.unknown?, settings_available?)
    ensure
      recognizer.try(&.cleanup)
    end

    private def permission_state(value : SpeechRecognitionPermission) : PermissionState
      case value
      when .granted? then PermissionState::Granted
      when .denied?  then PermissionState::Denied
      else                PermissionState::Unknown
      end
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::SpeechSynthesis, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Capabilities.register(NativeDesktop::Features::SpeechRecognition, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Permissions.register(NativeDesktop::SpeechPermissionProvider.new(NativeDesktop::PermissionIds::Microphone))
NativeDesktop::Permissions.register(NativeDesktop::SpeechPermissionProvider.new(NativeDesktop::PermissionIds::SpeechRecognition))

{% if flag?(:darwin) %}
  require "./platform/macos/speech"
{% elsif flag?(:linux) %}
  require "./platform/linux/speech"
{% elsif flag?(:windows) %}
  require "./platform/windows/speech"
{% end %}
