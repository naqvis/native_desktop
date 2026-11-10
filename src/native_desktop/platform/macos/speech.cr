require "./objc_runtime"

module NativeDesktop::Platform
  @[Link(ldflags: "#{__DIR__}/speech_recognition.m -framework Speech -framework AVFoundation -framework Foundation")]
  lib LibNativeDesktopSpeechRecognition
    fun languages = native_desktop_recognition_languages : UInt8*
    fun available = native_desktop_recognition_available(language : UInt8*) : Int32
    fun permission = native_desktop_recognition_permission : Int32
    fun request_permission = native_desktop_recognition_request_permission : Int32
    fun create = native_desktop_recognition_create : Void*
    fun start = native_desktop_recognition_start(recognizer : Void*, language : UInt8*, interim : Int32, error : UInt8**) : Int32
    fun stop = native_desktop_recognition_stop(recognizer : Void*) : Nil
    fun abort = native_desktop_recognition_abort(recognizer : Void*) : Nil
    fun listening = native_desktop_recognition_listening(recognizer : Void*) : Int32
    fun poll = native_desktop_recognition_poll(recognizer : Void*, text : UInt8**, final : Int32*, confidence : Float64*) : Int32
    fun free_string = native_desktop_recognition_free_string(value : UInt8*) : Nil
    fun close = native_desktop_recognition_close(recognizer : Void*) : Nil
  end

  class SpeechSynthesizer
    @synth = Pointer(Void).null
    @base_rates = {} of String => Float32
    @base_pitches = {} of String => Float64

    def initialize
      MacOS::ObjCRuntime.with_autorelease_pool do
        MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSApplication"), "sharedApplication")
        object = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSSpeechSynthesizer"), "alloc")
        @synth = MacOS::ObjCRuntime.msg(object, "init")
        raise Error.new("could not create the macOS speech synthesizer", :speech_unavailable) if @synth.null?
      end
    end

    def voices : Array(Voice)
      MacOS::ObjCRuntime.with_autorelease_pool do
        available = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSSpeechSynthesizer"), "availableVoices")
        Array(Voice).new(MacOS::ObjCRuntime.msg_long(available, "count").to_i) do |index|
          voice = MacOS::ObjCRuntime.msg_object_at(available, "objectAtIndex:", index.to_u64)
          attributes = MacOS::ObjCRuntime.msg(MacOS::ObjCRuntime.get_class("NSSpeechSynthesizer"), "attributesForVoice:", voice)
          id = string_attribute(attributes, "VoiceIdentifier") || MacOS::ObjCRuntime.nsstring_to_s(voice) || "unknown"
          name = string_attribute(attributes, "VoiceName") || id
          language = string_attribute(attributes, "VoiceLanguage") ||
                     string_attribute(attributes, "VoiceLocaleIdentifier").try { |locale| locale.tr("_", "-") } ||
                     "und"
          Voice.new(id, name, language, variant: voice_variant(id))
        end
      end
    end

    def speak(text : String, options : SynthesisOptions) : Nil
      MacOS::ObjCRuntime.with_autorelease_pool do
        MacOS::ObjCRuntime.msg_void(@synth, "stopSpeaking") if speaking?
        if voice = options.voice
          accepted = MacOS::ObjCRuntime.msg_bool_object(@synth, "setVoice:", MacOS::ObjCRuntime.nsstring(voice.id))
          raise Error.new("macOS did not accept the requested speech voice", :speech_failed) unless accepted
        end
        voice_id = current_voice_id
        base_rate = @base_rates[voice_id] ||= MacOS::ObjCRuntime.msg_float(@synth, "rate")
        MacOS::ObjCRuntime.msg_void_float(@synth, "setRate:", (base_rate * options.rate).to_f32)
        apply_pitch(voice_id, options.pitch)
        MacOS::ObjCRuntime.msg_void_float(@synth, "setVolume:", options.volume.to_f32)
        accepted = MacOS::ObjCRuntime.msg_bool_object(@synth, "startSpeakingString:", MacOS::ObjCRuntime.nsstring(text))
        raise Error.new("the macOS speech synthesizer rejected the utterance", :speech_failed) unless accepted
      end
    end

    def stop : Nil
      MacOS::ObjCRuntime.msg_void(@synth, "stopSpeaking")
    end

    def pause : Nil
      MacOS::ObjCRuntime.msg_uint(@synth, "pauseSpeakingAtBoundary:", 0_u64)
    end

    def resume : Nil
      MacOS::ObjCRuntime.msg_void(@synth, "continueSpeaking")
    end

    def speaking? : Bool
      MacOS::ObjCRuntime.msg_long(@synth, "isSpeaking") != 0
    end

    def cleanup : Nil
      unless @synth.null?
        MacOS::ObjCRuntime.msg_void(@synth, "stopSpeaking")
        MacOS::ObjCRuntime.msg_void(@synth, "release")
        @synth = Pointer(Void).null
      end
    end

    private def string_attribute(attributes : Void*, key : String) : String?
      value = MacOS::ObjCRuntime.msg(attributes, "objectForKey:", MacOS::ObjCRuntime.nsstring(key))
      MacOS::ObjCRuntime.nsstring_to_s(value)
    end

    private def voice_variant(id : String) : String?
      return "premium" if id.includes?(".premium")
      return "enhanced" if id.includes?(".enhanced")
      return "compact" if id.includes?(".compact.")
      nil
    end

    private def current_voice_id : String
      value = MacOS::ObjCRuntime.msg(@synth, "voice")
      MacOS::ObjCRuntime.nsstring_to_s(value) || "__default__"
    end

    private def apply_pitch(voice_id : String, multiplier : Float64) : Nil
      base = @base_pitches[voice_id]?
      unless base
        error = Pointer(Void).null
        value = MacOS::ObjCRuntime.msg(
          @synth,
          "objectForProperty:error:",
          MacOS::ObjCRuntime.nsstring("pbas"),
          pointerof(error).as(Void*)
        )
        raise Error.new("could not read the macOS speech pitch", :speech_failed) unless error.null?
        raise Error.new("macOS did not return a speech pitch", :speech_failed) if value.null?
        base = MacOS::ObjCRuntime.msg_double(value, "doubleValue")
        @base_pitches[voice_id] = base
      end

      number = MacOS::ObjCRuntime.msg_float(
        MacOS::ObjCRuntime.get_class("NSNumber"),
        "numberWithDouble:",
        base * multiplier
      )
      error = Pointer(Void).null
      accepted = MacOS::ObjCRuntime.msg_bool_object_object_error(
        @synth,
        "setObject:forProperty:error:",
        number,
        MacOS::ObjCRuntime.nsstring("pbas"),
        pointerof(error)
      )
      unless accepted && error.null?
        raise Error.new("macOS did not accept the requested speech pitch", :speech_failed)
      end
    end
  end

  class SpeechRecognizer
    @recognizer = Pointer(Void).null

    def self.languages : Array(String)
      pointer = LibNativeDesktopSpeechRecognition.languages
      return [] of String if pointer.null?
      String.new(pointer).split('\n', remove_empty: true)
    ensure
      LibNativeDesktopSpeechRecognition.free_string(pointer) if pointer && !pointer.null?
    end

    def self.available?(language : String) : Bool
      LibNativeDesktopSpeechRecognition.available(language) != 0
    end

    def self.permission : SpeechRecognitionPermission
      permission(LibNativeDesktopSpeechRecognition.permission)
    end

    def self.request_permission : SpeechRecognitionPermission
      permission(LibNativeDesktopSpeechRecognition.request_permission)
    end

    private def self.permission(value : Int32) : SpeechRecognitionPermission
      case value
      when 2 then SpeechRecognitionPermission::Granted
      when 1 then SpeechRecognitionPermission::Denied
      else        SpeechRecognitionPermission::Unknown
      end
    end

    def initialize
      @recognizer = LibNativeDesktopSpeechRecognition.create
      raise Error.new("could not create the macOS speech recognizer", :speech_recognition_unavailable) if @recognizer.null?
    end

    def start(language : String, interim : Bool) : Nil
      error = Pointer(UInt8).null
      accepted = LibNativeDesktopSpeechRecognition.start(@recognizer, language, interim ? 1 : 0, pointerof(error))
      return if accepted != 0

      message = native_error(error) || "macOS rejected the speech recognition request"
      raise Error.new(message, :speech_recognition_failed)
    end

    def stop : Nil
      LibNativeDesktopSpeechRecognition.stop(@recognizer) unless @recognizer.null?
    end

    def abort : Nil
      LibNativeDesktopSpeechRecognition.abort(@recognizer) unless @recognizer.null?
    end

    def listening? : Bool
      !@recognizer.null? && LibNativeDesktopSpeechRecognition.listening(@recognizer) != 0
    end

    def poll : RecognitionEvent?
      return nil if @recognizer.null?
      text = Pointer(UInt8).null
      final = 0_i32
      confidence = -1.0
      kind = LibNativeDesktopSpeechRecognition.poll(@recognizer, pointerof(text), pointerof(final), pointerof(confidence))
      return nil if kind == 0

      message = native_error(text)
      case kind
      when 1
        RecognitionEvent.new(
          RecognitionEventKind::Result,
          message,
          final != 0,
          confidence >= 0.0 ? confidence.clamp(0.0, 1.0) : nil
        )
      when 2
        RecognitionEvent.new(RecognitionEventKind::Error, message, true, code: :speech_recognition_failed)
      else
        RecognitionEvent.new(RecognitionEventKind::Ended)
      end
    end

    def cleanup : Nil
      unless @recognizer.null?
        LibNativeDesktopSpeechRecognition.close(@recognizer)
        @recognizer = Pointer(Void).null
      end
    end

    private def native_error(pointer : UInt8*) : String?
      return nil if pointer.null?
      String.new(pointer)
    ensure
      LibNativeDesktopSpeechRecognition.free_string(pointer) unless pointer.null?
    end
  end
end
