module NativeDesktop
  enum ContextMenuItemType
    Normal
    Separator
    Checkbox
  end

  # A native context-menu entry. Submenus contain more entries of this type.
  struct ContextMenuItem
    getter id : String
    getter label : String
    getter enabled : Bool
    getter checked : Bool
    getter type : ContextMenuItemType
    getter submenu : Array(ContextMenuItem)?

    def initialize(
      @id : String = "",
      @label : String = "",
      @enabled : Bool = true,
      @checked : Bool = false,
      @type : ContextMenuItemType = ContextMenuItemType::Normal,
      @submenu : Array(ContextMenuItem)? = nil,
    )
    end

    def enabled? : Bool
      @enabled
    end

    def checked? : Bool
      @checked
    end
  end

  module ContextMenus
    extend self

    def available? : Bool
      Runtime.dispatch_sync { platform_available? }
    end

    # Shows *items* at the supplied client coordinates and returns the selected id.
    def show(items : Array(ContextMenuItem), x : Int32, y : Int32, window : Void*) : String?
      raise ArgumentError.new("native window handle cannot be null") if window.null?
      return nil if items.empty?
      Runtime.dispatch_sync { platform_show(items, x, y, window) }
    end

    private def platform_available? : Bool
      {% if flag?(:darwin) %}
        Platform::MacOS::ContextMenu.available?
      {% elsif flag?(:linux) %}
        Platform::Linux::ContextMenu.available?
      {% elsif flag?(:windows) %}
        Platform::Windows::ContextMenu.available?
      {% end %}
    end

    private def platform_show(items, x, y, window)
      {% if flag?(:darwin) %}
        Platform::MacOS::ContextMenu.show_context_menu(items, x, y, window)
      {% elsif flag?(:linux) %}
        Platform::Linux::ContextMenu.show_context_menu(items, x, y, window)
      {% elsif flag?(:windows) %}
        Platform::Windows::ContextMenu.show_context_menu(items, x, y, window)
      {% end %}
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/context_menu"
{% elsif flag?(:linux) %}
  require "./platform/linux/context_menu"
{% elsif flag?(:windows) %}
  require "./platform/windows/context_menu"
{% end %}
