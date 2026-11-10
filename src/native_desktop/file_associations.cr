{% if flag?(:darwin) %}
  require "./platform/macos/file_associations"
{% elsif flag?(:linux) %}
  require "./platform/linux/file_associations"
{% elsif flag?(:windows) %}
  require "./platform/windows/file_associations"
{% end %}

module NativeDesktop
  FILE_ASSOCIATION_EXTENSION_PATTERN   = /\A\.[a-z0-9]+(?:\.[a-z0-9]+)*\z/
  FILE_ASSOCIATION_APPLICATION_PATTERN = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+\z/
  FILE_ASSOCIATION_MIME_PATTERN        = /\A[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*\z/

  # Describes one file type handled by an application.
  struct FileAssociation
    getter application_id : String
    getter application_name : String
    getter extension : String
    getter type_name : String
    getter mime_type : String
    getter executable : Path
    getter description : String?

    def initialize(
      *,
      application_id : String,
      application_name : String,
      extension : String,
      type_name : String,
      mime_type : String,
      executable : Path,
      description : String? = nil,
    )
      @application_id = application_id.strip.downcase
      @application_name = validate_text(application_name, "application name")
      @extension = normalize_extension(extension)
      @type_name = validate_text(type_name, "file type name")
      @mime_type = mime_type.strip.downcase
      @executable = executable
      @description = description.try { |value| validate_text(value, "description") }

      unless @application_id.matches?(FILE_ASSOCIATION_APPLICATION_PATTERN)
        raise ArgumentError.new("invalid application ID #{application_id.inspect}")
      end
      raise ArgumentError.new("application ID is too long") if @application_id.bytesize > 180
      unless @extension.matches?(FILE_ASSOCIATION_EXTENSION_PATTERN)
        raise ArgumentError.new("invalid file extension #{extension.inspect}")
      end
      raise ArgumentError.new("file extension is too long") if @extension.bytesize > 32
      unless @mime_type.matches?(FILE_ASSOCIATION_MIME_PATTERN)
        raise ArgumentError.new("invalid MIME type #{mime_type.inspect}")
      end
      raise ArgumentError.new("MIME type is too long") if @mime_type.bytesize > 127
      raise ArgumentError.new("executable must be an absolute path") unless @executable.absolute?
      if @executable.to_s.each_char.any? { |character| character.ord < 0x20 || character.ord == 0x7f }
        raise ArgumentError.new("executable path contains a control character")
      end
    end

    # :nodoc:
    def resource_key : String
      "#{application_id}-#{extension.lstrip('.').gsub('.', '-')}"
    end

    private def normalize_extension(extension : String) : String
      value = extension.strip.downcase
      value.starts_with?('.') ? value : ".#{value}"
    end

    private def validate_text(value : String, label : String) : String
      normalized = value.strip
      raise ArgumentError.new("#{label} cannot be empty") if normalized.empty?
      if normalized.each_char.any? { |character| character.ord < 0x20 || character.ord == 0x7f }
        raise ArgumentError.new("#{label} contains a control character")
      end
      normalized
    end
  end

  # Registers file handlers for the current user without changing their default
  # application for the file type.
  module FileAssociations
    extend self

    @@lock = Mutex.new

    def register(association : FileAssociation) : Nil
      @@lock.synchronize { Platform::FileAssociations.register(association) }
    end

    # Removes only the registration owned by `association.application_id`.
    def unregister(association : FileAssociation) : Nil
      @@lock.synchronize { Platform::FileAssociations.unregister(association) }
    end
  end
end
