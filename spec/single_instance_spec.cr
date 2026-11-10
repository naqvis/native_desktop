require "./spec_helper"

private def instance_lock_id : String
  "native-desktop.spec.#{Process.pid}.#{Random.rand(1_000_000)}"
end

describe NativeDesktop::InstanceLock do
  it "excludes another lock with the same identifier" do
    identifier = instance_lock_id
    primary = NativeDesktop.instance_lock(identifier)
    secondary = NativeDesktop.instance_lock(identifier)
    begin
      primary.acquire.should be_true
      secondary.acquire.should be_false
      primary.acquired?.should be_true
      secondary.acquired?.should be_false
    ensure
      secondary.release
      primary.release
    end
  end

  it "allows acquisition after release" do
    identifier = instance_lock_id
    first = NativeDesktop.instance_lock(identifier)
    second = NativeDesktop.instance_lock(identifier)
    first.acquire.should be_true
    first.release
    begin
      second.acquire.should be_true
    ensure
      second.release
    end
  end

  it "closes and restarts its IPC listener" do
    lock = NativeDesktop.instance_lock(instance_lock_id)
    received = Channel(String).new(1)
    begin
      lock.start_ipc_server { |payload| received.send(payload) }
      lock.connect_to_primary("first")
      received.receive.should eq("first")
      lock.cleanup_ipc

      lock.start_ipc_server { |payload| received.send(payload) }
      lock.connect_to_primary("second")
      received.receive.should eq("second")
    ensure
      lock.cleanup_ipc
    end
  end

  {% unless flag?(:windows) %}
    it "does not truncate the owner's PID when acquisition fails" do
      identifier = instance_lock_id
      primary = NativeDesktop.instance_lock(identifier)
      secondary = NativeDesktop.instance_lock(identifier)
      begin
        primary.acquire.should be_true
        File.read(primary.path).should eq(Process.pid.to_s)
        secondary.acquire.should be_false
        File.read(primary.path).should eq(Process.pid.to_s)
      ensure
        secondary.release
        primary.release
      end
    end

    it "removes an unlocked stale file" do
      lock = NativeDesktop.instance_lock(instance_lock_id)
      File.write(lock.path, "stale")
      lock.cleanup_stale.should be_true
      File.exists?(lock.path).should be_false
    ensure
      File.delete(lock.path) if lock && File.exists?(lock.path)
    end
  {% end %}
end
