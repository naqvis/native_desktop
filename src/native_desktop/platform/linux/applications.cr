{% if flag?(:linux) %}
  module NativeDesktop::Platform::Applications
    extend self

    @[Link("X11", pkg_config: "x11")]
    lib LibX11Applications
      alias Display = Void
      alias Window = LibC::ULong

      struct ClassHint
        resource_name : UInt8*
        resource_class : UInt8*
      end

      fun XOpenDisplay(name : UInt8*) : Display*
      fun XCloseDisplay(display : Display*) : Int32
      fun XGetInputFocus(display : Display*, window : Window*, revert_to : Int32*) : Int32
      fun XGetClassHint(display : Display*, window : Window, hint : ClassHint*) : Int32
      fun XFree(data : Void*) : Int32
    end

    @[Link("gio-2.0")]
    lib LibGIOApplications
      fun g_app_info_launch_default_for_uri(uri : UInt8*, context : Void*, error : Void**) : Int32
      fun g_app_info_create_from_commandline(commandline : UInt8*, name : UInt8*, flags : Int32, error : Void**) : Void*
      fun g_app_info_launch_uris(info : Void*, uris : Void*, context : Void*, error : Void**) : Int32
      fun g_filename_to_uri(filename : UInt8*, hostname : UInt8*, error : Void**) : UInt8*
      fun g_list_append(list : Void*, data : Void*) : Void*
      fun g_list_free(list : Void*) : Nil
      fun g_object_unref(object : Void*) : Nil
      fun g_free(data : Void*) : Nil
    end

    def foreground_name : String?
      return nil if ENV["WAYLAND_DISPLAY"]?
      display = LibX11Applications.XOpenDisplay(Pointer(UInt8).null)
      return nil if display.null?
      begin
        window = uninitialized LibX11Applications::Window
        revert_to = uninitialized Int32
        return nil if LibX11Applications.XGetInputFocus(display, pointerof(window), pointerof(revert_to)) == 0 || window == 0
        hint = LibX11Applications::ClassHint.new
        return nil if LibX11Applications.XGetClassHint(display, window, pointerof(hint)) == 0
        begin
          value = hint.resource_class.null? ? hint.resource_name : hint.resource_class
          value.null? ? nil : String.new(value)
        ensure
          LibX11Applications.XFree(hint.resource_name.as(Void*)) unless hint.resource_name.null?
          LibX11Applications.XFree(hint.resource_class.as(Void*)) unless hint.resource_class.null?
        end
      ensure
        LibX11Applications.XCloseDisplay(display)
      end
    rescue
      nil
    end

    def open(target : String, application : String?) : Nil
      if target.includes?("://")
        launch(target.to_unsafe, target, application)
        return
      end

      uri = LibGIOApplications.g_filename_to_uri(
        Path[target].expand.to_s,
        nil,
        nil
      )
      raise Error.new("could not convert path to URI", :open_failed) unless uri
      raise Error.new("could not convert path to URI", :open_failed) if uri.null?

      begin
        launch(uri, target, application)
      ensure
        LibGIOApplications.g_free(uri.as(Void*))
      end
    end

    private def launch(uri : Pointer(UInt8), target : String, application : String?) : Nil
      result = if application
                 info = LibGIOApplications.g_app_info_create_from_commandline("#{application} %u", application, 1, nil)
                 raise Error.new("application is unavailable", :open_failed) if info.null?
                 begin
                   list = LibGIOApplications.g_list_append(Pointer(Void).null, uri.as(Void*))
                   begin
                     LibGIOApplications.g_app_info_launch_uris(info, list, nil, nil)
                   ensure
                     LibGIOApplications.g_list_free(list)
                   end
                 ensure
                   LibGIOApplications.g_object_unref(info)
                 end
               else
                 LibGIOApplications.g_app_info_launch_default_for_uri(uri, nil, nil)
               end
      raise Error.new("failed to open #{target.inspect}", :open_failed) if result == 0
    end
  end
{% end %}
