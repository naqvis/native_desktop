@[Link(ldflags: "#{__DIR__}/speech.c -lspeechd")]
@[Link("speechd", pkg_config: "speech-dispatcher")]
lib LibNativeDesktopSpeechD
  fun open = native_desktop_speech_open : Void*
  fun configure = native_desktop_speech_configure(connection : Void*, voice_name : UInt8*, language : UInt8*, rate : Int32, pitch : Int32, volume : Int32) : Int32
  fun say = native_desktop_speech_say(connection : Void*, text : UInt8*) : Int32
  fun stop = native_desktop_speech_stop(connection : Void*) : Int32
  fun pause = native_desktop_speech_pause(connection : Void*) : Int32
  fun resume = native_desktop_speech_resume(connection : Void*) : Int32
  fun speaking = native_desktop_speech_speaking(connection : Void*) : Int32
  fun close = native_desktop_speech_close(connection : Void*) : Nil
  fun list_voices = native_desktop_speech_list_voices(connection : Void*) : Void*
  fun voice_count = native_desktop_speech_voice_count(voices : Void*) : UInt64
  fun voice_name = native_desktop_speech_voice_name(voices : Void*, index : UInt64) : UInt8*
  fun voice_language = native_desktop_speech_voice_language(voices : Void*, index : UInt64) : UInt8*
  fun voice_variant = native_desktop_speech_voice_variant(voices : Void*, index : UInt64) : UInt8*
  fun free_voices = native_desktop_speech_free_voices(voices : Void*) : Nil
end

NativeDesktop::Capabilities.register(
  NativeDesktop::Features::SpeechRecognition,
  NativeDesktop::CapabilityState::Unsupported,
  "Linux does not expose a standard system speech-recognition service"
)

module NativeDesktop::Platform
  class SpeechSynthesizer
    @connection = Pointer(Void).null
    @speaking = false

    def initialize
    end

    def voices : Array(Voice)
      pointer = LibNativeDesktopSpeechD.list_voices(connection)
      return [] of Voice if pointer.null?

      valid_list = false
      begin
        count = LibNativeDesktopSpeechD.voice_count(pointer)
        if count == UInt64::MAX
          raise Error.new("Speech Dispatcher returned an unterminated voice list", :speech_failed)
        end
        valid_list = true

        result = Array(Voice).new(count.to_i) do |index|
          native_index = index.to_u64
          name = string(LibNativeDesktopSpeechD.voice_name(pointer, native_index), "unknown")
          language = string(LibNativeDesktopSpeechD.voice_language(pointer, native_index), "und")
          variant = string(LibNativeDesktopSpeechD.voice_variant(pointer, native_index), "")
          variant = "" if variant == "none"
          id = variant.empty? ? "#{name}-#{language}" : "#{name}-#{language}-#{variant}"
          Voice.new(id, name, language, variant: variant.empty? ? nil : variant)
        end
        compact_variant_expansion(result)
      ensure
        LibNativeDesktopSpeechD.free_voices(pointer) if valid_list
      end
    end

    def speak(text : String, options : SynthesisOptions) : Nil
      stop if speaking?
      voice_name = options.voice.try(&.name)
      language = options.voice.try(&.language)
      result = LibNativeDesktopSpeechD.configure(
        connection,
        voice_name ? voice_name.to_unsafe : Pointer(UInt8).null,
        language ? language.to_unsafe : Pointer(UInt8).null,
        SynthesisTuning.signed_rate(options.rate, 100),
        SynthesisTuning.signed_pitch(options.pitch, 100),
        SynthesisTuning.dispatcher_volume(options.volume)
      )
      raise Error.new("Speech Dispatcher rejected the synthesis options", :speech_failed) if result < 0

      result = LibNativeDesktopSpeechD.say(connection, text)
      raise Error.new("Speech Dispatcher rejected the utterance", :speech_failed) if result < 0
      @speaking = LibNativeDesktopSpeechD.speaking(connection) != 0
    end

    def stop : Nil
      check(LibNativeDesktopSpeechD.stop(connection), "stop speech")
      @speaking = false
    end

    def pause : Nil
      check(LibNativeDesktopSpeechD.pause(connection), "pause speech")
    end

    def resume : Nil
      check(LibNativeDesktopSpeechD.resume(connection), "resume speech")
    end

    def speaking? : Bool
      @speaking = LibNativeDesktopSpeechD.speaking(connection) != 0
    end

    def cleanup : Nil
      unless @connection.null?
        LibNativeDesktopSpeechD.stop(@connection) if @speaking
        LibNativeDesktopSpeechD.close(@connection)
        @connection = Pointer(Void).null
        @speaking = false
      end
    end

    private def connection : Void*
      return @connection unless @connection.null?
      value = LibNativeDesktopSpeechD.open
      raise Error.new("could not connect to Speech Dispatcher", :speech_unavailable) if value.null?
      @connection = value
    end

    private def string(pointer : UInt8*, fallback : String) : String
      pointer.null? ? fallback : String.new(pointer)
    rescue
      fallback
    end

    # eSpeak-NG exposes every language crossed with every acoustic variant.
    # Keep ordinary variant lists intact, but avoid returning thousands of
    # combinations when a default voice exists for each language.
    private def compact_variant_expansion(voices : Array(Voice)) : Array(Voice)
      defaults = voices.select(&.variant.nil?)
      selected = defaults.size > 0 && voices.size > defaults.size * 4 ? defaults : voices
      selected.uniq(&.id)
    end

    private def check(result : Int32, operation : String) : Nil
      raise Error.new("could not #{operation}", :speech_failed) if result < 0
    end
  end

  # Linux deliberately has no recognizer backend: unlike synthesis through
  # Speech Dispatcher, freedesktop.org does not define a system STT service.
  class SpeechRecognizer
    def self.languages : Array(String)
      [] of String
    end

    def self.available?(language : String) : Bool
      false
    end

    def self.permission : SpeechRecognitionPermission
      SpeechRecognitionPermission::Unknown
    end

    def self.request_permission : SpeechRecognitionPermission
      SpeechRecognitionPermission::Unknown
    end

    def start(language : String, interim : Bool) : Nil
      raise Error.new("speech recognition is not available on Linux", :speech_recognition_unavailable)
    end

    def stop : Nil
    end

    def abort : Nil
    end

    def listening? : Bool
      false
    end

    def poll : RecognitionEvent?
      nil
    end

    def cleanup : Nil
    end
  end
end
