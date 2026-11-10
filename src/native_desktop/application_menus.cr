module NativeDesktop
  # A clickable entry in an application menu.
  class MenuItem
    getter id : String
    getter label : String
    property enabled : Bool
    property checked : Bool
    getter accelerator : String?
    getter action : Proc(Nil)?

    def initialize(
      @id : String,
      @label : String,
      @enabled : Bool = true,
      @checked : Bool = false,
      @accelerator : String? = nil,
      @action : Proc(Nil)? = nil,
    )
      raise ArgumentError.new("menu item id cannot be empty") if @id.empty?
      raise ArgumentError.new("menu item label cannot be empty") if @label.empty?
    end
  end

  # A named menu containing items, separators, and nested menus.
  class Menu
    getter id : String
    getter label : String
    getter entries : Array(MenuItem | Menu | MenuSeparator)

    def initialize(@label : String, @id : String = "", @entries = [] of MenuItem | Menu | MenuSeparator)
    end

    def add(entry : MenuItem | Menu | MenuSeparator) : self
      @entries << entry
      self
    end

    def item(
      id : String,
      label : String,
      enabled : Bool = true,
      checked : Bool = false,
      accelerator : String? = nil,
      &action : ->
    ) : MenuItem
      item = MenuItem.new(id, label, enabled, checked, accelerator, action)
      add(item)
      item
    end

    def separator : self
      add(MenuSeparator.new)
    end

    def menu(label : String, id : String = "", &block : Menu ->) : Menu
      child = Menu.new(label, id)
      block.call(child)
      add(child)
      child
    end
  end

  # A visual separator between application-menu entries.
  struct MenuSeparator
  end

  # The ordered top-level menus installed for an application or window.
  class MenuBar
    getter menus : Array(Menu)

    def initialize(@menus = [] of Menu)
    end

    def add(menu : Menu) : self
      @menus << menu
      self
    end

    def menu(label : String, id : String = "", &block : Menu ->) : Menu
      menu = Menu.new(label, id)
      block.call(menu)
      add(menu)
      menu
    end
  end

  module ApplicationMenus
    extend self

    # macOS application menus are installed after its application loop starts.
    # Other supported platforms can attach a menu as soon as the window exists.
    def requires_running_event_loop? : Bool
      {% if flag?(:darwin) %}
        true
      {% else %}
        false
      {% end %}
    end

    # Installs *menu_bar* globally on macOS or on *window* elsewhere.
    def install(menu_bar : MenuBar, window : Void*? = nil) : Nil
      Runtime.dispatch_sync do
        {% if flag?(:darwin) %}
          Platform::MacOS::Menu.global_menu = menu_bar
        {% elsif flag?(:linux) %}
          if handle = window
            Platform::Linux::Menu.set_window_menu(handle, menu_bar)
          else
            Platform::Linux::Menu.global_menu = menu_bar
          end
        {% elsif flag?(:windows) %}
          if handle = window
            Platform::Windows::Menu.set_window_menu(handle, menu_bar)
          else
            Platform::Windows::Menu.global_menu = menu_bar
          end
        {% end %}
      end
    end

    # Gives the active platform a chance to consume a host event.
    # GUI hosts should call this before their normal event translation step.
    def process_event(event : Void*) : Bool
      {% if flag?(:windows) %}
        Platform::Windows::Menu.process_event(event)
      {% else %}
        false
      {% end %}
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/menu"
{% elsif flag?(:linux) %}
  require "./platform/linux/menu"
{% elsif flag?(:windows) %}
  require "./platform/windows/menu"
{% end %}
