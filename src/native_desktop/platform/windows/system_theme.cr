require "./win32_common"

module NativeDesktop::Platform::SystemTheme
  extend self

  HKEY_CURRENT_USER = Pointer(Void).new(0x80000001_u64)
  RRF_RT_REG_DWORD  = 0x10_u32

  def current : ColorScheme
    sub_key = wide("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize")
    value_name = wide("AppsUseLightTheme")
    value = 1_u32
    size = sizeof(UInt32).to_u32
    type = 0_u32
    result = Windows::LibAdvApi32.RegGetValueW(
      HKEY_CURRENT_USER,
      sub_key.to_unsafe,
      value_name.to_unsafe,
      RRF_RT_REG_DWORD,
      pointerof(type),
      pointerof(value).as(Void*),
      pointerof(size)
    )
    return ColorScheme::Light unless result == 0
    value == 0 ? ColorScheme::Dark : ColorScheme::Light
  end

  private def wide(value : String) : Slice(UInt16)
    units = value.to_utf16
    Slice(UInt16).new(units.size + 1, 0_u16).tap do |buffer|
      units.each_with_index { |unit, index| buffer[index] = unit }
    end
  end
end
