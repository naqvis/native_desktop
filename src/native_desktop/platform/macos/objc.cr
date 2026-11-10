{% if flag?(:darwin) %}
  module NativeDesktop::Platform::MacOS
    @[Link(framework: "Foundation")]
    @[Link(framework: "AppKit")]
    @[Link(ldflags: "#{__DIR__}/macos.c -framework Foundation -framework AppKit")]
    lib LibNativeObjC
      fun get_class = native_desktop_objc_get_class(name : UInt8*) : Void*
      fun selector = native_desktop_objc_selector(name : UInt8*) : Void*
      fun message_send = native_desktop_objc_message_send : Void*
      fun pool_push = native_desktop_objc_pool_push : Void*
      fun pool_pop = native_desktop_objc_pool_pop(pool : Void*) : Nil
    end

    module ObjC
      extend self
      alias NoArgs = Proc(Void*, Void*, Void*)
      alias OneArg = Proc(Void*, Void*, Void*, Void*)
      alias TwoArgs = Proc(Void*, Void*, Void*, Void*, Void*)
      alias ThreeArgs = Proc(Void*, Void*, Void*, Void*, Void*, Void*)
      alias LongNoArgs = Proc(Void*, Void*, LibC::Long)
      alias PtrNoArgs = Proc(Void*, Void*, UInt8*)
      alias PtrLength = Proc(Void*, Void*, Void*, LibC::ULong, Void*)
      alias LongArg = Proc(Void*, Void*, LibC::Long, Void*)
      @@send = Pointer(Void).null

      private def send_address : Void*
        @@send = LibNativeObjC.message_send if @@send.null?
        raise Error.new("objc_msgSend is unavailable", :platform_unavailable) if @@send.null?
        @@send
      end

      def klass(name : String) : Void*
        LibNativeObjC.get_class(name)
      end

      def msg(receiver : Void*, selector : String) : Void*
        NoArgs.new(send_address, Pointer(Void).null).call(receiver, LibNativeObjC.selector(selector))
      end

      def msg(receiver : Void*, selector : String, arg : Void*) : Void*
        OneArg.new(send_address, Pointer(Void).null).call(receiver, LibNativeObjC.selector(selector), arg)
      end

      def msg(receiver : Void*, selector : String, first : Void*, second : Void*) : Void*
        TwoArgs.new(send_address, Pointer(Void).null).call(receiver, LibNativeObjC.selector(selector), first, second)
      end

      def msg(receiver : Void*, selector : String, first : Void*, second : Void*, third : Void*) : Void*
        ThreeArgs.new(send_address, Pointer(Void).null).call(receiver, LibNativeObjC.selector(selector), first, second, third)
      end

      def long(receiver : Void*, selector : String) : Int64
        LongNoArgs.new(send_address, Pointer(Void).null).call(receiver, LibNativeObjC.selector(selector)).to_i64
      end

      def msg_long(receiver : Void*, selector : String, value : Int64) : Void*
        LongArg.new(send_address, Pointer(Void).null).call(receiver, LibNativeObjC.selector(selector), LibC::Long.new(value))
      end

      def msg_index(receiver : Void*, selector : String, value : UInt64) : Void*
        LongArg.new(send_address, Pointer(Void).null).call(receiver, LibNativeObjC.selector(selector), LibC::Long.new(value))
      end

      def pointer(receiver : Void*, selector : String) : UInt8*
        PtrNoArgs.new(send_address, Pointer(Void).null).call(receiver, LibNativeObjC.selector(selector))
      end

      def data(bytes : Bytes) : Void*
        PtrLength.new(send_address, Pointer(Void).null).call(klass("NSData"), LibNativeObjC.selector("dataWithBytes:length:"), bytes.to_unsafe.as(Void*), bytes.size.to_u64)
      end

      def string(value : String) : Void*
        msg(klass("NSString"), "stringWithUTF8String:", value.to_unsafe.as(Void*))
      end

      def to_s(value : Void*) : String?
        return nil if value.null?
        ptr = pointer(value, "UTF8String")
        ptr.null? ? nil : String.new(ptr)
      end

      def pool(&block : -> T) : T forall T
        token = LibNativeObjC.pool_push
        begin
          block.call
        ensure
          LibNativeObjC.pool_pop(token)
        end
      end
    end
  end
{% end %}
