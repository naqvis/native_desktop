require "log"
require "socket"

module NativeDesktop::Platform
  class InstanceLock
    @file : File?
    @ipc_server : UNIXServer?

    def initialize(@identifier : String, @path : Path)
    end

    def acquire : Bool
      file = File.open(@path, "a+")
      unless LibC.flock(file.fd, LibC::FlockOp::EX | LibC::FlockOp::NB) == 0
        error = Errno.value
        file.close
        return false if error == Errno::EWOULDBLOCK || error == Errno::EAGAIN
        raise InstanceLockError.new("flock failed: #{error.message}", :lock_failed)
      end

      begin
        file.truncate(0)
        file.rewind
        file.print(Process.pid)
        file.flush
        @file = file
        true
      rescue ex
        LibC.flock(file.fd, LibC::FlockOp::UN)
        file.close
        raise ex
      end
    end

    def release : Nil
      return unless file = @file
      File.delete(@path) if File.exists?(@path)
      LibC.flock(file.fd, LibC::FlockOp::UN)
      file.close
      @file = nil
    end

    def cleanup_stale : Bool
      return false unless File.exists?(@path)
      file = File.open(@path, "a+")
      return false unless LibC.flock(file.fd, LibC::FlockOp::EX | LibC::FlockOp::NB) == 0
      begin
        file.rewind
        if (pid = file.gets.try(&.strip.to_i?)) && process_running?(pid)
          return false
        end
        File.delete(@path) if File.exists?(@path)
        true
      ensure
        LibC.flock(file.fd, LibC::FlockOp::UN)
        file.close
      end
    end

    private def process_running?(pid : Int32) : Bool
      return false if pid <= 0
      return true if LibC.kill(pid, 0) == 0
      Errno.value == Errno::EPERM
    end

    # ── IPC (Unix domain socket) ────────────────────────────────────────────

    MAX_PAYLOAD_SIZE = 65_536

    private def ipc_socket_path : String
      hash = @identifier.bytes.reduce(0_u32) { |a, b| (a &* 31) &+ b }
      (Path[Dir.tempdir] / "nd_si_#{hash.to_s(36)}.sock").to_s
    end

    def start_ipc_server(&handler : String ->) : Nil
      cleanup_ipc
      path = ipc_socket_path
      File.delete(path) if File.exists?(path)
      server = UNIXServer.new(path)
      @ipc_server = server
      spawn do
        loop do
          client = server.accept?
          break unless client
          spawn { handle_ipc_client(client, handler) }
        end
      rescue ex
        if @ipc_server.try(&.same?(server))
          Log.error(exception: ex) { "SingleInstance[Unix]: IPC server error" }
        end
      end
    end

    def connect_to_primary(payload : String) : Nil
      socket = UNIXSocket.new(ipc_socket_path)
      socket.puts(payload)
      socket.close
    end

    private def handle_ipc_client(client : UNIXSocket, handler : String ->) : Nil
      begin
        line = client.gets(MAX_PAYLOAD_SIZE)
        handler.call(line.chomp) if line && !line.empty?
      ensure
        client.close
      end
    end

    def cleanup_ipc : Nil
      server = @ipc_server
      @ipc_server = nil
      server.try(&.close)
      path = ipc_socket_path
      File.delete(path) if File.exists?(path)
    end
  end
end
