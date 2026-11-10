require "log"
require "socket"
require "./string_helpers"
require "./win32_common"

module NativeDesktop::Platform
  class InstanceLock
    ALREADY_EXISTS            =    183_u32
    QUERY_LIMITED_INFORMATION = 0x1000_u32
    STILL_ACTIVE              =    259_u32
    @handle = Pointer(Void).null
    @ipc_server : TCPServer?

    def initialize(@identifier : String, @path : Path)
    end

    def acquire : Bool
      safe = @identifier.gsub(/[^a-zA-Z0-9._-]/, "_")
      name = Windows::StringHelpers.to_utf16("Local\\NativeDesktop.InstanceLock.#{safe}")
      handle = Windows::LibKernel32.CreateMutexW(Pointer(Void).null, 0, name.to_unsafe)
      raise InstanceLockError.new("CreateMutexW failed", :lock_failed) if handle.null?
      if Windows::LibKernel32.GetLastError == ALREADY_EXISTS
        Windows::LibKernel32.CloseHandle(handle)
        false
      else
        @handle = handle
        true
      end
    end

    def release : Nil
      return if @handle.null?
      Windows::LibKernel32.CloseHandle(@handle)
      @handle = Pointer(Void).null
    end

    def cleanup_stale : Bool
      return false unless File.exists?(@path)
      pid = File.read(@path).strip.to_i?
      return false if pid && process_running?(pid)
      File.delete(@path)
      true
    end

    private def process_running?(pid : Int32) : Bool
      return false if pid <= 0
      process = Windows::LibKernel32.OpenProcess(QUERY_LIMITED_INFORMATION, 0, pid.to_u32)
      return false if process.null?
      begin
        code = 0_u32
        Windows::LibKernel32.GetExitCodeProcess(process, pointerof(code)) != 0 && code == STILL_ACTIVE
      ensure
        Windows::LibKernel32.CloseHandle(process)
      end
    end

    # ── IPC (TCP loopback) ──────────────────────────────────────────────────

    MAX_PAYLOAD_SIZE = 65_536
    IPC_TIMEOUT      = 2.seconds

    private def ipc_port : Int32
      hash = @identifier.bytes.reduce(0_u32) { |a, b| (a &* 31) &+ b }
      49152 + (hash % 16383).to_i32
    end

    private def ipc_host_port : String
      "127.0.0.1:#{ipc_port}"
    end

    def start_ipc_server(&handler : String ->) : Nil
      cleanup_ipc
      server = TCPServer.new("127.0.0.1", ipc_port)
      @ipc_server = server
      spawn do
        loop do
          client = server.accept?
          break unless client
          spawn { handle_ipc_client(client, handler) }
        end
      rescue ex
        if @ipc_server.try(&.same?(server))
          Log.error(exception: ex) { "SingleInstance[Windows]: IPC server error" }
        end
      end
    end

    def connect_to_primary(payload : String) : Nil
      socket = TCPSocket.new("127.0.0.1", ipc_port)
      socket.write_timeout = IPC_TIMEOUT
      socket.puts(payload)
      socket.close
    end

    private def handle_ipc_client(client : TCPSocket, handler : String ->) : Nil
      begin
        client.read_timeout = IPC_TIMEOUT
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
    end
  end
end
