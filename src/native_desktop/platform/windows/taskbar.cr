require "./win32_common"
require "./icon_helpers"

module NativeDesktop::Platform::Windows
  class Taskbar
    CLSID_TASKBAR_LIST       = "{56FDF344-FD6D-11d0-958A-006097C9A090}"
    IID_ITASKBAR_LIST3       = "{EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF}"
    COINIT_APARTMENTTHREADED =     0x2_u32
    RPC_E_CHANGED_MODE       = -2147417850

    alias NoArgs = Proc(Void*, Int32)
    alias SetProgressValue = Proc(Void*, Void*, UInt64, UInt64, Int32)
    alias SetProgressState = Proc(Void*, Void*, UInt32, Int32)
    alias SetOverlayIcon = Proc(Void*, Void*, Void*, UInt16*, Int32)

    @object = Pointer(Void).null
    @com_initialized = false
    @cleaned = false
    @window = Pointer(Void).null
    @application_id = nil

    def initialize(@window : Void*, @application_id : String?)
      initialize_com
      create_taskbar
    rescue ex
      cleanup
      raise ex
    end

    def progress=(value : Float64) : Nil
      result = SetProgressValue.new(function(9), Pointer(Void).null).call(@object, @window, (value * 1000).round.to_u64, 1000_u64)
      check(result, "set taskbar progress")
    end

    def state=(state : TaskbarProgressState) : Nil
      native_state = case state
                     in .no_progress?   then 0_u32
                     in .indeterminate? then 1_u32
                     in .normal?        then 2_u32
                     in .error?         then 4_u32
                     in .paused?        then 8_u32
                     end
      check(SetProgressState.new(function(10), Pointer(Void).null).call(@object, @window, native_state), "set taskbar progress state")
    end

    def clear_progress : Nil
      self.state = TaskbarProgressState::NoProgress
    end

    def badge=(text : String?) : Nil
      # Windows has no taskbar text-badge API independent of notifications.
    end

    def overlay_icon=(icon : TaskbarIcon?) : Nil
      handle = IconHelpers.hicon_from_source(icon)
      description = "Taskbar overlay".to_utf16
      begin
        check(SetOverlayIcon.new(function(18), Pointer(Void).null).call(@object, @window, handle, description.to_unsafe), "set taskbar overlay icon")
      ensure
        if icon.try(&.bytes) && !handle.null?
          LibGDI32.DestroyIcon(handle)
        end
      end
    end

    def cleanup : Nil
      return if @cleaned
      @cleaned = true
      unless @object.null?
        clear_progress rescue nil
        self.overlay_icon = nil rescue nil
        IconHelpers.com_release(@object)
        @object = Pointer(Void).null
      end
      if @com_initialized
        LibOLE.CoUninitialize
        @com_initialized = false
      end
    end

    private def initialize_com : Nil
      result = LibOLE.CoInitializeEx(Pointer(Void).null, COINIT_APARTMENTTHREADED)
      if result == RPC_E_CHANGED_MODE
        return
      elsif result < 0
        raise Error.new("could not initialize COM for taskbar integration", :taskbar_unavailable)
      end
      @com_initialized = true
    end

    private def create_taskbar : Nil
      clsid = guid(CLSID_TASKBAR_LIST)
      iid = guid(IID_ITASKBAR_LIST3)
      object = Pointer(Void).null
      result = LibOLE.CoCreateInstance(
        clsid.to_unsafe,
        Pointer(Void).null,
        LibOLE::CLSCTX_INPROC_SERVER,
        iid.to_unsafe,
        pointerof(object)
      )
      check(result, "create the Windows taskbar controller")
      @object = object
      check(NoArgs.new(function(3), Pointer(Void).null).call(@object), "initialize the Windows taskbar controller")
    end

    private def guid(value : String) : Bytes
      bytes = Bytes.new(16, 0_u8)
      wide = value.to_utf16
      check(LibOLE.CLSIDFromString(wide.to_unsafe, bytes.to_unsafe), "parse a taskbar interface identifier")
      bytes
    end

    private def function(index : Int32) : Void*
      vtable = @object.as(Pointer(Void*)).value
      vtable.as(Pointer(Void*))[index]
    end

    private def check(result : Int32, operation : String) : Nil
      raise Error.new("could not #{operation} (HRESULT 0x#{result.to_u32.to_s(16)})", :taskbar_failed) if result < 0
    end
  end
end

NativeDesktop::Capabilities.register(NativeDesktop::Features::TaskbarProgress, NativeDesktop::CapabilityState::Supported)
NativeDesktop::Capabilities.register(
  NativeDesktop::Features::TaskbarBadge,
  NativeDesktop::CapabilityState::Unsupported,
  "the Windows taskbar has no independent text-badge API"
)
NativeDesktop::Capabilities.register(NativeDesktop::Features::TaskbarOverlay, NativeDesktop::CapabilityState::Supported)
