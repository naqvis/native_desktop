{% if flag?(:darwin) %}
  require "./platform/macos/autostart"
{% elsif flag?(:linux) %}
  require "./platform/linux/autostart"
{% elsif flag?(:windows) %}
  require "./platform/windows/autostart"
{% end %}

module NativeDesktop
  # An application login entry and its launch arguments.
  record AutostartEntry,
    name : String,
    executable : Path,
    arguments : Array(String) = [] of String,
    minimized : Bool = false,
    delay : Time::Span = 0.seconds

  # Manages per-user login autostart entries.
  module Autostart
    extend self

    def enable(entry : AutostartEntry) : Nil
      validate(entry)
      Platform::Autostart.enable(entry)
    end

    def disable(name : String) : Nil
      validate_name(name)
      Platform::Autostart.disable(name)
    end

    def enabled?(name : String) : Bool
      validate_name(name)
      Platform::Autostart.enabled?(name)
    end

    private def validate(entry : AutostartEntry) : Nil
      validate_name(entry.name)
      raise ArgumentError.new("executable must be an absolute path") unless entry.executable.absolute?
      raise ArgumentError.new("delay cannot be negative") if entry.delay < 0.seconds
      raise ArgumentError.new("arguments cannot contain NUL bytes") if entry.arguments.any?(&.includes?('\0'))
    end

    private def validate_name(name : String) : Nil
      raise ArgumentError.new("application name cannot be empty") if name.strip.empty?
      raise ArgumentError.new("application name cannot contain NUL bytes") if name.includes?('\0')
    end
  end
end
