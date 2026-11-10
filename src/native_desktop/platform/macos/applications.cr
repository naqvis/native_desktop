{% if flag?(:darwin) %}
  require "./objc"

  module NativeDesktop::Platform::Applications
    extend self

    def foreground_name : String?
      MacOS::ObjC.pool do
        workspace = MacOS::ObjC.msg(MacOS::ObjC.klass("NSWorkspace"), "sharedWorkspace")
        application = MacOS::ObjC.msg(workspace, "frontmostApplication")
        next nil if application.null?
        MacOS::ObjC.to_s(MacOS::ObjC.msg(application, "localizedName"))
      end
    rescue
      nil
    end

    def open(target : String, application : String?) : Nil
      success = MacOS::ObjC.pool do
        workspace = MacOS::ObjC.msg(MacOS::ObjC.klass("NSWorkspace"), "sharedWorkspace")
        if application
          MacOS::ObjC.msg(workspace, "openFile:withApplication:", MacOS::ObjC.string(target), MacOS::ObjC.string(application)).address != 0
        else
          url = target.includes?("://") ? MacOS::ObjC.msg(MacOS::ObjC.klass("NSURL"), "URLWithString:", MacOS::ObjC.string(target)) : MacOS::ObjC.msg(MacOS::ObjC.klass("NSURL"), "fileURLWithPath:", MacOS::ObjC.string(target))
          MacOS::ObjC.msg(workspace, "openURL:", url).address != 0
        end
      end
      raise Error.new("failed to open #{target.inspect}", :open_failed) unless success
    end
  end
{% end %}
