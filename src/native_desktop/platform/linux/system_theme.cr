module NativeDesktop::Platform::SystemTheme
  extend self

  @[Link("gio-2.0")]
  lib LibGIOTheme
    fun g_settings_schema_source_get_default : Void*
    fun g_settings_schema_source_lookup(source : Void*, schema_id : UInt8*, recursive : Int32) : Void*
    fun g_settings_schema_has_key(schema : Void*, name : UInt8*) : Int32
    fun g_settings_schema_unref(schema : Void*) : Nil
    fun g_settings_new(schema_id : UInt8*) : Void*
    fun g_settings_get_string(settings : Void*, key : UInt8*) : UInt8*
  end

  @[Link("gobject-2.0")]
  lib LibGObjectTheme
    fun g_object_unref(object : Void*) : Nil
  end

  @[Link("glib-2.0")]
  lib LibGLibTheme
    fun g_free(value : Void*) : Nil
  end

  def current : ColorScheme
    return environment_fallback unless gnome_schema_available?
    settings = LibGIOTheme.g_settings_new("org.gnome.desktop.interface")
    return environment_fallback if settings.null?
    begin
      if schema_has_key?("color-scheme")
        scheme = setting(settings, "color-scheme")
        return ColorScheme::Dark if scheme.downcase.includes?("dark")
      end
      theme = setting(settings, "gtk-theme")
      theme.downcase.includes?("dark") ? ColorScheme::Dark : ColorScheme::Light
    ensure
      LibGObjectTheme.g_object_unref(settings)
    end
  end

  private def gnome_schema_available? : Bool
    source = LibGIOTheme.g_settings_schema_source_get_default
    return false if source.null?
    schema = LibGIOTheme.g_settings_schema_source_lookup(source, "org.gnome.desktop.interface", 1)
    return false if schema.null?
    LibGIOTheme.g_settings_schema_unref(schema)
    true
  end

  private def setting(settings : Void*, key : String) : String
    value = LibGIOTheme.g_settings_get_string(settings, key)
    return "" if value.null?
    begin
      String.new(value)
    ensure
      LibGLibTheme.g_free(value.as(Void*))
    end
  end

  private def schema_has_key?(key : String) : Bool
    source = LibGIOTheme.g_settings_schema_source_get_default
    return false if source.null?
    schema = LibGIOTheme.g_settings_schema_source_lookup(source, "org.gnome.desktop.interface", 1)
    return false if schema.null?
    begin
      LibGIOTheme.g_settings_schema_has_key(schema, key) != 0
    ensure
      LibGIOTheme.g_settings_schema_unref(schema)
    end
  end

  private def environment_fallback : ColorScheme
    theme = ENV["GTK_THEME"]? || ""
    theme.downcase.includes?("dark") ? ColorScheme::Dark : ColorScheme::Light
  end
end
