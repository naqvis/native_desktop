{% if flag?(:darwin) %}
  require "./platform/macos/url_schemes"
{% elsif flag?(:linux) %}
  require "./platform/linux/url_schemes"
{% elsif flag?(:windows) %}
  require "./platform/windows/url_schemes"
{% end %}

module NativeDesktop
  # Description of an application that handles a custom URL scheme.
  record URLSchemeRegistration,
    scheme : String,
    application_name : String,
    executable : Path

  # Registers custom URL schemes with the current user's desktop session.
  module URLSchemes
    extend self
    SCHEME_PATTERN = /\A[a-zA-Z][a-zA-Z0-9+.-]*\z/

    def register(registration : URLSchemeRegistration) : Nil
      normalized = normalize(registration.scheme)
      raise ArgumentError.new("application name cannot be empty") if registration.application_name.strip.empty?
      raise ArgumentError.new("executable must be an absolute path") unless registration.executable.absolute?
      Platform::URLSchemes.register(normalized, registration.application_name, registration.executable)
    end

    def unregister(scheme : String) : Nil
      Platform::URLSchemes.unregister(normalize(scheme))
    end

    private def normalize(scheme : String) : String
      value = scheme.downcase
      raise ArgumentError.new("invalid URL scheme #{scheme.inspect}") unless SCHEME_PATTERN.matches?(value)
      value
    end
  end
end
