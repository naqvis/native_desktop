require "./spec_helper"

# The operating system may deny trash access in headless or sandboxed
# environments (for example, macOS TCC permissions). Skip rather than fail when
# the OS refuses to trash an item that still exists afterwards.
private def trash_or_pending(path : String) : Nil
  NativeDesktop.trash.move(path)
rescue ex : NativeDesktop::TrashError
  if File.exists?(path) || File.symlink?(path)
    pending!("trash unavailable in this environment (#{ex.code})")
  end
  raise ex
end

describe NativeDesktop::Trash do
  it "reports a missing item with a stable error code" do
    path = File.tempname("native-desktop-missing-trash")
    error = expect_raises(NativeDesktop::TrashError) { NativeDesktop.trash.move(path) }
    error.code.should eq(:file_not_found)
  end

  it "moves a file out of its original location" do
    path = File.tempname("native-desktop-trash")
    File.write(path, "trash test")
    trash_or_pending(path)
    File.exists?(path).should be_false
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  {% unless flag?(:windows) %}
    it "trashes a symbolic link without moving its target" do
      directory = File.tempname("native-desktop-trash-link")
      Dir.mkdir(directory)
      target = File.join(directory, "target.txt")
      link = File.join(directory, "link.txt")
      File.write(target, "keep me")
      File.symlink(target, link)

      trash_or_pending(link)

      File.exists?(target).should be_true
      File.symlink?(link).should be_false
    ensure
      File.delete(link) if link && File.symlink?(link)
      File.delete(target) if target && File.exists?(target)
      Dir.delete(directory) if directory && Dir.exists?(directory)
    end
  {% end %}
end
