require "log"

# Optional Linux subsystems can be disabled at build time when their native
# library is unavailable. Pass the matching -D flag to `crystal`:
#
#   -Dnative_desktop_no_tray           (AppIndicator 3)
#   -Dnative_desktop_no_notifications  (libnotify)
#   -Dnative_desktop_no_speech         (Speech Dispatcher)
#   -Dnative_desktop_no_biometric      (fprintd)
#   -Dnative_desktop_no_hardware       (libudev)
#
# Disabled subsystems are omitted entirely: their accessors, capability, and
# permission registrations are not compiled. See guides/platform-support.md.

module NativeDesktop
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  # Process-wide system clipboard.
  def self.clipboard : Clipboard.class
    Clipboard
  end

  # Native file pickers and message dialogs.
  def self.dialogs : Dialogs.class
    Dialogs
  end

  # Connected displays and pointer location.
  def self.displays : Displays.class
    Displays
  end

  # Information about desktop applications.
  def self.applications : Applications.class
    Applications
  end

  # Custom URL-scheme registration.
  def self.url_schemes : URLSchemes.class
    URLSchemes
  end

  # Login autostart registration.
  def self.autostart : Autostart.class
    Autostart
  end

  {% if !flag?(:linux) || !flag?(:native_desktop_no_notifications) %}
    # Native desktop notifications.
    def self.notifications : Notifications.class
      Notifications
    end
  {% end %}

  # Native popup context menus.
  def self.context_menus : ContextMenus.class
    ContextMenus
  end

  {% if !flag?(:linux) || !flag?(:native_desktop_no_tray) %}
    # Process-wide system tray icon.
    def self.tray : Tray.class
      Tray
    end
  {% end %}

  # Native application menu bars.
  def self.application_menus : ApplicationMenus.class
    ApplicationMenus
  end

  # The operating system's effective light or dark appearance.
  def self.system_theme : SystemTheme.class
    SystemTheme
  end

  # Battery and external-power state.
  def self.power : Power.class
    Power
  end

  # Time since the last user input.
  def self.idle : Idle.class
    Idle
  end

  # Aggregate CPU counters.
  def self.cpu : CPU.class
    CPU
  end

  # Creates a new, owned text-to-speech engine. Unlike the process-wide
  # services above, this returns a fresh instance the caller must `cleanup`;
  # it is not a singleton.
  {% if !flag?(:linux) || !flag?(:native_desktop_no_speech) %}
    def self.speech : SpeechSynthesizer
      SpeechSynthesizer.new
    end

    # Creates a new, owned operating-system speech recognizer. Unlike the
    # process-wide services above, this returns a fresh instance the caller must
    # `cleanup`; it is not a singleton.
    def self.speech_recognizer : SpeechRecognizer
      SpeechRecognizer.new
    end
  {% end %}

  {% if !flag?(:linux) || !flag?(:native_desktop_no_biometric) %}
    # Operating-system biometric authentication.
    def self.biometric : Biometrics.class
      Biometrics
    end
  {% end %}

  # Operating-system trash or Recycle Bin.
  def self.trash : Trash.class
    Trash
  end

  # File type association registration.
  def self.file_associations : FileAssociations.class
    FileAssociations
  end

  {% if !flag?(:linux) || !flag?(:native_desktop_no_hardware) %}
    # Connected Bluetooth, USB, serial, and HID devices.
    def self.hardware : Hardware.class
      Hardware
    end
  {% end %}

  # Runtime feature support and limitations for the current desktop session.
  def self.capabilities : Capabilities.class
    Capabilities
  end

  # Operating-system permission state and settings helpers.
  def self.permissions : Permissions.class
    Permissions
  end

  # Application identity used by desktop registrations and diagnostics.
  def self.application : Application.class
    Application
  end

  # URL, file-open, and second-instance activation delivery.
  def self.activations : Activations.class
    Activations
  end

  # Suspend, resume, lock, unlock, and shutdown event delivery.
  def self.session : SessionLifecycle.class
    SessionLifecycle
  end

  # Generates an open identifier value type used across the public API.
  # Identifiers are plain strings with a non-empty invariant, a Symbol-or-String
  # constructor, and value-string semantics. Applications and extension shards
  # can define additional identifiers of any of these types without modifying
  # native_desktop.
  macro native_desktop_open_id(name, label)
  record {{name}}, value : String do
    def initialize(@value : String)
      raise ArgumentError.new({{label}} + " cannot be empty") if @value.strip.empty?
    end

    def self.[](value : String | Symbol) : self
      new(value.to_s)
    end

    def to_s(io : IO) : Nil
      io << value
    end
  end
end
end

require "./native_desktop/error"
require "./native_desktop/runtime"
require "./native_desktop/capabilities"
require "./native_desktop/registration"
require "./native_desktop/permissions"
require "./native_desktop/application_identity"
require "./native_desktop/activations"
require "./native_desktop/session_lifecycle"
require "./native_desktop/window"
require "./native_desktop/clipboard"
require "./native_desktop/dialogs"
require "./native_desktop/displays"
require "./native_desktop/applications"
require "./native_desktop/url_schemes"
require "./native_desktop/autostart"

require "./native_desktop/application_menus"
require "./native_desktop/toolbars"
require "./native_desktop/shortcuts"
require "./native_desktop/taskbar"
require "./native_desktop/kiosk"
require "./native_desktop/system_theme"
require "./native_desktop/power"
require "./native_desktop/idle"
require "./native_desktop/cpu"
require "./native_desktop/single_instance"
require "./native_desktop/drag_source"
require "./native_desktop/drop_target"
require "./native_desktop/file_associations"

{% if !flag?(:linux) || !flag?(:native_desktop_no_notifications) %}
  require "./native_desktop/notifications"
{% end %}
require "./native_desktop/context_menus"
{% if !flag?(:linux) || !flag?(:native_desktop_no_tray) %}
  require "./native_desktop/tray"
{% end %}
{% if !flag?(:linux) || !flag?(:native_desktop_no_speech) %}
  require "./native_desktop/speech"
{% end %}
{% if !flag?(:linux) || !flag?(:native_desktop_no_biometric) %}
  require "./native_desktop/biometric"
{% end %}
require "./native_desktop/trash"
{% if !flag?(:linux) || !flag?(:native_desktop_no_hardware) %}
  require "./native_desktop/hardware"
{% end %}
