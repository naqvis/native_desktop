{% if flag?(:linux) %}
  module NativeDesktop::Platform::Autostart
    extend self

    def enable(entry : AutostartEntry) : Nil
      Dir.mkdir_p(directory)
      arguments = entry.arguments.dup
      arguments << "--minimized" if entry.minimized
      command = ([quote(entry.executable.to_s)] + arguments.map { |argument| quote(argument) }).join(' ')
      lines = [
        "[Desktop Entry]",
        "Version=1.0",
        "Type=Application",
        "Name=#{entry.name.gsub('\n', ' ').gsub('\r', ' ')}",
        "Exec=#{command}",
        "X-GNOME-Autostart-enabled=true",
        "NoDisplay=false",
        "Hidden=false",
        "Comment=Autostart entry for #{entry.name.gsub('\n', ' ').gsub('\r', ' ')}",
      ]
      lines << "X-GNOME-Autostart-Delay=#{entry.delay.total_seconds.to_i}" if entry.delay > 0.seconds
      File.write(path(entry.name), lines.join('\n') + "\n")
    rescue ex
      raise Error.new("failed to enable autostart for #{entry.name.inspect}: #{ex.message}", :autostart_failed)
    end

    def disable(name : String) : Nil
      file = path(name)
      File.delete(file) if File.exists?(file)
    rescue ex
      raise Error.new("failed to disable autostart for #{name.inspect}: #{ex.message}", :autostart_failed)
    end

    def enabled?(name : String) : Bool
      File.exists?(path(name))
    end

    private def directory : Path
      Path[ENV["NATIVE_DESKTOP_AUTOSTART_DIR"]? || ENV["WEBVIEW_AUTOSTART_DIR"]? || (Path.home / ".config" / "autostart").to_s]
    end

    private def path(name : String) : Path
      directory / "#{name.gsub(/[^a-zA-Z0-9._-]/, "_").downcase}.desktop"
    end

    private def quote(value : String) : String
      %("#{value.gsub('\\', "\\\\").gsub('"', "\\\"")}")
    end
  end
{% end %}
