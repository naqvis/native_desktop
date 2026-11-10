# Host Integration

`native_desktop` works with GUI hosts that already create native windows and run a platform event loop. It does not create an application object, choose a WebView, or start an event loop.

## Attach the runtime

Attach from the GUI thread and provide a dispatcher that enqueues work on that thread:

```crystal
require "native_desktop"

worker_context = Fiber::ExecutionContext::Parallel.new(
  "native-desktop-workers",
  maximum: 4
)

background = ->(work : Proc(Nil)) do
  worker_context.spawn { work.call }
  nil
end

NativeDesktop::Runtime.attach_to_current_thread(background: background) do |work|
  host_window.dispatch { work.call }
end
```

The dispatcher is a host integration point. Platform selection is automatic and is not application configuration.

Calls made on the attached GUI thread run immediately. Calls from other execution contexts are dispatched to the GUI thread and suspend the calling fiber until the operation completes. Detaching the runtime rejects pending and later GUI work with `NativeDesktop::RuntimeError`.

Only one runtime attachment may be active. A second attachment raises `NativeDesktop::RuntimeError` with code `:already_attached`.

## Background execution

The background executor is used by services that wait for native activity or poll operating-system state:

- global shortcuts
- theme monitoring
- power monitoring
- idle monitoring
- speech-recognition event polling

Callbacks from those services, including speech-recognition result, error, and end handlers, run on the background executor. A callback that updates the interface must dispatch that update through the host’s GUI loop.

The host owns the background execution context. Keep it alive until all services using it have stopped.

## Attach existing windows

`NativeDesktop::Window` is a non-owning reference to a host-created window:

```crystal
window = NativeDesktop::Window.attach(host_window.native_handle)
window.always_on_top = true
window.opacity = 0.9
```

The handle represents:

| Platform | Native handle |
| --- | --- |
| macOS | `NSWindow*` |
| Linux | `GtkWindow*` |
| Windows | `HWND` |

A null handle is rejected. The host must keep the underlying native window alive while a `Window`, `Toolbar`, `Taskbar`, `Kiosk`, `DragSource`, application menu, or context-menu operation may use it.

Destroying a `NativeDesktop::Window` value does not destroy the native window.

## Windows message forwarding

Windows hosts must offer each native `MSG` to the runtime before normal translation and dispatch:

```crystal
if NativeDesktop::Runtime.process_event(message_pointer)
  # The native service consumed the message.
else
  # Continue with TranslateMessage and DispatchMessage.
end
```

This is required by native services such as application menus and global shortcuts. `process_event` returns `false` on macOS and Linux, so a host may call it from shared event-loop code.

The same forwarding reports Windows power, session, and shutdown messages to `NativeDesktop.session`. The session backend registers each forwarded window for `WM_WTSSESSION_CHANGE` the first time it sees that window.

## Activations and drop targets

The shard installs the native Apple-event source on macOS and argument source on Linux and Windows. A host can add another `ActivationSource` for toolkit-specific callbacks:

```crystal
NativeDesktop.activations.install(host_activation_source)
```

Events received before `on_event` is installed are queued and replayed. A host may classify command-line arguments without placing that policy in the shard:

```crystal
NativeDesktop.activations.capture_arguments(ARGV) do |argument|
  host_activation_for(argument)
end
```

`NativeDesktop::DropTarget` applies common payload filtering and lifecycle through the platform's default `DropTargetAdapter`. A toolkit may supply a replacement adapter directly or register a scoped provider through `NativeDesktop::DropTargets.register`. Closing that registration reveals the previous provider, so integrations compose without naming or replacing a concrete platform class.

## Event-loop timing

Some controls can only be installed after the host event loop is active. Application menus expose this without requiring a platform branch:

```crystal
if NativeDesktop.application_menus.requires_running_event_loop?
  host_window.dispatch { install_menu }
else
  install_menu
end
```

## Shutdown

Release resources in this order:

1. Stop `ThemeMonitor`, `PowerMonitor`, and `IdleMonitor`.
2. Stop and clean up `GlobalShortcuts`.
3. Clean up speech synthesizers and recognizers, drag sources, toolbars, taskbar controllers, and kiosk controllers.
4. Destroy the tray and release application-owned single-instance resources.
5. Call `NativeDesktop::Runtime.detach`.
6. Destroy native windows.
7. Stop the host’s background execution context and GUI loop.

```crystal
NativeDesktop::Runtime.detach
```

Detaching before owned services stop makes later GUI-bound cleanup fail. Destroying a native window before its attached controls are released leaves those controls with an invalid non-owning handle.
