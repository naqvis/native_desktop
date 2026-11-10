module NativeDesktop
  class Error < Exception
    getter code : Symbol

    def initialize(message : String, @code : Symbol = :native_error, cause : Exception? = nil)
      super(message, cause: cause)
    end
  end

  class RuntimeError < Error
  end
end
