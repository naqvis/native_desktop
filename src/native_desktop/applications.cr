{% if flag?(:darwin) %}
  require "./platform/macos/applications"
{% elsif flag?(:linux) %}
  require "./platform/linux/applications"
{% elsif flag?(:windows) %}
  require "./platform/windows/applications"
{% end %}

module NativeDesktop
  # Queries desktop application state exposed by the operating system.
  module Applications
    extend self

    # Returns the foreground application's display name, or `nil` when the
    # platform cannot determine it.
    def foreground_name : String?
      Platform::Applications.foreground_name
    end

    # Opens a URL or filesystem path using its default handler. When
    # *application* is supplied, that application is requested explicitly.
    def open(target : String, application : String? = nil) : Nil
      raise ArgumentError.new("target cannot be empty") if target.empty?
      Platform::Applications.open(target, application)
    end
  end
end
