require "log"
require "./objc"

module NativeDesktop::Platform::Power
  extend self

  @[Link(framework: "IOKit")]
  @[Link(framework: "CoreFoundation")]
  lib LibIOPowerStatus
    fun IOPSCopyPowerSourcesInfo : Void*
    fun IOPSGetProvidingPowerSourceType(blob : Void*) : Void*
    fun IOPSCopyPowerSourcesList(blob : Void*) : Void*
    fun IOPSGetPowerSourceDescription(blob : Void*, source : Void*) : Void*
    fun cf_array_count = CFArrayGetCount(array : Void*) : Int64
    fun cf_array_value = CFArrayGetValueAtIndex(array : Void*, index : Int64) : Void*
    fun cf_dictionary_value = CFDictionaryGetValue(dictionary : Void*, key : Void*) : Void*
    fun cf_number_value = CFNumberGetValue(number : Void*, type : UInt32, value : Void*) : Int32
    fun cf_boolean_value = CFBooleanGetValue(boolean : Void*) : UInt8
    fun cf_string_get_c_string = CFStringGetCString(string : Void*, buffer : UInt8*, size : Int64, encoding : UInt32) : UInt8
    fun cf_release = CFRelease(value : Void*) : Nil
  end

  UTF8_ENCODING = 0x08000100_u32
  NUMBER_INT    =          9_u32

  def battery : BatteryStatus?
    MacOS::ObjC.pool do
      blob = LibIOPowerStatus.IOPSCopyPowerSourcesInfo
      next nil if blob.null?
      begin
        sources = LibIOPowerStatus.IOPSCopyPowerSourcesList(blob)
        next nil if sources.null?
        begin
          next nil if LibIOPowerStatus.cf_array_count(sources) <= 0
          source = LibIOPowerStatus.cf_array_value(sources, 0)
          next nil if source.null?
          description = LibIOPowerStatus.IOPSGetPowerSourceDescription(blob, source)
          next nil if description.null?

          current = number(description, "Current Capacity")
          maximum = number(description, "Max Capacity")
          level = if current && maximum && maximum > 0
                    (current.to_f64 / maximum).clamp(0.0, 1.0)
                  end
          charging = boolean(description, "Is Charging") || false
          remaining_key = charging ? "Time to Full Charge" : "Time to Empty"
          remaining = number(description, remaining_key).try { |minutes| minutes >= 0 ? minutes.minutes : nil }
          external = power_source(blob) == "AC Power"

          BatteryStatus.new(level, charging, external, remaining)
        ensure
          LibIOPowerStatus.cf_release(sources)
        end
      ensure
        LibIOPowerStatus.cf_release(blob)
      end
    end
  rescue ex
    Log.warn(exception: ex) { "could not read macOS battery state" }
    nil
  end

  private def number(dictionary : Void*, key : String) : Int32?
    value = LibIOPowerStatus.cf_dictionary_value(dictionary, MacOS::ObjC.string(key))
    return nil if value.null?
    result = 0_i32
    LibIOPowerStatus.cf_number_value(value, NUMBER_INT, pointerof(result).as(Void*)) == 0 ? nil : result
  end

  private def boolean(dictionary : Void*, key : String) : Bool?
    value = LibIOPowerStatus.cf_dictionary_value(dictionary, MacOS::ObjC.string(key))
    value.null? ? nil : LibIOPowerStatus.cf_boolean_value(value) != 0
  end

  private def power_source(blob : Void*) : String?
    value = LibIOPowerStatus.IOPSGetProvidingPowerSourceType(blob)
    return nil if value.null?
    buffer = Bytes.new(64, 0_u8)
    return nil if LibIOPowerStatus.cf_string_get_c_string(value, buffer.to_unsafe, buffer.size.to_i64, UTF8_ENCODING) == 0
    String.new(buffer.to_unsafe)
  end
end
