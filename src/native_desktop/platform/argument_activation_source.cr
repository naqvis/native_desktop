module NativeDesktop::Platform
  # Linux desktop entries and Windows shell registrations deliver URL/file
  # activations as process arguments.
  class ArgumentActivationSource < NativeDesktop::ActivationSource
    URI_PATTERN = /\A[a-zA-Z][a-zA-Z0-9+.-]*:/

    def initialize(@arguments : Enumerable(String) = ARGV)
    end

    def start(&emit : NativeDesktop::Activation ->) : Nil
      files = [] of String
      @arguments.each do |argument|
        if URI_PATTERN.matches?(argument)
          emit.call(NativeDesktop::Activation.url(argument))
        elsif File.exists?(argument)
          files << Path[argument].expand.to_s
        end
      end
      emit.call(NativeDesktop::Activation.files(files)) unless files.empty?
    end
  end
end

NativeDesktop::Activations.install(NativeDesktop::Platform::ArgumentActivationSource.new)
