require "./objc_runtime"

module NativeDesktop::Platform::SystemTheme
  extend self

  def current : ColorScheme
    MacOS::ObjCRuntime.with_autorelease_pool do
      defaults_class = MacOS::ObjCRuntime.get_class("NSUserDefaults")
      return ColorScheme::Light if defaults_class.null?
      defaults = MacOS::ObjCRuntime.msg(defaults_class, "standardUserDefaults")
      return ColorScheme::Light if defaults.null?
      style = MacOS::ObjCRuntime.msg(defaults, "stringForKey:", MacOS::ObjCRuntime.nsstring("AppleInterfaceStyle"))
      style.null? ? ColorScheme::Light : ColorScheme::Dark
    end
  rescue
    ColorScheme::Light
  end
end
