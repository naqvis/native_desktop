module NativeDesktop
  enum ToolbarStyle
    Default
    Dark
    Light
    Transparent
  end

  enum ToolbarItemType
    Button
    Toggle
    Dropdown
    Color
    Separator
  end

  struct ToolbarIcon
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

  class ToolbarItem
    getter id : String
    getter label : String
    getter icon : ToolbarIcon?
    property enabled : Bool
    property checked : Bool
    getter type : ToolbarItemType
    getter options : Array(String)
    property selected_index : Int32
    property color : String
    getter action : Proc(Nil)?

    def initialize(
      @id : String,
      @label : String,
      @icon : ToolbarIcon? = nil,
      @enabled : Bool = true,
      @checked : Bool = false,
      @type : ToolbarItemType = ToolbarItemType::Button,
      @options : Array(String) = [] of String,
      @selected_index : Int32 = 0,
      @color : String = "",
      @action : Proc(Nil)? = nil,
    )
    end

    def self.separator : self
      new("__separator__", "", type: ToolbarItemType::Separator)
    end
  end

  # A native toolbar attached to a host-owned top-level window.
  class Toolbar
    @@owner_lock = Mutex.new
    @@owner : Toolbar?

    getter items : Array(ToolbarItem)
    property style : ToolbarStyle
    property title : String
    getter? visible : Bool

    def initialize(
      @items = [] of ToolbarItem,
      @style = ToolbarStyle::Default,
      @title = "",
      @visible = true,
    )
      @window = Pointer(Void).null
    end

    def attach(window : Void*, content : Void*? = nil) : Nil
      raise ArgumentError.new("native window handle cannot be null") if window.null?
      return if @window == window
      return unless @window.null?

      claimed = @@owner_lock.synchronize do
        if @@owner
          false
        else
          @@owner = self
          true
        end
      end
      return unless claimed

      begin
        Runtime.dispatch_sync { NativeToolbarPlatform.register(window, content, self) }
        @window = window
      rescue ex
        @@owner_lock.synchronize { @@owner = nil if @@owner.same?(self) }
        raise ex
      end
    end

    def add(item : ToolbarItem) : self
      @items << item
      self
    end

    def button(id : String, label : String, icon : ToolbarIcon? = nil, &action : ->) : ToolbarItem
      item = ToolbarItem.new(id, label, icon, action: action)
      add(item)
      item
    end

    def toggle(id : String, label : String, icon : ToolbarIcon? = nil, checked : Bool = false, &action : ->) : ToolbarItem
      item = ToolbarItem.new(id, label, icon, checked: checked, type: ToolbarItemType::Toggle, action: action)
      add(item)
      item
    end

    def dropdown(id : String, label : String, options : Array(String), icon : ToolbarIcon? = nil, selected_index : Int32 = 0, &action : ->) : ToolbarItem
      item = ToolbarItem.new(id, label, icon, type: ToolbarItemType::Dropdown, options: options, selected_index: selected_index, action: action)
      add(item)
      item
    end

    def color(id : String, label : String, value : String, &action : ->) : ToolbarItem
      item = ToolbarItem.new(id, label, type: ToolbarItemType::Color, color: value, action: action)
      add(item)
      item
    end

    def separator : self
      add(ToolbarItem.separator)
    end

    def sync : Nil
      Runtime.dispatch_sync do
        NativeToolbarPlatform.update_items(@items)
        NativeToolbarPlatform.visible = @visible
      end
    end

    def visible=(value : Bool) : Nil
      @visible = value
      Runtime.dispatch_sync { NativeToolbarPlatform.visible = value }
    end

    def cleanup : Nil
      owned = @@owner_lock.synchronize { @@owner.same?(self) }
      return unless owned

      begin
        Runtime.dispatch_sync { NativeToolbarPlatform.cleanup }
      ensure
        @window = Pointer(Void).null
        @@owner_lock.synchronize { @@owner = nil if @@owner.same?(self) }
      end
    end

    {% if flag?(:darwin) %}
      private alias NativeToolbarPlatform = Platform::MacOS::Toolbar
    {% elsif flag?(:linux) %}
      private alias NativeToolbarPlatform = Platform::Linux::Toolbar
    {% elsif flag?(:windows) %}
      private alias NativeToolbarPlatform = Platform::Windows::Toolbar
    {% end %}
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/toolbar"
{% elsif flag?(:linux) %}
  require "./platform/linux/toolbar"
{% elsif flag?(:windows) %}
  require "./platform/windows/toolbar"
{% end %}
