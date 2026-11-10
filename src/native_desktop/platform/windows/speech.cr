require "./win32_common"
require "./string_helpers"

module NativeDesktop::Platform
  class SpeechSynthesizer
    CLSID_SPVOICE = Bytes[0x77, 0x93, 0x74, 0x96, 0x91, 0x33, 0xD2, 0x11, 0x9E, 0xE3, 0x00, 0xC0, 0x4F, 0x79, 0x73, 0x96]
    IID_ISPVOICE  = Bytes[0x74, 0xDF, 0x44, 0x6C, 0xB9, 0x72, 0x92, 0x49, 0xA1, 0xEC, 0xEF, 0x99, 0x6E, 0x04, 0x22, 0xD4]

    CLSID_SPOBJECTTOKENCATEGORY    = Bytes[0x7F, 0x18, 0x10, 0xA9, 0x7A, 0x0C, 0xAC, 0x45, 0x92, 0xCC, 0x59, 0xED, 0xAF, 0xB7, 0x7B, 0x53]
    IID_ISPARSEOBJECTTOKENCATEGORY = Bytes[0x45, 0x38, 0x3D, 0x2D, 0xAF, 0x39, 0x50, 0x48, 0xBB, 0xF9, 0x40, 0xB4, 0x97, 0x80, 0x01, 0x1D]

    CLSID_SPOBJECTTOKEN    = Bytes[0x52, 0x17, 0x41, 0xEF, 0x36, 0x37, 0xB4, 0x4C, 0x9C, 0x8C, 0x8E, 0xF4, 0xCC, 0xB5, 0x8E, 0xFE]
    IID_ISPARSEOBJECTTOKEN = Bytes[0x89, 0x65, 0x05, 0x14, 0x6C, 0xE1, 0xD2, 0x11, 0xBB, 0x90, 0x00, 0xC0, 0x4F, 0x8E, 0xE6, 0xC0]

    VOICE_CATEGORY = "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\Voices"

    IUNKNOWN_RELEASE = 2
    # These interfaces inherit the twelve ISpDataKey methods.
    ISPCATEGORY_SETID      = 15
    ISPCATEGORY_ENUMTOKENS = 18
    ISPTOKEN_SETID         = 15
    ISPENUM_NEXT           =  3
    ISPENUM_GETCOUNT       =  8
    ISPDATA_GETSTRINGVALUE =  6
    ISPDATA_OPENKEY        =  9
    ISPTOKEN_GETID         = 16
    ISPVOICE_PAUSE         = 16
    ISPVOICE_RESUME        = 17
    ISPVOICE_SETVOICE      = 18
    ISPVOICE_SPEAK         = 20
    ISPVOICE_SETRATE       = 28
    ISPVOICE_SETVOLUME     = 30
    ISPVOICE_WAITUNTILDONE = 32

    SPF_ASYNC                =       1_u32
    SPF_PURGEBEFORESPEAK     =       2_u32
    SPF_IS_XML               =       8_u32
    SPF_IS_NOT_XML           =      16_u32
    COINIT_APARTMENTTHREADED =     0x2_u32
    RPC_E_CHANGED_MODE       = -2147417850
    MAX_VOICE_COUNT          =    4096_u32

    @voice = Pointer(Void).null
    @com_initialized = false
    @speaking = false

    def initialize
      initialize_com
      voice = Pointer(Void).null
      result = Windows::LibOLE.CoCreateInstance(
        CLSID_SPVOICE.to_unsafe.as(Void*),
        Pointer(Void).null,
        Windows::LibOLE::CLSCTX_INPROC_SERVER,
        IID_ISPVOICE.to_unsafe.as(Void*),
        pointerof(voice)
      )
      check(result, "create the Windows speech synthesizer")
      raise Error.new("Windows did not return a speech synthesizer", :speech_unavailable) if voice.null?
      @voice = voice
    rescue ex
      cleanup
      raise ex
    end

    def voices : Array(Voice)
      category_path = Windows::StringHelpers.to_utf16(VOICE_CATEGORY)
      category = Pointer(Void).null
      enumerator = Pointer(Void).null
      result = Windows::LibOLE.CoCreateInstance(
        CLSID_SPOBJECTTOKENCATEGORY.to_unsafe.as(Void*),
        Pointer(Void).null,
        Windows::LibOLE::CLSCTX_INPROC_SERVER,
        IID_ISPARSEOBJECTTOKENCATEGORY.to_unsafe.as(Void*),
        pointerof(category)
      )
      check(result, "create the Windows speech voice category")
      return [] of Voice if category.null?
      begin
        check(call(category, ISPCATEGORY_SETID, category_path.to_unsafe, 0), "set the Windows speech voice category identifier")
        check(call(category, ISPCATEGORY_ENUMTOKENS, Pointer(UInt16).null, Pointer(UInt16).null, pointerof(enumerator)), "enumerate Windows speech voices")
        return [] of Voice if enumerator.null?

        count = 0_u32
        check(call(enumerator, ISPENUM_GETCOUNT, pointerof(count)), "count Windows speech voices")
        if count > MAX_VOICE_COUNT
          raise Error.new("Windows returned an invalid speech voice count (#{count})", :speech_failed)
        end
        result = [] of Voice
        count.times do |index|
          token = Pointer(Void).null
          fetched = 0_u32
          next unless call(enumerator, ISPENUM_NEXT, 1_u32, pointerof(token), pointerof(fetched)) == Windows::LibOLE::S_OK
          next if token.null?
          begin
            id = token_id(token) || "voice_#{index}"
            name = token_string(token, nil) || id
            language = locale_name(token_attribute(token, "Language")) || "und"
            result << Voice.new(id, name, language)
          ensure
            call(token, IUNKNOWN_RELEASE)
          end
        end
        result
      ensure
        call(category, IUNKNOWN_RELEASE)
        call(enumerator, IUNKNOWN_RELEASE) unless enumerator.null?
      end
    end

    def speak(text : String, options : SynthesisOptions) : Nil
      select_voice(options.voice) if options.voice
      rate = SynthesisTuning.signed_rate(options.rate, 10)
      check(call(@voice, ISPVOICE_SETRATE, rate), "set the Windows speech rate")
      check(call(@voice, ISPVOICE_SETVOLUME, (options.volume * 100.0).round.to_u16), "set the Windows speech volume")
      pitch = SynthesisTuning.signed_pitch(options.pitch, 10)
      content = pitch == 0 ? text : %(<pitch absmiddle="#{pitch}">#{SynthesisTuning.xml_escape(text)}</pitch>)
      format = pitch == 0 ? SPF_IS_NOT_XML : SPF_IS_XML
      value = Windows::StringHelpers.to_utf16(content)
      check(call(@voice, ISPVOICE_SPEAK, value.to_unsafe, SPF_ASYNC | SPF_PURGEBEFORESPEAK | format, Pointer(UInt32).null), "speak text on Windows")
      @speaking = true
    end

    def stop : Nil
      check(call(@voice, ISPVOICE_SPEAK, Pointer(UInt16).null, SPF_PURGEBEFORESPEAK, Pointer(UInt32).null), "stop Windows speech")
      @speaking = false
    end

    def pause : Nil
      check(call(@voice, ISPVOICE_PAUSE), "pause Windows speech")
    end

    def resume : Nil
      check(call(@voice, ISPVOICE_RESUME), "resume Windows speech")
    end

    def speaking? : Bool
      if @speaking
        result = call(@voice, ISPVOICE_WAITUNTILDONE, 0_u32)
        check(result, "query Windows speech state")
        @speaking = false if result == Windows::LibOLE::S_OK
      end
      @speaking
    end

    def cleanup : Nil
      unless @voice.null?
        call(@voice, ISPVOICE_SPEAK, Pointer(UInt16).null, SPF_PURGEBEFORESPEAK, Pointer(UInt32).null) rescue nil
        call(@voice, IUNKNOWN_RELEASE)
        @voice = Pointer(Void).null
      end
      if @com_initialized
        Windows::LibOLE.CoUninitialize
        @com_initialized = false
      end
      @speaking = false
    end

    private def initialize_com : Nil
      result = Windows::LibOLE.CoInitializeEx(Pointer(Void).null, COINIT_APARTMENTTHREADED)
      return if result == RPC_E_CHANGED_MODE
      check(result, "initialize COM for speech")
      @com_initialized = true
    end

    private def select_voice(voice : Voice?) : Nil
      return unless voice
      id = Windows::StringHelpers.to_utf16(voice.id)
      token = Pointer(Void).null
      result = Windows::LibOLE.CoCreateInstance(
        CLSID_SPOBJECTTOKEN.to_unsafe.as(Void*),
        Pointer(Void).null,
        Windows::LibOLE::CLSCTX_INPROC_SERVER,
        IID_ISPARSEOBJECTTOKEN.to_unsafe.as(Void*),
        pointerof(token)
      )
      check(result, "create Windows speech voice token")
      raise Error.new("Windows did not return the requested speech voice", :speech_failed) if token.null?
      begin
        check(call(token, ISPTOKEN_SETID, Pointer(UInt16).null, id.to_unsafe, 0), "set the Windows speech voice token identifier")
        check(call(@voice, ISPVOICE_SETVOICE, token), "select the Windows speech voice")
      ensure
        call(token, IUNKNOWN_RELEASE)
      end
    end

    private def token_id(token : Void*) : String?
      pointer = Pointer(UInt16).null
      return nil unless call(token, ISPTOKEN_GETID, pointerof(pointer)) == Windows::LibOLE::S_OK
      return nil if pointer.null?
      begin
        Windows::StringHelpers.from_utf16(pointer)
      ensure
        Windows::LibOLE.CoTaskMemFree(pointer.as(Void*))
      end
    end

    private def token_string(token : Void*, key : String?) : String?
      key_value = key.try { |value| Windows::StringHelpers.to_utf16(value) }
      pointer = Pointer(UInt16).null
      key_pointer = key_value ? key_value.to_unsafe : Pointer(UInt16).null
      return nil unless call(token, ISPDATA_GETSTRINGVALUE, key_pointer, pointerof(pointer)) == Windows::LibOLE::S_OK
      return nil if pointer.null?
      begin
        Windows::StringHelpers.from_utf16(pointer)
      ensure
        Windows::LibOLE.CoTaskMemFree(pointer.as(Void*))
      end
    end

    private def token_attribute(token : Void*, name : String) : String?
      attributes_name = Windows::StringHelpers.to_utf16("Attributes")
      attributes = Pointer(Void).null
      return nil unless call(token, ISPDATA_OPENKEY, attributes_name.to_unsafe, pointerof(attributes)) == Windows::LibOLE::S_OK
      return nil if attributes.null?
      begin
        token_string(attributes, name)
      ensure
        call(attributes, IUNKNOWN_RELEASE)
      end
    end

    private def locale_name(language : String?) : String?
      return nil unless language
      lcid = language.split(';', 2).first.to_u32?(16)
      return nil unless lcid

      buffer = Slice(UInt16).new(85, 0_u16)
      return nil if Windows::LibKernel32.LCIDToLocaleName(lcid, buffer.to_unsafe, buffer.size, 0_u32) == 0
      Windows::StringHelpers.from_utf16(buffer.to_unsafe)
    end

    private def function(object : Void*, index : Int32) : Void*
      object.as(Pointer(Void*)).value.as(Pointer(Void*))[index]
    end

    private def call(object : Void*, index : Int32) : Int32
      Proc(Void*, Int32).new(function(object, index), Pointer(Void).null).call(object)
    end

    private def call(object : Void*, index : Int32, a) : Int32
      Proc(Void*, typeof(a), Int32).new(function(object, index), Pointer(Void).null).call(object, a)
    end

    private def call(object : Void*, index : Int32, a, b) : Int32
      Proc(Void*, typeof(a), typeof(b), Int32).new(function(object, index), Pointer(Void).null).call(object, a, b)
    end

    private def call(object : Void*, index : Int32, a, b, c) : Int32
      Proc(Void*, typeof(a), typeof(b), typeof(c), Int32).new(function(object, index), Pointer(Void).null).call(object, a, b, c)
    end

    private def check(result : Int32, operation : String) : Nil
      raise Error.new("could not #{operation} (HRESULT 0x#{result.to_u32!.to_s(16)})", :speech_failed) if result < 0
    end
  end

  class SpeechRecognizer
    CLSID_SPINPROCRECOGNIZER = Bytes[0x6B, 0x9B, 0xB8, 0x41, 0x99, 0x93, 0xD2, 0x11, 0x96, 0x23, 0x00, 0xC0, 0x4F, 0x8E, 0xE6, 0x28]
    IID_ISPRECOGNIZER        = Bytes[0x41, 0xF2, 0xB5, 0xC2, 0xA0, 0xDA, 0x07, 0x45, 0x9E, 0x16, 0x5A, 0x1E, 0xAA, 0x2B, 0x7A, 0x5C]

    CLSID_SPOBJECTTOKENCATEGORY    = SpeechSynthesizer::CLSID_SPOBJECTTOKENCATEGORY
    IID_ISPARSEOBJECTTOKENCATEGORY = SpeechSynthesizer::IID_ISPARSEOBJECTTOKENCATEGORY

    RECOGNIZER_CATEGORY  = "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\Recognizers"
    AUDIO_INPUT_CATEGORY = "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\AudioInput"

    IUNKNOWN_RELEASE                   =  2
    ISPDATA_GETSTRINGVALUE             =  6
    ISPDATA_OPENKEY                    =  9
    ISPCATEGORY_SETID                  = 15
    ISPCATEGORY_ENUMTOKENS             = 18
    ISPENUM_NEXT                       =  3
    ISPENUM_GETCOUNT                   =  8
    ISPRECOGNIZER_SETRECOGNIZER        =  7
    ISPRECOGNIZER_SETINPUT             =  9
    ISPRECOGNIZER_CREATERECOCONTEXT    = 12
    ISPRECOGNIZER_SETRECOSTATE         = 17
    ISPRECOCONTEXT_SETNOTIFYWIN32EVENT =  7
    ISPRECOCONTEXT_SETINTEREST         = 10
    ISPRECOCONTEXT_GETEVENTS           = 11
    ISPRECOCONTEXT_CREATEGRAMMAR       = 14
    ISPRECOGRAMMAR_LOADDICTATION       = 20
    ISPRECOGRAMMAR_SETDICTATIONSTATE   = 22
    ISPRECOPHRASE_GETTEXT              =  5

    SPEI_END_SR_STREAM       = 34_u16
    SPEI_RECOGNITION         = 38_u16
    SPEI_HYPOTHESIS          = 39_u16
    SPFEI_FLAGCHECK          = (1_u64 << 30) | (1_u64 << 33)
    SPET_LPARAM_IS_OBJECT    =       2_u16
    SPLO_STATIC              =       0_u32
    SPRS_INACTIVE            =       0_i32
    SPRS_ACTIVE              =       1_i32
    SPRST_ACTIVE             =       1_i32
    COINIT_APARTMENTTHREADED =     0x2_u32
    RPC_E_CHANGED_MODE       = -2147417850
    MAX_RECOGNIZER_COUNT     =    4096_u32

    @[Extern]
    struct SpEvent
      getter event_id : UInt16
      getter param_type : UInt16
      getter stream_number : UInt32
      getter audio_stream_offset : UInt64
      getter w_param : UInt64
      getter l_param : Int64

      def initialize
        @event_id = 0_u16
        @param_type = 0_u16
        @stream_number = 0_u32
        @audio_stream_offset = 0_u64
        @w_param = 0_u64
        @l_param = 0_i64
      end
    end

    @recognizer = Pointer(Void).null
    @context = Pointer(Void).null
    @grammar = Pointer(Void).null
    @com_initialized = false
    @listening = false
    @ended_pending = false

    def self.languages : Array(String)
      recognizer = new
      recognizer.recognition_languages
    ensure
      recognizer.try(&.cleanup)
    end

    def self.available?(language : String) : Bool
      recognizer = new
      recognizer.language_available?(language)
    ensure
      recognizer.try(&.cleanup)
    end

    def self.permission : SpeechRecognitionPermission
      SpeechRecognitionPermission::Granted
    end

    def self.request_permission : SpeechRecognitionPermission
      SpeechRecognitionPermission::Granted
    end

    def initialize
      result = Windows::LibOLE.CoInitializeEx(Pointer(Void).null, COINIT_APARTMENTTHREADED)
      unless result == RPC_E_CHANGED_MODE
        check(result, "initialize COM for speech recognition")
        @com_initialized = true
      end
    end

    def start(language : String, interim : Bool) : Nil
      cleanup_session
      token = recognizer_token(language)
      raise Error.new("no Windows speech recognizer supports #{language}", :speech_recognition_unavailable) if token.null?

      begin
        check(Windows::LibOLE.CoCreateInstance(
          CLSID_SPINPROCRECOGNIZER.to_unsafe.as(Void*),
          Pointer(Void).null,
          Windows::LibOLE::CLSCTX_INPROC_SERVER,
          IID_ISPRECOGNIZER.to_unsafe.as(Void*),
          pointerof(@recognizer)
        ), "create the Windows speech recognizer")
        raise Error.new("Windows did not return a speech recognizer", :speech_recognition_unavailable) if @recognizer.null?
        check(call(@recognizer, ISPRECOGNIZER_SETRECOGNIZER, token), "select the Windows speech recognizer language")
      ensure
        call(token, IUNKNOWN_RELEASE)
      end

      audio = first_token(AUDIO_INPUT_CATEGORY, nil)
      raise Error.new("no Windows microphone input is available", :speech_recognition_unavailable) if audio.null?
      begin
        check(call(@recognizer, ISPRECOGNIZER_SETINPUT, audio, 1), "select the Windows microphone input")
      ensure
        call(audio, IUNKNOWN_RELEASE)
      end

      check(call(@recognizer, ISPRECOGNIZER_CREATERECOCONTEXT, pointerof(@context)), "create the Windows speech recognition context")
      interests = event_interest(SPEI_RECOGNITION) | event_interest(SPEI_END_SR_STREAM)
      interests |= event_interest(SPEI_HYPOTHESIS) if interim
      check(call(@context, ISPRECOCONTEXT_SETINTEREST, interests, interests), "configure Windows speech recognition events")
      check(call(@context, ISPRECOCONTEXT_SETNOTIFYWIN32EVENT), "configure Windows speech recognition notification")
      check(call(@context, ISPRECOCONTEXT_CREATEGRAMMAR, 1_u64, pointerof(@grammar)), "create the Windows dictation grammar")
      check(call(@grammar, ISPRECOGRAMMAR_LOADDICTATION, Pointer(UInt16).null, SPLO_STATIC), "load Windows dictation")
      check(call(@recognizer, ISPRECOGNIZER_SETRECOSTATE, SPRST_ACTIVE), "activate the Windows speech recognizer")
      check(call(@grammar, ISPRECOGRAMMAR_SETDICTATIONSTATE, SPRS_ACTIVE), "start Windows dictation")
      @ended_pending = false
      @listening = true
    rescue ex
      cleanup_session
      raise ex
    end

    def stop : Nil
      finish_session if @listening
    end

    def abort : Nil
      cleanup_session
    end

    def listening? : Bool
      @listening
    end

    def poll : RecognitionEvent?
      unless @context.null?
        event = uninitialized SpEvent
        fetched = 0_u32
        result = call(@context, ISPRECOCONTEXT_GETEVENTS, 1_u32, pointerof(event), pointerof(fetched))
        check(result, "read Windows speech recognition events")
        if fetched == 1
          begin
            case event.event_id
            when SPEI_RECOGNITION, SPEI_HYPOTHESIS
              transcript = result_text(event.l_param)
              unless transcript.empty?
                return RecognitionEvent.new(
                  RecognitionEventKind::Result,
                  transcript,
                  event.event_id == SPEI_RECOGNITION
                )
              end
            when SPEI_END_SR_STREAM
              finish_session
            end
          ensure
            if event.param_type == SPET_LPARAM_IS_OBJECT && event.l_param != 0
              call(Pointer(Void).new(event.l_param.to_u64), IUNKNOWN_RELEASE)
            end
          end
        end
      end

      if @ended_pending
        @ended_pending = false
        cleanup_session
        return RecognitionEvent.new(RecognitionEventKind::Ended)
      end
      nil
    end

    def cleanup : Nil
      cleanup_session
      if @com_initialized
        Windows::LibOLE.CoUninitialize
        @com_initialized = false
      end
    end

    protected def language_available?(language : String) : Bool
      token = recognizer_token(language)
      return false if token.null?
      call(token, IUNKNOWN_RELEASE)
      true
    end

    protected def recognition_languages : Array(String)
      category = Pointer(Void).null
      enumerator = Pointer(Void).null
      check(Windows::LibOLE.CoCreateInstance(
        CLSID_SPOBJECTTOKENCATEGORY.to_unsafe.as(Void*),
        Pointer(Void).null,
        Windows::LibOLE::CLSCTX_INPROC_SERVER,
        IID_ISPARSEOBJECTTOKENCATEGORY.to_unsafe.as(Void*),
        pointerof(category)
      ), "create the Windows speech recognizer category")
      return [] of String if category.null?

      begin
        category_value = Windows::StringHelpers.to_utf16(RECOGNIZER_CATEGORY)
        check(call(category, ISPCATEGORY_SETID, category_value.to_unsafe, 0), "open the Windows speech recognizer category")
        check(call(category, ISPCATEGORY_ENUMTOKENS, Pointer(UInt16).null, Pointer(UInt16).null, pointerof(enumerator)), "enumerate Windows speech recognizers")
        return [] of String if enumerator.null?

        count = 0_u32
        check(call(enumerator, ISPENUM_GETCOUNT, pointerof(count)), "count Windows speech recognizers")
        if count > MAX_RECOGNIZER_COUNT
          raise Error.new("Windows returned an invalid speech recognizer count (#{count})", :speech_recognition_failed)
        end

        result = [] of String
        count.times do
          token = Pointer(Void).null
          fetched = 0_u32
          next unless call(enumerator, ISPENUM_NEXT, 1_u32, pointerof(token), pointerof(fetched)) == Windows::LibOLE::S_OK
          next if token.null?
          begin
            if language = locale_name(token_attribute(token, "Language"))
              result << language
            end
          ensure
            call(token, IUNKNOWN_RELEASE)
          end
        end
        result.uniq.sort!
      ensure
        call(enumerator, IUNKNOWN_RELEASE) unless enumerator.null?
        call(category, IUNKNOWN_RELEASE)
      end
    end

    private def finish_session : Nil
      call(@grammar, ISPRECOGRAMMAR_SETDICTATIONSTATE, SPRS_INACTIVE) unless @grammar.null?
      @listening = false
      @ended_pending = true
    end

    private def cleanup_session : Nil
      call(@grammar, ISPRECOGRAMMAR_SETDICTATIONSTATE, SPRS_INACTIVE) unless @grammar.null?
      call(@grammar, IUNKNOWN_RELEASE) unless @grammar.null?
      call(@context, IUNKNOWN_RELEASE) unless @context.null?
      call(@recognizer, IUNKNOWN_RELEASE) unless @recognizer.null?
      @grammar = Pointer(Void).null
      @context = Pointer(Void).null
      @recognizer = Pointer(Void).null
      @listening = false
      @ended_pending = false
    end

    private def recognizer_token(language : String) : Void*
      locale = Windows::StringHelpers.to_utf16(language)
      lcid = Windows::LibKernel32.LocaleNameToLCID(locale.to_unsafe, 0_u32)
      return Pointer(Void).null if lcid == 0
      first_token(RECOGNIZER_CATEGORY, "Language=#{lcid.to_s(16)}")
    end

    private def token_string(token : Void*, key : String?) : String?
      key_value = key.try { |value| Windows::StringHelpers.to_utf16(value) }
      pointer = Pointer(UInt16).null
      key_pointer = key_value ? key_value.to_unsafe : Pointer(UInt16).null
      return nil unless call(token, ISPDATA_GETSTRINGVALUE, key_pointer, pointerof(pointer)) == Windows::LibOLE::S_OK
      return nil if pointer.null?
      begin
        Windows::StringHelpers.from_utf16(pointer)
      ensure
        Windows::LibOLE.CoTaskMemFree(pointer.as(Void*))
      end
    end

    private def token_attribute(token : Void*, name : String) : String?
      attributes_name = Windows::StringHelpers.to_utf16("Attributes")
      attributes = Pointer(Void).null
      return nil unless call(token, ISPDATA_OPENKEY, attributes_name.to_unsafe, pointerof(attributes)) == Windows::LibOLE::S_OK
      return nil if attributes.null?
      begin
        token_string(attributes, name)
      ensure
        call(attributes, IUNKNOWN_RELEASE)
      end
    end

    private def locale_name(language : String?) : String?
      return nil unless language
      lcid = language.split(';', 2).first.to_u32?(16)
      return nil unless lcid

      buffer = Slice(UInt16).new(85, 0_u16)
      return nil if Windows::LibKernel32.LCIDToLocaleName(lcid, buffer.to_unsafe, buffer.size, 0_u32) == 0
      Windows::StringHelpers.from_utf16(buffer.to_unsafe)
    end

    private def first_token(category_id : String, attributes : String?) : Void*
      category = Pointer(Void).null
      enumerator = Pointer(Void).null
      check(Windows::LibOLE.CoCreateInstance(
        CLSID_SPOBJECTTOKENCATEGORY.to_unsafe.as(Void*),
        Pointer(Void).null,
        Windows::LibOLE::CLSCTX_INPROC_SERVER,
        IID_ISPARSEOBJECTTOKENCATEGORY.to_unsafe.as(Void*),
        pointerof(category)
      ), "create a Windows speech token category")
      return Pointer(Void).null if category.null?

      begin
        category_value = Windows::StringHelpers.to_utf16(category_id)
        check(call(category, ISPCATEGORY_SETID, category_value.to_unsafe, 0), "open a Windows speech token category")
        attribute_value = attributes.try { |value| Windows::StringHelpers.to_utf16(value) }
        attribute_pointer = attribute_value ? attribute_value.to_unsafe : Pointer(UInt16).null
        check(call(category, ISPCATEGORY_ENUMTOKENS, attribute_pointer, Pointer(UInt16).null, pointerof(enumerator)), "enumerate Windows speech tokens")
        return Pointer(Void).null if enumerator.null?

        token = Pointer(Void).null
        fetched = 0_u32
        return Pointer(Void).null unless call(enumerator, ISPENUM_NEXT, 1_u32, pointerof(token), pointerof(fetched)) == Windows::LibOLE::S_OK
        fetched == 1 ? token : Pointer(Void).null
      ensure
        call(enumerator, IUNKNOWN_RELEASE) unless enumerator.null?
        call(category, IUNKNOWN_RELEASE)
      end
    end

    private def result_text(value : Int64) : String
      return "" if value == 0
      result = Pointer(Void).new(value.to_u64)
      text = Pointer(UInt16).null
      check(call(result, ISPRECOPHRASE_GETTEXT, 0_u32, UInt32::MAX, 1, pointerof(text), Pointer(UInt8).null), "read the Windows speech transcript")
      return "" if text.null?
      Windows::StringHelpers.from_utf16(text)
    ensure
      Windows::LibOLE.CoTaskMemFree(text.as(Void*)) if text && !text.null?
    end

    private def event_interest(event_id : UInt16) : UInt64
      (1_u64 << event_id) | SPFEI_FLAGCHECK
    end

    private def function(object : Void*, index : Int32) : Void*
      object.as(Pointer(Void*)).value.as(Pointer(Void*))[index]
    end

    private def call(object : Void*, index : Int32) : Int32
      Proc(Void*, Int32).new(function(object, index), Pointer(Void).null).call(object)
    end

    private def call(object : Void*, index : Int32, a) : Int32
      Proc(Void*, typeof(a), Int32).new(function(object, index), Pointer(Void).null).call(object, a)
    end

    private def call(object : Void*, index : Int32, a, b) : Int32
      Proc(Void*, typeof(a), typeof(b), Int32).new(function(object, index), Pointer(Void).null).call(object, a, b)
    end

    private def call(object : Void*, index : Int32, a, b, c) : Int32
      Proc(Void*, typeof(a), typeof(b), typeof(c), Int32).new(function(object, index), Pointer(Void).null).call(object, a, b, c)
    end

    private def call(object : Void*, index : Int32, a, b, c, d) : Int32
      Proc(Void*, typeof(a), typeof(b), typeof(c), typeof(d), Int32).new(function(object, index), Pointer(Void).null).call(object, a, b, c, d)
    end

    private def call(object : Void*, index : Int32, a, b, c, d, e) : Int32
      Proc(Void*, typeof(a), typeof(b), typeof(c), typeof(d), typeof(e), Int32).new(function(object, index), Pointer(Void).null).call(object, a, b, c, d, e)
    end

    private def check(result : Int32, operation : String) : Nil
      raise Error.new("could not #{operation} (HRESULT 0x#{result.to_u32!.to_s(16)})", :speech_recognition_failed) if result < 0
    end
  end
end
