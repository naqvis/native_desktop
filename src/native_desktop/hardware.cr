module NativeDesktop
  # Hardware families supported by device enumeration.
  enum HardwareKind
    Bluetooth
    USB
    Serial
    HID
    NFC
  end

  # A connected device reported by the operating system.
  struct HardwareDevice
    getter id : String
    getter name : String
    getter kind : HardwareKind
    getter vendor_id : UInt16?
    getter product_id : UInt16?

    def initialize(
      @id : String,
      @name : String,
      @kind : HardwareKind,
      @vendor_id : UInt16? = nil,
      @product_id : UInt16? = nil,
    )
      raise ArgumentError.new("device id cannot be empty") if @id.empty?
      raise ArgumentError.new("device name cannot be empty") if @name.empty?
    end
  end

  # One-shot enumeration of connected Bluetooth, USB, serial, and HID devices.
  module Hardware
    extend self

    def available?(kind : HardwareKind) : Bool
      !kind.nfc?
    end

    def enumerate(kind : HardwareKind) : Array(HardwareDevice)
      return [] of HardwareDevice unless available?(kind)
      Platform::Hardware.enumerate(kind)
    end
  end

  native_desktop_open_id(HardwareEventType, "hardware event type")

  module HardwareEventTypes
    Connected    = HardwareEventType["connected"]
    Disconnected = HardwareEventType["disconnected"]
  end

  record HardwareEvent, type : HardwareEventType, device : HardwareDevice

  class HardwareMonitor
    @lock = Mutex.new
    @running = false
    @generation = 0_u64

    def start(kinds : Enumerable(HardwareKind) = HardwareKind.values, interval : Time::Span = 2.seconds, &changed : HardwareEvent ->) : Nil
      raise ArgumentError.new("monitor interval must be positive") unless interval.positive?
      selected = kinds.select { |kind| Hardware.available?(kind) }
      raise ArgumentError.new("monitor must include a supported hardware kind") if selected.empty?
      generation = @lock.synchronize do
        return if @running
        @running = true
        @generation &+= 1
      end
      initial = snapshot(selected)
      Runtime.spawn_background { poll(generation, selected, initial, interval, changed) }
    rescue ex
      @lock.synchronize { @running = false if @generation == generation }
      raise ex
    end

    def stop : Nil
      @lock.synchronize do
        @running = false
        @generation &+= 1
      end
    end

    def running? : Bool
      @lock.synchronize { @running }
    end

    private def snapshot(kinds : Array(HardwareKind)) : Hash(String, HardwareDevice)
      kinds.flat_map { |kind| Hardware.enumerate(kind) }.to_h { |device| {device.id, device} }
    end

    private def poll(generation : UInt64, kinds : Array(HardwareKind), last : Hash(String, HardwareDevice), interval : Time::Span, changed : Proc(HardwareEvent, Nil)) : Nil
      loop do
        sleep interval
        break unless @lock.synchronize { @running && @generation == generation }
        current = snapshot(kinds)
        current.each { |id, device| changed.call(HardwareEvent.new(HardwareEventTypes::Connected, device)) unless last.has_key?(id) }
        last.each { |id, device| changed.call(HardwareEvent.new(HardwareEventTypes::Disconnected, device)) unless current.has_key?(id) }
        last = current
      end
    ensure
      @lock.synchronize { @running = false if @generation == generation }
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::HardwareEnumeration, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Capabilities.register(NativeDesktop::Features::HardwareMonitoring, NativeDesktop::CapabilityState::Supported)

{% if flag?(:darwin) %}
  require "./platform/macos/hardware"
{% elsif flag?(:linux) %}
  require "./platform/linux/hardware"
{% elsif flag?(:windows) %}
  require "./platform/windows/hardware"
{% end %}
