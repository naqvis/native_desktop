module NativeDesktop
  class TrashError < Error
  end

  # Moves files and directories to the operating system's trash.
  module Trash
    extend self

    def move(path : Path | String) : Nil
      value = Path[path].expand.to_s
      unless File.exists?(value) || Dir.exists?(value) || File.symlink?(value)
        raise TrashError.new("file not found: #{value}", :file_not_found)
      end
      Platform::Trash.move(value)
    rescue ex : TrashError
      raise ex
    rescue ex : File::AccessDeniedError
      raise TrashError.new("permission denied: #{value}", :permission_denied, ex)
    rescue ex
      raise TrashError.new("could not move #{value} to trash: #{ex.message}", :trash_failed, ex)
    end
  end
end

{% if flag?(:darwin) %}
  require "./platform/macos/trash"
{% elsif flag?(:linux) %}
  require "./platform/linux/trash"
{% elsif flag?(:windows) %}
  require "./platform/windows/trash"
{% end %}
