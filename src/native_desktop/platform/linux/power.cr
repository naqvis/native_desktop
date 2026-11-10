require "log"

module NativeDesktop::Platform::Power
  extend self

  ROOT = Path["/sys/class/power_supply"]

  def battery : BatteryStatus?
    return nil unless Dir.exists?(ROOT)
    supplies = Dir.children(ROOT).map { |name| ROOT / name }
    batteries = supplies.select { |path| read(path, "type") == "Battery" }
    return nil if batteries.empty?

    levels = batteries.compact_map { |path| percentage(path) }
    statuses = batteries.compact_map { |path| read(path, "status") }
    charging = statuses.any? { |status| status == "Charging" }
    external = external_power?(supplies, statuses)
    level = levels.empty? ? nil : levels.sum / levels.size
    remaining = estimate_remaining(batteries.first, charging)

    BatteryStatus.new(level, charging, external, remaining)
  rescue ex
    Log.warn(exception: ex) { "could not read Linux battery state" }
    nil
  end

  private def percentage(path : Path) : Float64?
    value = read(path, "capacity").try(&.to_f64?)
    value.try { |percent| (percent / 100.0).clamp(0.0, 1.0) }
  end

  private def external_power?(supplies : Array(Path), statuses : Array(String)) : Bool
    online = supplies.reject { |path| read(path, "type") == "Battery" }
      .any? { |path| read(path, "online") == "1" }
    online || statuses.any? { |status| status.in?("Charging", "Full", "Not charging") }
  end

  private def estimate_remaining(path : Path, charging : Bool) : Time::Span?
    now = numeric(path, "energy_now") || numeric(path, "charge_now")
    full = numeric(path, "energy_full") || numeric(path, "charge_full")
    rate = numeric(path, "power_now") || numeric(path, "current_now")
    return nil unless now && rate && rate > 0

    units = charging && full ? full - now : now
    return nil if units < 0
    (units / rate * 3600.0).seconds
  end

  private def numeric(path : Path, name : String) : Float64?
    read(path, name).try(&.to_f64?)
  end

  private def read(path : Path, name : String) : String?
    File.read(path / name).strip
  rescue File::Error
    nil
  end
end
