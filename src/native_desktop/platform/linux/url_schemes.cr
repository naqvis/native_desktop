{% if flag?(:linux) %}
  module NativeDesktop::Platform::URLSchemes
    extend self
    APPLICATIONS_DIR = Path.home / ".local" / "share" / "applications"

    @[Link("gio-2.0")]
    lib LibGIOURLSchemes
      fun g_desktop_app_info_new(id : UInt8*) : Void*
      fun g_app_info_set_as_default_for_type(info : Void*, content_type : UInt8*, error : Void**) : Int32
      fun g_object_unref(object : Void*) : Nil
    end

    def register(scheme : String, name : String, executable : Path) : Nil
      Dir.mkdir_p(APPLICATIONS_DIR)
      file = desktop_file(scheme)
      File.write(file, desktop_entry(scheme, name, executable))

      info = LibGIOURLSchemes.g_desktop_app_info_new(file.basename.to_s)
      raise Error.new("GIO could not load #{file.basename}", :url_scheme_registration_failed) if info.null?
      begin
        result = LibGIOURLSchemes.g_app_info_set_as_default_for_type(info, "x-scheme-handler/#{scheme}", nil)
        raise Error.new("GIO could not register URL scheme #{scheme.inspect}", :url_scheme_registration_failed) if result == 0
      ensure
        LibGIOURLSchemes.g_object_unref(info)
      end
    rescue ex : Error
      raise ex
    rescue ex
      raise Error.new("failed to register URL scheme #{scheme.inspect}: #{ex.message}", :url_scheme_registration_failed)
    end

    def unregister(scheme : String) : Nil
      file = desktop_file(scheme)
      File.delete(file) if File.exists?(file)
    rescue ex
      raise Error.new("failed to unregister URL scheme #{scheme.inspect}: #{ex.message}", :url_scheme_registration_failed)
    end

    private def desktop_file(scheme : String) : Path
      APPLICATIONS_DIR / "native-desktop-#{scheme}-handler.desktop"
    end

    private def desktop_entry(scheme : String, name : String, executable : Path) : String
      escaped_exec = executable.to_s.gsub('\\', "\\\\").gsub('"', "\\\"")
      escaped_name = name.gsub('\n', ' ').gsub('\r', ' ')
      <<-DESKTOP
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=#{escaped_name}
      Exec="#{escaped_exec}" %u
      MimeType=x-scheme-handler/#{scheme};
      NoDisplay=true
      StartupNotify=false
      DESKTOP
    end
  end
{% end %}
