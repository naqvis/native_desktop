module NativeDesktop
  struct TrayIcon
    getter bytes : Bytes?
    getter name : String?
    getter key : String?

    def self.bytes(value : Bytes, key : String? = nil) : self
      raise ArgumentError.new("icon bytes cannot be empty") if value.empty?
      new(value, nil, key)
    end

    def self.name(value : String) : self
      raise ArgumentError.new("icon name cannot be empty") if value.empty?
      new(nil, value, nil)
    end

    private def initialize(@bytes : Bytes?, @name : String?, @key : String?)
    end
  end

  enum TrayMenuItemType
    Normal
    Checkbox
    Radio
    Separator
  end

  # An entry in a system tray menu.
  class TrayMenuItem
    getter id : String
    getter label : String
    getter type : TrayMenuItemType
    getter enabled : Bool
    getter checked : Bool
    getter accelerator : String?
    getter submenu : Array(TrayMenuItem)
    getter action : Proc(Nil)?

    def initialize(
      @id : String,
      @label : String,
      @type : TrayMenuItemType = TrayMenuItemType::Normal,
      @enabled : Bool = true,
      @checked : Bool = false,
      @accelerator : String? = nil,
      @submenu : Array(TrayMenuItem) = [] of TrayMenuItem,
      @action : Proc(Nil)? = nil,
    )
    end
  end

  # :nodoc:
  alias PlatformTrayMenuEntry = NamedTuple(
    id: String,
    label: String,
    type: Int32,
    enabled: Int32,
    checked: Int32,
    parent_id: String,
    accelerator: String?)

  module Tray
    extend self

    {% if flag?(:darwin) %}
      alias NativeTrayPlatform = Platform::MacOS::Tray
    {% elsif flag?(:linux) %}
      alias NativeTrayPlatform = Platform::Linux::Tray
    {% elsif flag?(:windows) %}
      alias NativeTrayPlatform = Platform::Windows::Tray
    {% end %}

    def create(application_id : String, icon : TrayIcon? = nil, tooltip : String? = nil) : Nil
      raise ArgumentError.new("application id cannot be empty") if application_id.empty?
      Runtime.dispatch_sync { NativeTrayPlatform.create(application_id, icon, tooltip) }
    end

    def on_click(&block : Int32 ->) : Nil
      Runtime.dispatch_sync { NativeTrayPlatform.on_click { |button| block.call(button) } }
    end

    def update_icon(icon : TrayIcon) : Nil
      Runtime.dispatch_sync { NativeTrayPlatform.update_icon(icon) }
    end

    def set_menu(items : Array(TrayMenuItem)) : Nil
      entries = [] of PlatformTrayMenuEntry
      callbacks = {} of String => Proc(Nil)
      flatten_menu(items, "", entries, callbacks)
      Runtime.dispatch_sync { NativeTrayPlatform.set_menu(entries, callbacks) }
    end

    def tooltip=(text : String) : Nil
      Runtime.dispatch_sync { NativeTrayPlatform.tooltip = text }
    end

    def destroy : Nil
      Runtime.dispatch_sync { NativeTrayPlatform.destroy }
    end

    private def flatten_menu(
      items : Array(TrayMenuItem),
      parent_id : String,
      entries : Array(PlatformTrayMenuEntry),
      callbacks : Hash(String, Proc(Nil)),
    ) : Nil
      items.each do |item|
        entries << {
          id:          item.id,
          label:       item.label,
          type:        item.type.value,
          enabled:     item.enabled ? 1 : 0,
          checked:     item.checked ? 1 : 0,
          parent_id:   parent_id,
          accelerator: item.accelerator,
        }
        if action = item.action
          callbacks[item.id] = action
        end
        flatten_menu(item.submenu, item.id, entries, callbacks) unless item.submenu.empty?
      end
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/tray"
{% elsif flag?(:linux) %}
  require "./platform/linux/tray"
{% elsif flag?(:windows) %}
  require "./platform/windows/tray"
{% end %}
