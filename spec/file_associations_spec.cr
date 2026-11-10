require "./spec_helper"

private def file_association_fixture(
  application_id = "dev.example.editor",
  application_name = "Example Editor",
  extension = ".md",
  type_name = "Markdown Document",
  mime_type = "text/markdown",
  executable = (Path[Dir.current] / "example-editor").expand,
  description : String? = "A Markdown source file",
)
  NativeDesktop::FileAssociation.new(
    application_id: application_id,
    application_name: application_name,
    extension: extension,
    type_name: type_name,
    mime_type: mime_type,
    executable: executable,
    description: description
  )
end

describe NativeDesktop::FileAssociations do
  it "normalizes identifiers used by every platform" do
    value = file_association_fixture(
      application_id: " DEV.Example.Editor ",
      extension: " MD ",
      mime_type: " TEXT/MARKDOWN "
    )

    value.application_id.should eq("dev.example.editor")
    value.extension.should eq(".md")
    value.mime_type.should eq("text/markdown")
    value.resource_key.should eq("dev.example.editor-md")
  end

  it "rejects invalid application identifiers" do
    ["", "editor", ".editor", "dev..editor", "dev.example_editor", "dev/example", "dev.example-"].each do |application_id|
      expect_raises(ArgumentError) do
        file_association_fixture(application_id: application_id)
      end
    end
  end

  it "rejects invalid extensions" do
    ["", ".", "..", "with space", ".md/other", ".md_"].each do |extension|
      expect_raises(ArgumentError) { file_association_fixture(extension: extension) }
    end
  end

  it "rejects malformed MIME types" do
    ["", "text", "/plain", "text/", "text/plain other", "text/*"].each do |mime_type|
      expect_raises(ArgumentError) { file_association_fixture(mime_type: mime_type) }
    end
  end

  it "rejects invalid display text and executable paths" do
    expect_raises(ArgumentError) { file_association_fixture(application_name: " ") }
    expect_raises(ArgumentError) { file_association_fixture(type_name: "Markdown\nDocument") }
    expect_raises(ArgumentError) { file_association_fixture(description: "Markdown\u0000Document") }
    expect_raises(ArgumentError) { file_association_fixture(executable: Path["relative/editor"]) }
    invalid_executable = (Path[Dir.current] / "example\neditor").expand
    expect_raises(ArgumentError) { file_association_fixture(executable: invalid_executable) }
  end

  it "keeps registrations from different applications isolated" do
    first = file_association_fixture(application_id: "dev.example.first")
    second = file_association_fixture(application_id: "dev.example.second")

    first.resource_key.should_not eq(second.resource_key)
  end

  {% if flag?(:darwin) %}
    it "generates an alternate Launch Services handler owned by the application" do
      value = file_association_fixture(application_name: "Editor & Viewer", type_name: "Markdown <Document>")
      plist = NativeDesktop::Platform::FileAssociations.plist(value, "editor-handler")

      plist.should contain("<string>dev.example.editor.native-desktop.md</string>")
      plist.should contain("<string>Editor &amp; Viewer</string>")
      plist.should contain("<string>Markdown &lt;Document&gt;</string>")
      plist.should contain("<key>CFBundleTypeRole</key><string>Viewer</string>")
      plist.should contain("<key>LSHandlerRank</key><string>Alternate</string>")
    end

    it "uses distinct bundle locations for distinct applications" do
      first = NativeDesktop::Platform::FileAssociations.bundle_for(file_association_fixture(application_id: "dev.example.first"))
      second = NativeDesktop::Platform::FileAssociations.bundle_for(file_association_fixture(application_id: "dev.example.second"))

      first.should_not eq(second)
    end
  {% elsif flag?(:linux) %}
    it "generates an application-owned desktop entry without claiming the default" do
      value = file_association_fixture(
        application_name: "Example Editor",
        executable: Path["/opt/Example Editor/$editor"]
      )
      entry = NativeDesktop::Platform::FileAssociations.desktop_entry(value)

      entry.should contain("Name=Example Editor")
      entry.should contain("Exec=\"/opt/Example Editor/\\$editor\" %f")
      entry.should contain("MimeType=text/markdown;")
    end

    it "uses distinct desktop files for distinct applications" do
      first = NativeDesktop::Platform::FileAssociations.desktop_file(file_association_fixture(application_id: "dev.example.first"))
      second = NativeDesktop::Platform::FileAssociations.desktop_file(file_association_fixture(application_id: "dev.example.second"))

      first.should_not eq(second)
    end
  {% elsif flag?(:windows) %}
    it "uses an application-owned ProgID" do
      first = NativeDesktop::Platform::FileAssociations.prog_id(file_association_fixture(application_id: "dev.example.first"))
      second = NativeDesktop::Platform::FileAssociations.prog_id(file_association_fixture(application_id: "dev.example.second"))

      first.should match(/\ANativeDesktop\.[a-f0-9]{24}\z/)
      first.bytesize.should be <= 39
      first.should_not eq(second)
    end
  {% end %}
end
