module NativeDesktop
  record ApplicationIdentity,
    id : String,
    name : String,
    executable : Path do
    def initialize(@id : String, @name : String, @executable : Path)
      raise ArgumentError.new("application ID cannot be empty") if @id.strip.empty?
      raise ArgumentError.new("application name cannot be empty") if @name.strip.empty?
      raise ArgumentError.new("application executable must be absolute") unless @executable.absolute?
    end
  end

  record Diagnostic,
    id : String,
    message : String,
    feature : FeatureId? = nil,
    state : CapabilityState? = nil

  module Application
    extend self
    alias DiagnosticProvider = Proc(Array(Diagnostic))
    @@lock = Mutex.new
    @@identity : ApplicationIdentity?
    @@diagnostic_providers = {} of String => DiagnosticProvider

    def configure(identity : ApplicationIdentity) : Nil
      @@lock.synchronize { @@identity = identity }
    end

    def identity : ApplicationIdentity?
      @@lock.synchronize { @@identity }
    end

    def register_diagnostics(id : String, &provider : -> Array(Diagnostic)) : Nil
      raise ArgumentError.new("diagnostic provider identifier cannot be empty") if id.strip.empty?
      @@lock.synchronize { @@diagnostic_providers[id] = provider }
    end

    def unregister_diagnostics(id : String) : Nil
      @@lock.synchronize { @@diagnostic_providers.delete(id) }
    end

    def diagnostics : Array(Diagnostic)
      providers = @@lock.synchronize { @@diagnostic_providers.values.dup }
      providers.flat_map(&.call)
    end
  end
end

NativeDesktop::Application.register_diagnostics("native-desktop.capabilities") do
  NativeDesktop::Capabilities.all.compact_map do |capability|
    next if capability.supported?
    NativeDesktop::Diagnostic.new(
      "capability.#{capability.feature}",
      capability.reason || "feature is not available",
      capability.feature,
      capability.state
    )
  end
end

NativeDesktop::Application.register_diagnostics("native-desktop.identity") do
  if NativeDesktop::Application.identity
    [] of NativeDesktop::Diagnostic
  else
    [NativeDesktop::Diagnostic.new(
      "application.identity",
      "application identity has not been configured"
    )]
  end
end
