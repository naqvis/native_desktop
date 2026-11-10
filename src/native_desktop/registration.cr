module NativeDesktop
  # Idempotent ownership token returned by extensible registries.
  class Registration
    @lock = Mutex.new
    @close_action : Proc(Nil)?

    def initialize(&close_action : ->)
      @close_action = close_action
    end

    def close : Nil
      action = @lock.synchronize do
        value = @close_action
        @close_action = nil
        value
      end
      action.try(&.call)
    end

    def closed? : Bool
      @lock.synchronize { @close_action.nil? }
    end
  end
end
