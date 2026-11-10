require "log"
require "./win32_common"

module NativeDesktop::Platform::Power
  extend self

  NO_BATTERY       = 0x80_u8
  BATTERY_CHARGING = 0x08_u8
  UNKNOWN_PERCENT  = 0xff_u8
  UNKNOWN_TIME     = UInt32::MAX

  def battery : BatteryStatus?
    status = uninitialized Windows::LibKernel32::SystemPowerStatus
    return nil if Windows::LibKernel32.GetSystemPowerStatus(pointerof(status)) == 0
    return nil unless (status.battery_flag & NO_BATTERY) == 0

    level = if status.battery_life_percent == UNKNOWN_PERCENT
              nil
            else
              (status.battery_life_percent.to_f64 / 100.0).clamp(0.0, 1.0)
            end
    remaining = status.battery_life_time == UNKNOWN_TIME ? nil : status.battery_life_time.seconds
    charging = (status.battery_flag & BATTERY_CHARGING) != 0
    external = status.ac_line_status == 1
    BatteryStatus.new(level, charging, external, remaining)
  rescue ex
    Log.warn(exception: ex) { "could not read Windows battery state" }
    nil
  end
end
