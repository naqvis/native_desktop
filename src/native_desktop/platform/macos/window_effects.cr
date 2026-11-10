{% if flag?(:darwin) %}
  require "./objc"

  module NativeDesktop::Platform::WindowEffects
    extend self

    def apply(window : Void*, effects : NativeDesktop::WindowEffects) : Nil
      return unless effects.vibrancy

      MacOS::ObjC.pool do
        objc = MacOS::ObjC
        view = objc.msg(objc.msg(objc.klass("NSVisualEffectView"), "alloc"), "init")
        material = case effects.material
                   when :dark       then 1_i64
                   when :light      then 2_i64
                   when :ultra_dark then 3_i64
                   when :sidebar    then 7_i64
                   when :window     then 8_i64
                   when :hud_window then 9_i64
                   when :menu       then 10_i64
                   when :popover    then 11_i64
                   when :selection  then 12_i64
                   else                  1_i64
                   end
        objc.msg_long(view, "setMaterial:", material)
        objc.msg_long(view, "setBlendingMode:", 1_i64)
        objc.msg_long(view, "setState:", 1_i64)
        objc.msg(objc.msg(window, "contentView"), "addSubview:", view)
      end
    end
  end
{% end %}
