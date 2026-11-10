{% if flag?(:darwin) %}
  require "file_utils"

  module NativeDesktop::Platform::FileAssociations
    @[Link(framework: "CoreServices")]
    @[Link(framework: "CoreFoundation")]
    lib LibLaunchServicesFileAssocs
      fun CFURLCreateFromFileSystemRepresentation(allocator : Void*, bytes : UInt8*, length : LibC::Long, directory : Int8) : Void*
      fun CFRelease(value : Void*) : Nil
      fun LSRegisterURL(url : Void*, update : Int8) : Int32
      fun unregister_url = _LSUnregisterURL(url : Void*) : Int32
    end

    extend self
    BUNDLES_DIR = Path.home / "Library" / "Application Support" / "native_desktop" / "file-types"

    def register(association : NativeDesktop::FileAssociation) : Nil
      bundle = bundle_for(association)
      contents = bundle / "Contents"
      binaries = contents / "MacOS"
      Dir.mkdir_p(binaries)

      launcher_name = "#{association.resource_key}-handler"
      File.write(contents / "Info.plist", plist(association, launcher_name))
      launcher = binaries / launcher_name
      File.delete(launcher) if File.exists?(launcher) || File.symlink?(launcher)
      File.symlink(association.executable, launcher)
      register_bundle(bundle)
    rescue ex : NativeDesktop::Error
      raise ex
    rescue ex
      raise NativeDesktop::Error.new("failed to register file type #{association.extension.inspect}: #{ex.message}", :file_association_failed)
    end

    def unregister(association : NativeDesktop::FileAssociation) : Nil
      bundle = bundle_for(association)
      return unless Dir.exists?(bundle)

      with_bundle_url(bundle) do |url|
        status = LibLaunchServicesFileAssocs.unregister_url(url)
        unless status == 0
          raise NativeDesktop::Error.new("Launch Services unregistration failed (#{status})", :file_association_failed)
        end
      end
      FileUtils.rm_rf(bundle)
      Dir.delete(bundle.parent) if Dir.empty?(bundle.parent)
    rescue ex : NativeDesktop::Error
      raise ex
    rescue ex
      raise NativeDesktop::Error.new("failed to unregister file type #{association.extension.inspect}: #{ex.message}", :file_association_failed)
    end

    # :nodoc:
    def bundle_for(association : NativeDesktop::FileAssociation) : Path
      BUNDLES_DIR / association.application_id / "#{association.resource_key}-handler.app"
    end

    # :nodoc:
    def plist(association : NativeDesktop::FileAssociation, launcher : String) : String
      escaped_application_name = xml(association.application_name)
      escaped_type_name = xml(association.type_name)
      escaped_ext = xml(association.extension.lstrip('.'))
      escaped_mime = xml(association.mime_type)
      escaped_launcher = xml(launcher)
      escaped_identifier = xml("#{association.application_id}.native-desktop.#{association.extension.lstrip('.').gsub('.', '-')}")
      <<-XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>#{escaped_identifier}</string>
        <key>CFBundleName</key><string>#{escaped_application_name}</string>
        <key>CFBundleExecutable</key><string>#{escaped_launcher}</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSUIElement</key><true/>
        <key>CFBundleDocumentTypes</key><array><dict>
          <key>CFBundleTypeName</key><string>#{escaped_type_name}</string>
          <key>CFBundleTypeRole</key><string>Viewer</string>
          <key>LSHandlerRank</key><string>Alternate</string>
          <key>CFBundleTypeExtensions</key><array><string>#{escaped_ext}</string></array>
          <key>CFBundleTypeMIMETypes</key><array><string>#{escaped_mime}</string></array>
        </dict></array>
      </dict></plist>
      XML
    end

    private def xml(value : String) : String
      value.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;").gsub('"', "&quot;").gsub('\'', "&apos;")
    end

    private def register_bundle(bundle : Path) : Nil
      with_bundle_url(bundle) do |url|
        status = LibLaunchServicesFileAssocs.LSRegisterURL(url, 1_i8)
        raise NativeDesktop::Error.new("Launch Services registration failed (#{status})", :file_association_failed) unless status == 0
      end
    end

    private def with_bundle_url(bundle : Path, & : Void* ->) : Nil
      bytes = bundle.to_s.to_slice
      url = LibLaunchServicesFileAssocs.CFURLCreateFromFileSystemRepresentation(Pointer(Void).null, bytes.to_unsafe, bytes.size, 1_i8)
      raise NativeDesktop::Error.new("could not create bundle URL", :file_association_failed) if url.null?
      begin
        yield url
      ensure
        LibLaunchServicesFileAssocs.CFRelease(url)
      end
    end
  end
{% end %}
