require "./win32_common"

{% if flag?(:windows) %}
  module NativeDesktop::Platform::WindowEffects
    extend self

    @[Link("dwmapi")]
    lib LibDwmWindowEffects
      struct BlurBehind
        flags : UInt32
        enabled : Int32
        region : Void*
        transition_on_maximized : Int32
      end

      fun DwmSetWindowAttribute(window : Void*, attribute : UInt32, value : Void*, size : UInt32) : Int32
      fun DwmEnableBlurBehindWindow(window : Void*, blur : BlurBehind*) : Int32
    end

    def apply(window : Void*, effects : NativeDesktop::WindowEffects) : Nil
      apply_mica(window) if effects.mica
      apply_acrylic(window) if effects.acrylic
      apply_blur(window) if effects.blur_behind
    end

    private def apply_mica(window : Void*) : Nil
      enabled = 1_u32
      LibDwmWindowEffects.DwmSetWindowAttribute(window, 1029_u32, pointerof(enabled).as(Void*), sizeof(UInt32))
    end

    private def apply_blur(window : Void*) : Nil
      blur = LibDwmWindowEffects::BlurBehind.new
      blur.flags = 1_u32
      blur.enabled = 1
      LibDwmWindowEffects.DwmEnableBlurBehindWindow(window, pointerof(blur))
    end

    private def apply_acrylic(window : Void*) : Nil
      library = Windows::LibKernel32.GetModuleHandleA("user32.dll")
      return if library.null?
      address = Windows::LibKernel32.GetProcAddress(library, "SetWindowCompositionAttribute")
      return if address.null?

      accent = StaticArray[4_u32, 0_u32, 0x99_000000_u32, 0_u32]
      data = StaticArray(Void*, 3).new(Pointer(Void).null)
      data[0] = Pointer(Void).new(19_u64)
      data[1] = accent.to_unsafe.as(Void*)
      data[2] = Pointer(Void).new((accent.size * sizeof(UInt32)).to_u64)
      Proc(Void*, Void*, Int32).new(address, Pointer(Void).null).call(window, data.to_unsafe.as(Void*))
    end
  end
{% end %}
