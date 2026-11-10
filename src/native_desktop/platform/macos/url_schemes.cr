{% if flag?(:darwin) %}
  require "file_utils"

  module NativeDesktop::Platform::URLSchemes
    extend self
    BUNDLES_DIR = Path.home / "Library" / "Application Support" / "native_desktop" / "url-schemes"

    @[Link(framework: "CoreServices")]
    @[Link(framework: "CoreFoundation")]
    lib LibLaunchServicesURLSchemes
      fun CFURLCreateFromFileSystemRepresentation(allocator : Void*, bytes : UInt8*, length : LibC::Long, directory : Int8) : Void*
      fun CFRelease(value : Void*) : Nil
      fun LSRegisterURL(url : Void*, update : Int8) : Int32
    end

    def register(scheme : String, name : String, executable : Path) : Nil
      bundle = bundle_for(scheme)
      contents = bundle / "Contents"
      binaries = contents / "MacOS"
      Dir.mkdir_p(binaries)

      launcher_name = "native-desktop-#{scheme}-handler"
      File.write(contents / "Info.plist", plist(scheme, name, launcher_name))
      launcher = binaries / launcher_name
      File.delete(launcher) if File.exists?(launcher) || File.symlink?(launcher)
      File.symlink(executable, launcher)
      register_bundle(bundle)
    rescue ex : Error
      raise ex
    rescue ex
      raise Error.new("failed to register URL scheme #{scheme.inspect}: #{ex.message}", :url_scheme_registration_failed)
    end

    def unregister(scheme : String) : Nil
      bundle = bundle_for(scheme)
      FileUtils.rm_rf(bundle) if Dir.exists?(bundle)
    rescue ex
      raise Error.new("failed to unregister URL scheme #{scheme.inspect}: #{ex.message}", :url_scheme_registration_failed)
    end

    private def bundle_for(scheme : String) : Path
      BUNDLES_DIR / "#{scheme}-handler.app"
    end

    private def plist(scheme : String, name : String, launcher : String) : String
      escaped_name = xml(name)
      escaped_scheme = xml(scheme)
      <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>org.crystal.native-desktop.url-scheme.#{escaped_scheme}</string>
        <key>CFBundleName</key><string>#{escaped_name}</string>
        <key>CFBundleExecutable</key><string>#{launcher}</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleURLTypes</key><array><dict>
          <key>CFBundleURLName</key><string>#{escaped_name} URL Handler</string>
          <key>CFBundleURLSchemes</key><array><string>#{escaped_scheme}</string></array>
        </dict></array>
        <key>LSUIElement</key><true/>
      </dict></plist>
      XML
    end

    private def xml(value : String) : String
      value.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;").gsub('"', "&quot;").gsub('\'', "&apos;")
    end

    private def register_bundle(bundle : Path) : Nil
      bytes = bundle.to_s.to_slice
      url = LibLaunchServicesURLSchemes.CFURLCreateFromFileSystemRepresentation(Pointer(Void).null, bytes.to_unsafe, bytes.size, 1_i8)
      raise Error.new("could not create bundle URL", :url_scheme_registration_failed) if url.null?
      begin
        status = LibLaunchServicesURLSchemes.LSRegisterURL(url, 1_i8)
        raise Error.new("Launch Services registration failed (#{status})", :url_scheme_registration_failed) unless status == 0
      ensure
        LibLaunchServicesURLSchemes.CFRelease(url)
      end
    end
  end
{% end %}
