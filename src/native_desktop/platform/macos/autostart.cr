{% if flag?(:darwin) %}
  module NativeDesktop::Platform::Autostart
    extend self

    def enable(entry : AutostartEntry) : Nil
      Dir.mkdir_p(directory)
      arguments = [entry.executable.to_s] + entry.arguments
      arguments << "--minimized" if entry.minimized
      values = arguments.map { |argument| "    <string>#{xml(argument)}</string>" }.join('\n')
      content = <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>Label</key><string>#{xml(entry.name)}</string>
        <key>ProgramArguments</key><array>
      #{values}
        </array>
        <key>RunAtLoad</key><true/>
      </dict></plist>
      XML
      File.write(path(entry.name), content)
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
      Path[ENV["NATIVE_DESKTOP_AUTOSTART_DIR"]? || ENV["WEBVIEW_AUTOSTART_DIR"]? || (Path.home / "Library" / "LaunchAgents").to_s]
    end

    private def path(name : String) : Path
      directory / "#{safe_name(name)}.plist"
    end

    private def safe_name(name : String) : String
      name.gsub(/[^a-zA-Z0-9._-]/, "_")
    end

    private def xml(value : String) : String
      value.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;").gsub('"', "&quot;").gsub('\'', "&apos;")
    end
  end
{% end %}
