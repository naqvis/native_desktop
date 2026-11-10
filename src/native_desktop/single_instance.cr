module NativeDesktop
  class InstanceLockError < Error
  end

  # An owned, process-scoped application instance lock.
  class InstanceLock
    getter identifier : String
    getter path : Path

    @mutex = Mutex.new
    @platform : Platform::InstanceLock
    @acquired = false

    def initialize(@identifier : String, directory : Path | String = Path[Dir.tempdir])
      raise ArgumentError.new("identifier cannot be empty") if @identifier.empty?
      safe = @identifier.gsub(/[^a-zA-Z0-9._-]/, "_")
      @path = Path[directory] / "#{safe}.lock"
      @platform = Platform::InstanceLock.new(@identifier, @path)
    end

    # Attempts to acquire the lock without waiting.
    def acquire : Bool
      @mutex.synchronize do
        return true if @acquired
        @acquired = @platform.acquire
      end
    rescue ex : InstanceLockError
      raise ex
    rescue ex
      raise InstanceLockError.new("could not acquire instance lock: #{ex.message}", :lock_failed, ex)
    end

    def acquired? : Bool
      @mutex.synchronize { @acquired }
    end

    # Releases the lock. Calling this more than once is safe.
    def release : Nil
      @mutex.synchronize do
        return unless @acquired
        @platform.release
        @acquired = false
      end
    end

    # Removes an unlocked lock file left by an earlier process.
    def cleanup_stale : Bool
      @mutex.synchronize { @platform.cleanup_stale }
    end

    # ── IPC delegation ───────────────────────────────────────────────────────

    def start_ipc_server(&handler : String ->) : Nil
      @platform.start_ipc_server { |payload| handler.call(payload) }
    end

    def connect_to_primary(payload : String) : Nil
      @platform.connect_to_primary(payload)
    end

    def cleanup_ipc : Nil
      @platform.cleanup_ipc
    end
  end

  # Creates an owned lock for an application identifier.
  def self.instance_lock(identifier : String, directory : Path | String = Path[Dir.tempdir]) : InstanceLock
    InstanceLock.new(identifier, directory)
  end

  # High-level single-instance manager wrapping lock + platform IPC.
  class SingleInstance
    @lock : InstanceLock

    def initialize(@name : String, directory : Path | String = Path[Dir.tempdir])
      @lock = InstanceLock.new(@name, directory)
    end

    def first? : Bool
      @lock.acquire
    end

    def listen(&handler : String ->) : Nil
      return unless @lock.acquired?
      @lock.start_ipc_server { |payload| handler.call(payload) }
    end

    # Routes second-instance payloads into the shared activation stream.
    def listen_activations : Nil
      listen { |payload| Activations.emit(Activation.second_instance(payload)) }
    end

    def send(payload : String) : Nil
      @lock.connect_to_primary(payload)
    end

    def cleanup : Nil
      @lock.release
      @lock.cleanup_ipc
    end
  end
end

{% if flag?(:windows) %}
  require "./platform/windows/single_instance"
{% elsif flag?(:darwin) %}
  require "./platform/macos/single_instance"
{% elsif flag?(:linux) %}
  require "./platform/linux/single_instance"
{% end %}
