{% if flag?(:darwin) %}
  require "./platform/macos/window"
  require "./platform/macos/window_effects"
{% elsif flag?(:linux) %}
  require "./platform/linux/window"
  require "./platform/linux/window_effects"
{% elsif flag?(:windows) %}
  require "./platform/windows/window"
  require "./platform/windows/window_effects"
{% end %}

module NativeDesktop
  # Platform-native visual effects for a window. Unsupported effects are ignored.
  record WindowEffects,
    vibrancy : Bool = false,
    material : Symbol = :dark,
    mica : Bool = false,
    acrylic : Bool = false,
    blur_behind : Bool = false

  # Non-owning reference to a top-level native window supplied by a host toolkit.
  struct Window
    getter handle : Void*

    def initialize(@handle : Void*)
      raise ArgumentError.new("native window handle cannot be null") if @handle.null?
    end

    def self.attach(handle : Void*) : self
      new(handle)
    end

    # Keeps this window above ordinary application windows.
    def always_on_top=(enabled : Bool) : Nil
      Runtime.dispatch_sync { Platform::Window.set_always_on_top(handle, enabled) }
    end

    # Extends content into the titlebar when enabled. On Linux and Windows this
    # removes the standard frame; on macOS it enables full-size content.
    def titlebar_overlay=(enabled : Bool) : Nil
      Runtime.dispatch_sync { Platform::Window.set_titlebar_overlay(handle, enabled) }
    end

    # Applies the effects supported by the current platform.
    def apply(effects : WindowEffects) : Nil
      Runtime.dispatch_sync { Platform::WindowEffects.apply(handle, effects) }
    end

    # Moves the window to the given screen coordinates.
    def move(x : Int32, y : Int32) : Nil
      Runtime.dispatch_sync { Platform::Window.move(handle, x, y) }
    end

    # Returns the window position in screen coordinates.
    def position : {Int32, Int32}
      Runtime.dispatch_sync { Platform::Window.position(handle) }
    end

    # Brings the window to the foreground.
    def focus : Nil
      Runtime.dispatch_sync { Platform::Window.focus(handle) }
    end

    # Shows the window.
    def show : Nil
      Runtime.dispatch_sync { Platform::Window.show(handle) }
    end

    # Hides the window.
    def hide : Nil
      Runtime.dispatch_sync { Platform::Window.hide(handle) }
    end

    # Minimizes the window.
    def minimize : Nil
      Runtime.dispatch_sync { Platform::Window.minimize(handle) }
    end

    # Maximizes the window.
    def maximize : Nil
      Runtime.dispatch_sync { Platform::Window.maximize(handle) }
    end

    # Restores the window from minimized or maximized state.
    def restore : Nil
      Runtime.dispatch_sync { Platform::Window.restore(handle) }
    end

    # Toggles fullscreen mode.
    def fullscreen=(value : Bool) : Nil
      Runtime.dispatch_sync { Platform::Window.set_fullscreen(handle, value) }
    end

    # Removes or restores the OS window frame (title bar, borders).
    def frameless=(value : Bool) : Nil
      Runtime.dispatch_sync { Platform::Window.set_frameless(handle, value) }
    end

    # Makes the window background transparent when true.
    def transparent=(value : Bool) : Nil
      Runtime.dispatch_sync { Platform::Window.set_transparent(handle, value) }
    end

    # Sets the window opacity (0.0 = fully transparent, 1.0 = fully opaque).
    def opacity=(value : Float64) : Nil
      unless value.finite? && value >= 0.0 && value <= 1.0
        raise ArgumentError.new("window opacity must be between 0.0 and 1.0")
      end
      Runtime.dispatch_sync { Platform::Window.set_opacity(handle, value) }
    end

    # Sets modal state relative to a parent window. The parent window
    # becomes non-interactive while this window is modal.
    def set_modal(parent_handle : Void*, value : Bool) : Nil
      Runtime.dispatch_sync { Platform::Window.set_modal(parent_handle, handle, value) }
    end

    def ==(other : self) : Bool
      handle == other.handle
    end

    def hash(hasher)
      handle.address.hash(hasher)
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::WindowControls, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Capabilities.register(NativeDesktop::Features::WindowEffects, NativeDesktop::CapabilityState::Supported)
