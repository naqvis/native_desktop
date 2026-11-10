module NativeDesktop
  # Modifier keys accepted by a global shortcut.
  enum ShortcutModifier
    Ctrl
    Alt
    Shift
    Meta
  end

  # Keys that can participate in a global shortcut.
  enum ShortcutKey
    A; B; C; D; E; F; G; H; I; J; K; L; M
    N; O; P; Q; R; S; T; U; V; W; X; Y; Z
    Num0; Num1; Num2; Num3; Num4; Num5; Num6; Num7; Num8; Num9
    F1; F2; F3; F4; F5; F6; F7; F8; F9; F10; F11; F12
    Space; Enter; Tab; Escape; Backspace; Delete
    Left; Right; Up; Down
    Home; End; PageUp; PageDown
    Comma; Period; Semicolon; Quote; BracketLeft; BracketRight
    Backslash; Slash; Minus; Equal
  end

  # A platform-independent key and modifier combination.
  struct Shortcut
    @modifiers : Array(ShortcutModifier)
    getter key : ShortcutKey

    def initialize(modifiers : Array(ShortcutModifier), @key : ShortcutKey)
      @modifiers = modifiers.uniq.sort_by(&.value)
    end

    # Returns the required modifiers in canonical order.
    def modifiers : Array(ShortcutModifier)
      @modifiers.dup
    end

    # Returns the stable process-wide registration key.
    def identifier : String
      modifiers = @modifiers.join("+")
      modifiers.empty? ? @key.to_s : "#{modifiers}+#{@key}"
    end
  end

  # Owns process-wide global keyboard shortcut registrations.
  class GlobalShortcuts
    @operation_lock = Mutex.new
    @lock = Mutex.new
    @entries = {} of String => {Shortcut, Proc(Nil)}
    @listening = false

    # Adds a shortcut and its handler. A duplicate raises `:shortcut_conflict`.
    def register(shortcut : Shortcut, &action : ->) : Nil
      @operation_lock.synchronize do
        identifier = shortcut.identifier
        listening = @lock.synchronize do
          raise Error.new("shortcut #{identifier.inspect} is already registered", :shortcut_conflict) if @entries.has_key?(identifier)
          @entries[identifier] = {shortcut, action}
          @listening
        end
        begin
          platform_register(identifier, shortcut, action) if listening
        rescue ex
          @lock.synchronize { @entries.delete(identifier) }
          raise ex
        end
      end
    end

    # Removes a shortcut if it is registered.
    def unregister(shortcut : Shortcut) : Nil
      @operation_lock.synchronize do
        identifier = shortcut.identifier
        entry, listening = @lock.synchronize { {@entries.delete(identifier), @listening} }
        platform_unregister(identifier) if entry && listening
      end
    end

    # Removes every shortcut from this registry.
    def unregister_all : Nil
      @operation_lock.synchronize do
        entries, listening = @lock.synchronize do
          values = @entries.values.dup
          @entries.clear
          {values, @listening}
        end
        entries.each { |shortcut, _| platform_unregister(shortcut.identifier) } if listening
      end
    end

    # Registers all entries with the operating system and begins listening.
    def start : Nil
      @operation_lock.synchronize do
        entries = @lock.synchronize do
          return if @listening
          @entries.values.dup
        end
        registered = [] of Shortcut
        begin
          entries.each do |shortcut, action|
            platform_register(shortcut.identifier, shortcut, action)
            registered << shortcut
          end
          Runtime.dispatch_sync { NativeShortcutsPlatform.start_listening }
          @lock.synchronize { @listening = true }
        rescue ex
          registered.each { |shortcut| platform_unregister(shortcut.identifier) rescue nil }
          raise Error.new("failed to start global shortcuts: #{ex.message}", :shortcut_listen_failed)
        end
      end
    end

    # Stops listening while retaining the in-memory registrations.
    def stop : Nil
      @operation_lock.synchronize do
        entries = @lock.synchronize do
          return unless @listening
          @listening = false
          @entries.values.dup
        end
        entries.each { |shortcut, _| platform_unregister(shortcut.identifier) rescue nil }
        Runtime.dispatch_sync { NativeShortcutsPlatform.stop_listening }
      end
    end

    # Returns whether this registry is currently receiving native events.
    def listening? : Bool
      @lock.synchronize { @listening }
    end

    # Returns a snapshot of the registered shortcuts.
    def registered : Array(Shortcut)
      @lock.synchronize { @entries.values.map(&.[0]) }
    end

    # Stops listening and removes all registrations.
    def cleanup : Nil
      stop
      unregister_all
    end

    private def platform_register(identifier : String, shortcut : Shortcut, action : Proc(Nil)) : Nil
      Runtime.dispatch_sync do
        NativeShortcutsPlatform.register(identifier, shortcut.modifiers.map(&.value), shortcut.key.value, action)
      end
    rescue ex
      raise Error.new("failed to register shortcut #{identifier.inspect}: #{ex.message}", :shortcut_register_failed)
    end

    private def platform_unregister(identifier : String) : Nil
      Runtime.dispatch_sync { NativeShortcutsPlatform.unregister(identifier) }
    end

    {% if flag?(:darwin) %}
      private alias NativeShortcutsPlatform = Platform::MacOS::Shortcuts
    {% elsif flag?(:linux) %}
      private alias NativeShortcutsPlatform = Platform::Linux::Shortcuts
    {% elsif flag?(:windows) %}
      private alias NativeShortcutsPlatform = Platform::Windows::Shortcuts
    {% end %}
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::GlobalShortcuts, NativeDesktop::CapabilityState::Supported)

{% if flag?(:darwin) %}
  require "./platform/macos/shortcuts"
{% elsif flag?(:linux) %}
  require "./platform/linux/shortcuts"
{% elsif flag?(:windows) %}
  require "./platform/windows/shortcuts"
{% end %}
