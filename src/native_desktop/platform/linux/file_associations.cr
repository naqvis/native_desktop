{% if flag?(:linux) %}
  module NativeDesktop::Platform::FileAssociations
    extend self

    @[Link("gio-2.0")]
    lib LibGIOFileAssocs
      fun desktop_app_info_new = g_desktop_app_info_new_from_filename(filename : UInt8*) : Void*
      fun add_supports_type = g_app_info_add_supports_type(info : Void*, content_type : UInt8*, error : Void**) : Int32
      fun remove_supports_type = g_app_info_remove_supports_type(info : Void*, content_type : UInt8*, error : Void**) : Int32
      fun object_unref = g_object_unref(object : Void*) : Nil
    end

    def register(association : NativeDesktop::FileAssociation) : Nil
      Dir.mkdir_p(applications_dir)
      file = desktop_file(association)
      previous = File.read(file) if File.exists?(file)
      File.write(file, desktop_entry(association))

      info = LibGIOFileAssocs.desktop_app_info_new(file.to_s)
      raise NativeDesktop::Error.new("GIO could not load #{file.basename}", :file_association_failed) if info.null?
      begin
        result = LibGIOFileAssocs.add_supports_type(info, association.mime_type, nil)
        raise NativeDesktop::Error.new("GIO could not register file type #{association.extension.inspect}", :file_association_failed) if result == 0
      ensure
        LibGIOFileAssocs.object_unref(info)
      end
    rescue ex : NativeDesktop::Error
      if file
        previous ? File.write(file, previous) : File.delete?(file)
      end
      raise ex
    rescue ex
      if file
        previous ? File.write(file, previous) : File.delete?(file)
      end
      raise NativeDesktop::Error.new("failed to register file type #{association.extension.inspect}: #{ex.message}", :file_association_failed)
    end

    def unregister(association : NativeDesktop::FileAssociation) : Nil
      file = desktop_file(association)
      return unless File.exists?(file)

      info = LibGIOFileAssocs.desktop_app_info_new(file.to_s)
      unless info.null?
        begin
          result = LibGIOFileAssocs.remove_supports_type(info, association.mime_type, nil)
          raise NativeDesktop::Error.new("GIO could not unregister file type #{association.extension.inspect}", :file_association_failed) if result == 0
        ensure
          LibGIOFileAssocs.object_unref(info)
        end
      end
      File.delete(file)
    rescue ex : NativeDesktop::Error
      raise ex
    rescue ex
      raise NativeDesktop::Error.new("failed to unregister file type #{association.extension.inspect}: #{ex.message}", :file_association_failed)
    end

    # :nodoc:
    def desktop_file(association : NativeDesktop::FileAssociation) : Path
      applications_dir / "#{association.resource_key}.desktop"
    end

    # :nodoc:
    def desktop_entry(association : NativeDesktop::FileAssociation) : String
      escaped_exec = exec_argument(association.executable.to_s)
      escaped_name = desktop_string(association.application_name)
      escaped_desc = desktop_string(association.description || association.type_name)
      <<-DESKTOP
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=#{escaped_name}
      Comment=#{escaped_desc}
      Exec="#{escaped_exec}" %f
      MimeType=#{association.mime_type};
      NoDisplay=true
      StartupNotify=false
      DESKTOP
    end

    private def desktop_string(value : String) : String
      value.gsub('\\', "\\\\")
    end

    private def applications_dir : Path
      if value = ENV["XDG_DATA_HOME"]?
        path = Path[value]
        return path / "applications" if path.absolute?
      end
      Path.home / ".local" / "share" / "applications"
    end

    private def exec_argument(value : String) : String
      value
        .gsub('\\', "\\\\\\\\")
        .gsub('"', "\\\"")
        .gsub('`', "\\`")
        .gsub('$', "\\$")
        .gsub('%', "%%")
    end
  end
{% end %}
