require "file_utils"
require "uri"

module NativeDesktop::Platform::Trash
  extend self

  TRASH_DIR_MODE  = 0o700
  TRASH_INFO_MODE = 0o600
  @@lock = Mutex.new

  def move(path : String) : Nil
    @@lock.synchronize { move_locked(path) }
  end

  private def move_locked(path : String) : Nil
    trash_root, recorded_path = destination_for(path)
    files = File.join(trash_root, "files")
    info = File.join(trash_root, "info")
    ensure_directories(files, info)

    name = unique_name(files, info, File.basename(path))
    destination = File.join(files, name)
    metadata = File.join(info, "#{name}.trashinfo")
    temporary = File.join(info, ".#{name}.#{Process.pid}.#{Time.utc.to_unix_ms}.tmp")

    begin
      File.write(temporary, trash_info(recorded_path))
      File.chmod(temporary, TRASH_INFO_MODE)
      File.rename(temporary, metadata)
      begin
        FileUtils.mv(path, destination)
      rescue ex
        File.delete(metadata) rescue nil
        raise ex
      end
    ensure
      File.delete(temporary) if File.exists?(temporary)
    end
  end

  private def destination_for(path : String) : {String, String}
    home = ENV["HOME"]? || "/tmp"
    if device_id(path) == device_id(home)
      return {home_trash(home), path}
    end

    top = volume_root(path)
    root = volume_trash(top)
    relative = Path[path].relative_to(Path[top]).to_s
    {root, relative}
  end

  private def home_trash(home : String) : String
    data = ENV["XDG_DATA_HOME"]?
    data && Path[data].absolute? ? File.join(data, "Trash") : File.join(home, ".local", "share", "Trash")
  end

  private def volume_trash(top : String) : String
    uid = LibC.getuid
    shared = File.join(top, ".Trash")
    if valid_shared_parent?(shared)
      return File.join(shared, uid.to_s)
    end
    File.join(top, ".Trash-#{uid}")
  end

  private def valid_shared_parent?(path : String) : Bool
    return false unless Dir.exists?(path)
    return false if File.symlink?(path)
    info = File.info(path, follow_symlinks: false)
    info.directory? && (info.permissions.value & 0o1000) != 0 && info.@stat.st_uid == 0
  rescue
    false
  end

  private def volume_root(path : String) : String
    current = path
    device = device_id(current)
    loop do
      parent = File.dirname(current)
      return current if parent == current
      return current if device_id(parent) != device
      current = parent
    end
  end

  private def device_id(path : String) : UInt64
    File.info(path, follow_symlinks: false).@stat.st_dev.to_u64
  rescue File::NotFoundError
    device_id(File.dirname(path))
  end

  private def ensure_directories(files : String, info : String) : Nil
    FileUtils.mkdir_p(files)
    FileUtils.mkdir_p(info)
    File.chmod(files, TRASH_DIR_MODE)
    File.chmod(info, TRASH_DIR_MODE)
  end

  private def unique_name(files : String, info : String, basename : String) : String
    candidate = basename
    suffix = 1
    while File.exists?(File.join(files, candidate)) ||
          Dir.exists?(File.join(files, candidate)) ||
          File.symlink?(File.join(files, candidate)) ||
          File.exists?(File.join(info, "#{candidate}.trashinfo"))
      candidate = "#{basename}.#{suffix}"
      suffix += 1
    end
    candidate
  end

  private def trash_info(original : String) : String
    String.build do |io|
      io << "[Trash Info]\n"
      io << "Path=" << URI.encode_path(original) << '\n'
      io << "DeletionDate=" << Time.local.to_s("%Y-%m-%dT%H:%M:%S") << '\n'
    end
  end
end
