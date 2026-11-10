# native_desktop

`native_desktop` provides host-neutral access to native desktop controls for Crystal applications. It enhances windows created by an existing GUI host and supplies process-wide operating-system services without taking over application lifecycle, creating a window, or running a competing event loop.

Supported platforms:

- macOS
- Linux with GTK 3
- Windows

The shard provides:

- non-owning native window references
- always-on-top behavior, titlebar overlays, and platform window effects
- connected-display names, geometry, work areas, scale factors, and pointer position
- foreground application name where the window system exposes it
- per-user custom URL-scheme registration
- per-user login autostart entries
- open, save, folder, message, and confirmation dialogs
- text, HTML, RTF, and image clipboard access
- desktop notifications with urgency, timeout, icon, and action metadata
- native popup context menus with separators, checkboxes, and nested submenus
- system tray icons, tooltips, click callbacks, and nested tray menus
- application menu bars with nested menus, checked state, callbacks, and keyboard accelerators
- window toolbars with buttons, toggles, dropdowns, color controls, separators, and icons
- system-wide keyboard shortcuts with dynamic registration and common punctuation keys
- taskbar or Dock progress, badges, and overlay icons where supported
- reversible kiosk-style window presentation with prior-state restoration
- system light/dark appearance detection and change monitoring
- battery level, charging state, external-power state, and change monitoring
- user idle duration and active/idle transition monitoring
- aggregate CPU counters and thread-safe utilization sampling
- owned text-to-speech engines with installed voice discovery and playback controls
- operating-system speech recognition with supported-language discovery, permissions, and partial or final results
- biometric capability detection and native authentication prompts
- recoverable file and directory deletion through the system trash
- connected Bluetooth, USB, serial, and HID device enumeration
- process-scoped single-instance application locks
- native file, image-file, text, and URL drag sources
- host-integrated drop targets with typed payload filtering
- per-user file extension and MIME type registration
- explicit per-feature capability and permission discovery
- queued URL, file-open, and second-instance activations
- notification activation, action, dismissal, and failure events
- display, clipboard, and hardware change monitors
- suspend, resume, session lock, unlock, and shutdown events
- application identity and integration diagnostics

All platform selection is automatic. Applications work with the same API on every supported operating system and do not construct or select platform backends.

## API overview

| Area                     | Entry point                                  | Requires attached GUI runtime |
| ------------------------ | -------------------------------------------- | ----------------------------: |
| Native window controls   | `NativeDesktop::Window`                      |                           Yes |
| Window effects           | `NativeDesktop::Window#apply`                |                           Yes |
| Displays and pointer     | `NativeDesktop.displays`                     |                           Yes |
| Clipboard                | `NativeDesktop.clipboard`                    |                           Yes |
| File and message dialogs | `NativeDesktop.dialogs`                      |                           Yes |
| Foreground application   | `NativeDesktop.applications.foreground_name` |                            No |
| Open URL or path         | `NativeDesktop.applications.open`            |                            No |
| URL-scheme registration  | `NativeDesktop.url_schemes`                  |                            No |
| Login autostart          | `NativeDesktop.autostart`                    |                            No |
| Desktop notifications    | `NativeDesktop.notifications`                |                           Yes |
| Context menus            | `NativeDesktop.context_menus`                |                           Yes |
| System tray              | `NativeDesktop.tray`                         |                           Yes |
| Application menus        | `NativeDesktop.application_menus`            |                           Yes |
| Window toolbars          | `NativeDesktop::Toolbar`                     |                           Yes |
| Global shortcuts         | `NativeDesktop::GlobalShortcuts`             |                           Yes |
| Taskbar and Dock status  | `NativeDesktop::Taskbar`                     |                           Yes |
| Kiosk presentation       | `NativeDesktop::Kiosk`                       |                           Yes |
| System appearance        | `NativeDesktop.system_theme`                 |               Only to monitor |
| Battery and power        | `NativeDesktop.power`                        |               Only to monitor |
| User idle time           | `NativeDesktop.idle`                         |               Only to monitor |
| CPU utilization          | `NativeDesktop.cpu`                          |                            No |
| Speech synthesis         | `NativeDesktop.speech`                       |                           Yes |
| Speech recognition       | `NativeDesktop.speech_recognizer`            |                           Yes |
| Biometric authentication | `NativeDesktop.biometric`                    |                            No |
| Trash or Recycle Bin     | `NativeDesktop.trash`                        |                            No |
| Hardware enumeration     | `NativeDesktop.hardware`                     |                            No |
| Single-instance lock     | `NativeDesktop.instance_lock`                |                            No |
| Native drag source       | `NativeDesktop::DragSource`                  |                           Yes |
| File type associations   | `NativeDesktop.file_associations`            |                            No |
| Capabilities             | `NativeDesktop.capabilities`                 |                            No |
| Permissions              | `NativeDesktop.permissions`                  |               Only to request |
| Application identity     | `NativeDesktop.application`                  |                            No |
| Activation delivery      | `NativeDesktop.activations`                  |                            No |
| Session lifecycle        | `NativeDesktop.session`                      |      Windows event forwarding |
| Native drop target       | `NativeDesktop::DropTarget`                  |                           Yes |

## Capabilities, permissions, and diagnostics

Desktop support can depend on the operating system, session type, permissions, and host integration. Query it before exposing a feature:

```crystal
capability = NativeDesktop.capabilities.status(
  NativeDesktop::Features::TaskbarProgress
)

unless capability.supported?
  puts capability.reason
end
```

`CapabilityState` distinguishes `Supported`, `Unsupported`, `Unavailable`, `PermissionRequired`, and `HostIntegrationRequired`. Permission preflight, requests, and settings links are available through `NativeDesktop.permissions`.

Feature and permission identifiers are open value objects. An extension shard can register support without modifying `native_desktop`:

```crystal
feature = NativeDesktop::FeatureId["vendor.feature"]
NativeDesktop.capabilities.register(
  feature,
  NativeDesktop::CapabilityState::Supported
)
```

Permissions use registered `PermissionProvider` implementations in the same way. Platform-specific settings locations remain inside platform backends.

Applications can also establish one canonical identity and inspect integration problems:

```crystal
NativeDesktop.application.configure(
  NativeDesktop::ApplicationIdentity.new(
    "dev.example.application",
    "Example Application",
    Path[Process.executable_path.not_nil!].expand
  )
)

NativeDesktop.application.diagnostics.each do |diagnostic|
  puts "#{diagnostic.feature}: #{diagnostic.message}"
end
```

## Application activations

URL, file-open, and second-instance events share a typed activation stream. Cold-start events are retained until the first replaying handler is installed:

```crystal
NativeDesktop.activations.capture_arguments(ARGV) do |argument|
  application_activation_for(argument) # Activation?
end

NativeDesktop.activations.on_event do |activation|
  case activation.type
  when NativeDesktop::ActivationTypes::URL
    open_url(activation.values.first)
  when NativeDesktop::ActivationTypes::Files
    open_files(activation.values.map { |value| Path[value] })
  when NativeDesktop::ActivationTypes::SecondInstance
    handle_secondary_launch(activation.values.first)
  end
end
```

The macOS backend installs an Apple-event `ActivationSource`; Linux and Windows install a command-line source. Additional host or toolkit sources can be installed without replacing those defaults. Sources own their platform parsing and emit `Activation` values, so the core stream contains no platform-specific classification policy. `SingleInstance#listen_activations` routes the existing IPC payload stream into the same API.

## Notification events

Subscribe to normalized notification events before displaying notifications:

```crystal
NativeDesktop.notifications.on_event do |event|
  if event.type == NativeDesktop::NotificationEventTypes::ActionSelected
    handle_notification_action(event.id, event.action_id)
  end
end
```

Bundled platform event sources translate UserNotifications responses, libnotify signals, and Windows notification messages before they enter the shared stream. Additional notification backends can install their own `NotificationEventSource`. Delivery failures raised by `show` are emitted automatically as `Failed` events.

## Drop targets and change monitors

Each platform supplies a native default adapter, so an owned target can attach directly to a host window:

```crystal
target = NativeDesktop::DropTarget.new(
  window,
  [NativeDesktop::DragKind::File, NativeDesktop::DragKind::URL]
) do |event|
  import(event.payloads)
end
```

A toolkit can pass its own `DropTargetAdapter` as the second constructor argument for one target, or layer a provider over the native default:

```crystal
registration = NativeDesktop::DropTargets.register do
  ToolkitDropTargetAdapter.new
end

# Default construction now uses the toolkit provider.
target = NativeDesktop::DropTarget.new(window) { |event| import(event.payloads) }

target.close
registration.close # reveals the previous provider
```

Call `target.close` before destroying the host window. `DisplayMonitor`, `ClipboardMonitor`, and `HardwareMonitor` provide change-only callbacks using the background executor supplied to `Runtime`.

Session events follow the same host-neutral model:

```crystal
NativeDesktop.session.on_event do |event|
  if event.type.in?({
       NativeDesktop::SessionEventTypes::Suspend,
       NativeDesktop::SessionEventTypes::Shutdown,
     })
    save_state
  end
end
```

Session behavior is supplied by registered `SessionEventSource` adapters: NSWorkspace on macOS, logind on Linux when available, and forwarded Windows messages. Native constants and decoding live in their platform backend rather than in the shared lifecycle API.

Window, display, clipboard, and dialog calls are GUI-bound even on platforms where an individual native call may happen to be thread-safe. This gives hosts one consistent threading contract across macOS, Linux, and Windows.

## Guides

- [Host integration](guides/host-integration.md) covers runtime attachment, GUI dispatch, background execution, native handles, Windows message forwarding, and shutdown.
- [Platform support](guides/platform-support.md) documents service availability and operating-system constraints.
- [Resource lifecycle](guides/resource-lifecycle.md) covers ownership, cleanup, callbacks, concurrency, and host-window lifetime.
- [Guide index](guides/README.md) explains the shard’s documentation boundary.

## Requirements

- Crystal 1.21 or newer
- AppKit on macOS
- GTK 3, GDK, X11, XScreenSaver, libnotify, AppIndicator 3, Speech Dispatcher, and libudev on Linux
- the standard Win32 desktop libraries on Windows

Linux distribution packages (Debian/Ubuntu and Fedora names; other distributions ship equivalents):

| Component                      | Debian/Ubuntu           | Fedora                             |
| ------------------------------ | ----------------------- | ---------------------------------- |
| GTK 3, GDK, GLib, GObject, GIO | `libgtk-3-dev`          | `gtk3-devel`                       |
| X11, XScreenSaver              | `libx11-dev libxss-dev` | `libX11-devel libXScrnSaver-devel` |
| libnotify                      | `libnotify-dev`         | `libnotify-devel`                  |
| AppIndicator 3                 | `libappindicator3-dev`  | `libappindicator-gtk3-devel`       |
| Speech Dispatcher              | `libspeechd-dev`        | `speech-dispatcher-devel`          |
| libudev                        | `libudev-dev`           | `systemd-devel`                    |

`fprintd` (biometric authentication) is a runtime D-Bus service, not a build dependency; biometric support needs only the GLib development files above.

The tray, notifications, speech, biometric, and hardware subsystems can be disabled at build time when their optional native library is unavailable. Pass the matching `-Dnative_desktop_no_*` flag to `crystal` (see [Platform support](guides/platform-support.md)).

`native_desktop` does not create windows or start an event loop. It is intended for GUI hosts that already own those responsibilities and can provide a native top-level window handle when window-specific operations are needed.

## Installation

```yaml
dependencies:
  native_desktop:
    github: naqvis/native_desktop
```

Then run `shards install`.

## Host integration

The GUI host creates the window and owns its event loop. Attach `native_desktop` from the GUI thread and provide a dispatcher that schedules work on that same loop:

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

# `dispatch` must enqueue work on the GUI loop owned by the host toolkit.
NativeDesktop::Runtime.attach_to_current_thread(background: background) do |work|
  host_window.dispatch { work.call }
end
```

The dispatcher is a host integration point, not a selectable platform backend. Platform selection remains automatic.

Calls made on the attached GUI thread run immediately. Calls from other execution contexts are queued through the dispatcher and wait without blocking the GUI event loop. `detach` wakes pending callers with `NativeDesktop::RuntimeError` instead of leaving fibers blocked during shutdown.

The background executor is used by controls that must wait for native events without occupying the GUI loop, including global shortcuts and speech-recognition event polling. The host owns that execution context and its shutdown order.

Only one host may be attached at a time. A second attachment raises `NativeDesktop::RuntimeError` with code `:already_attached`. Work queued by an earlier attachment is rejected after detach or reattachment, so a stale callback cannot operate on a replacement GUI host.

```crystal
NativeDesktop::Runtime.detach
```

Stop monitors, shortcuts, speech synthesizers and recognizers, drag sources, toolbars, taskbar controllers, tray resources, and other owned services before detaching. Detach rejects later GUI-bound calls and wakes callers currently waiting for GUI work.

## Existing native windows

`NativeDesktop::Window` is a non-owning reference. Destroying it does not destroy the native window, and the host must not use it after the underlying window has closed.

```crystal
window = NativeDesktop::Window.attach(host_window.native_handle)
window.always_on_top = true
window.titlebar_overlay = true
```

A null handle is rejected. Handles are interpreted automatically for the build platform: `NSWindow` on macOS, `GtkWindow` on Linux, and `HWND` on Windows. Titlebar overlay enables a full-size content view on macOS and removes the standard window frame on Linux and Windows.

The window wrapper also exposes common host-window operations:

```crystal
window.move(120, 80)
x, y = window.position

window.show
window.focus
window.minimize
window.maximize
window.restore
window.hide

window.fullscreen = true
window.frameless = true
window.transparent = true
window.opacity = 0.9

child = NativeDesktop::Window.attach(child_window_handle)
child.set_modal(window.handle, true)
```

Coordinates are screen coordinates. Opacity accepts `0.0..1.0`; invalid or non-finite values raise `ArgumentError`. Modal state is applied to the child window relative to the supplied parent handle.

### Window effects

Effects are applied through the same non-owning window reference. Unsupported options are ignored on the current platform.

```crystal
window.apply(
  NativeDesktop::WindowEffects.new(
    vibrancy: true,
    material: :sidebar,
    mica: true,
    acrylic: true,
    blur_behind: true
  )
)
```

Vibrancy materials apply on macOS, Mica and Acrylic apply on Windows, and blur-behind applies where supported by Windows or an X11 compositor.

## Displays and pointer position

Display geometry and the current pointer location are available without exposing toolkit or operating-system handles:

```crystal
NativeDesktop.displays.all.each do |display|
  puts "#{display.name}: #{display.bounds.width}x#{display.bounds.height} @#{display.scale_factor}x"
  puts "work area: #{display.work_area}"
  puts "primary" if display.primary?
end

pointer = NativeDesktop.displays.cursor
puts "#{pointer.x}, #{pointer.y}"
```

The primary display is available directly when a caller does not need the complete list:

```crystal
if display = NativeDesktop.displays.primary
  puts display.name
end
```

Display snapshots are ordered with the primary display first. Geometry is expressed in desktop coordinate units and may have negative origins for displays positioned left of or above the primary display. `scale_factor` converts logical desktop units to physical pixels where the platform exposes that distinction.

These queries are marshalled through the attached GUI runtime because GTK and AppKit display state is GUI-thread-bound.

## Foreground application

The foreground application's display name is available when the window system exposes it:

```crystal
if name = NativeDesktop.applications.foreground_name
  puts "Active application: #{name}"
end

NativeDesktop.applications.open("https://crystal-lang.org")
NativeDesktop.applications.open(Path["report.pdf"].expand.to_s)
```

The result is `nil` when it cannot be determined. In particular, generic Wayland clients cannot inspect another application's focused surface without compositor-specific protocols.

`applications.open` raises `NativeDesktop::Error` with code `:open_failed` when the operating system rejects the request. Passing an empty target raises `ArgumentError` before any native call.

## URL schemes

Register an executable as the current user's handler for a custom URL scheme:

```crystal
registration = NativeDesktop::URLSchemeRegistration.new(
  scheme: "myapp",
  application_name: "My Application",
  executable: Path[Process.executable_path.not_nil!]
)

NativeDesktop.url_schemes.register(registration)
NativeDesktop.url_schemes.unregister("myapp")
```

The scheme must follow the standard URI scheme syntax and the executable path must be absolute. Registration creates a small Launch Services bundle on macOS, a user-level desktop entry on Linux, or current-user registry keys on Windows.

## Login autostart

Register an application to launch when the current user logs in:

```crystal
entry = NativeDesktop::AutostartEntry.new(
  name: "My Application",
  executable: Path[Process.executable_path.not_nil!],
  arguments: ["--profile", "default"],
  minimized: true,
  delay: 5.seconds
)

NativeDesktop.autostart.enable(entry)
puts NativeDesktop.autostart.enabled?(entry.name)
NativeDesktop.autostart.disable(entry.name)
```

Arguments are stored as individual LaunchAgent values on macOS and safely quoted in Linux desktop entries and Windows registry commands. Linux represents `delay` with `X-GNOME-Autostart-Delay`. Windows login registry entries do not provide a delay field. macOS LaunchAgents do not provide a one-shot login-delay field; `delay` is currently unsupported there.

## Errors

Native failures raise `NativeDesktop::Error`. Its symbolic `code` is intended for programmatic handling while the message carries platform context. Runtime attachment and shutdown failures use the `NativeDesktop::RuntimeError` subclass.

Input errors that can be detected before touching the operating system, such as a relative autostart executable or malformed URL scheme, raise `ArgumentError`.

Symbolic error codes:

| Code                                                                                                      | Meaning                                                              |
| --------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `:not_attached`                                                                                           | A GUI-bound call was made before `Runtime.attach_to_current_thread`. |
| `:already_attached`                                                                                       | A second runtime attachment was attempted.                           |
| `:detached`                                                                                               | Work was queued or awaited on a runtime that has since detached.     |
| `:dispatch_timeout`                                                                                       | A GUI-bound call did not complete within its requested timeout.      |
| `:background_executor_missing`                                                                            | A background-bound service was used without a background executor.   |
| `:application_identity_missing`                                                                           | A permission request needs `Application#configure` first.            |
| `:platform_unavailable`                                                                                   | The platform backend is not available for the requested operation.   |
| `:native_call_failed`                                                                                     | A native call failed for an unspecified platform reason.             |
| `:open_failed`                                                                                            | The operating system rejected an open-URL-or-path request.           |
| `:file_not_found`, `:permission_denied`, `:trash_failed`                                                  | Trash operation failures.                                            |
| `:lock_failed`                                                                                            | A single-instance lock could not be acquired.                        |
| `:shortcut_conflict`, `:shortcut_register_failed`, `:shortcut_listen_failed`                              | Global shortcut problems.                                            |
| `:speech_closed`, `:speech_failed`, `:speech_unavailable`, `:speech_recognition_*`                        | Speech synthesis and recognition problems.                           |
| `:tray_create_failed`, `:taskbar_*`, `:kiosk_*`, `:drop_target_*`, `:clipboard_*`, `:notification_failed` | Feature-specific native failures.                                    |
| `:autostart_failed`, `:url_scheme_registration_failed`, `:file_association_failed`                        | Integration registration failures.                                   |

Feature-specific codes follow a `<area>_<failure>` convention so callers can match them without depending on platform message text.

## Clipboard

Clipboard operations are marshalled through the attached GUI runtime:

```crystal
clipboard = NativeDesktop.clipboard

clipboard.write_text("Hello from Crystal")
puts clipboard.read_text

clipboard.write_html("<strong>Hello</strong>")
clipboard.read_html

clipboard.write_rtf(%q({\rtf1 Hello}))
clipboard.read_rtf

clipboard.write_image(png_or_dib_bytes)
clipboard.read_image

clipboard.version
clipboard.clear
```

Image data is PNG on macOS and Linux and DIB data on Windows. Linux clipboard access uses GTK/GDK directly and does not invoke external clipboard utilities.

## Dialogs

File pickers return `Path` values and use the operating system's native dialog implementation. Filters contain a display name and one or more file extensions without leading dots.

```crystal
images = NativeDesktop::FileFilter.new("Images", %w(png jpg jpeg))

file = NativeDesktop.dialogs.open_file(
  NativeDesktop::OpenDialogOptions.new(
    title: "Choose an image",
    directory: Path["/tmp"],
    filters: [images]
  )
)

files = NativeDesktop.dialogs.open_files(
  NativeDesktop::OpenDialogOptions.new(title: "Choose images", filters: [images])
)

destination = NativeDesktop.dialogs.save_file(
  NativeDesktop::SaveDialogOptions.new(title: "Export", suggested_name: "image.png", filters: [images])
)

folder = NativeDesktop.dialogs.select_folder(
  NativeDesktop::FolderDialogOptions.new(title: "Choose a destination")
)
```

Message dialogs use the same GUI-thread runtime:

```crystal
NativeDesktop.dialogs.message("Export complete", "The image was saved.")
NativeDesktop.dialogs.message("Export failed", "The image could not be saved.", NativeDesktop::MessageKind::Error)

if NativeDesktop.dialogs.confirm("Replace file?", "The destination already exists.")
  # Replace it.
end
```

Dialog and clipboard calls must be made after the host attaches `NativeDesktop::Runtime`. Calls from worker execution contexts are marshalled to the attached GUI thread.

## Notifications

Request permission once, then display notifications using an application-defined identifier. Showing another notification with the same identifier replaces it on platforms that support replacement.

```crystal
if NativeDesktop.notifications.request_permission("My Application")
  request = NativeDesktop::NotificationRequest.new(
    id: "export-complete",
    title: "Export complete",
    body: "The report is ready.",
    urgency: NativeDesktop::NotificationUrgency::Normal,
    timeout: 8.seconds,
    actions: [
      NativeDesktop::NotificationAction.new("open", "Open")
    ]
  )

  NativeDesktop.notifications.show("My Application", request)
end

NativeDesktop.notifications.close("export-complete")
```

Notification calls are marshalled through the attached GUI runtime. macOS uses UserNotifications when running from an application bundle and NSUserNotificationCenter otherwise. Linux uses libnotify. Windows uses the native notification-area balloon API.

Icons can be supplied as encoded bytes with a stable cache key or as an operating-system icon name:

```crystal
icon = NativeDesktop::NotificationIcon.bytes(File.read("status.png").to_slice, key: "status")
```

Action metadata is forwarded on platforms that can display notification buttons. UserNotifications responses on macOS, libnotify action/close signals on Linux, and notification-area click/dismissal messages on Windows are normalized as `NotificationEvent` values.

## Drag sources

A drag source belongs to one host window and must be started while handling the pointer event that begins the drag:

```crystal
window = NativeDesktop::Window.attach(native_window_handle)
source = NativeDesktop::DragSource.new(window)

source.start(NativeDesktop::DragPayload.file("report.pdf"))
source.start(NativeDesktop::DragPayload.text("Dragged text"))
source.start(NativeDesktop::DragPayload.url("https://crystal-lang.org"))
source.start(NativeDesktop::DragPayload.image("preview.png"))

source.close
```

File and image payloads are paths. An image payload is transferred as an image file rather than decoded pixel data, which preserves its filename and encoded format at the destination. Text and URL payloads use the platform's Unicode text or URL representation.

`start` is synchronous with the native drag session and returns `true` only when the operating system accepts the drop. It returns `false` when the session cannot start or is cancelled. `close` releases the source's association with its host window and is idempotent.

`closed?` reports whether the source has been released. Starting a closed source raises `NativeDesktop::RuntimeError` with code `:closed`.

## File type associations

Register an application as an available handler for a file extension and MIME type:

```crystal
association = NativeDesktop::FileAssociation.new(
  application_id: "dev.example.markdown",
  application_name: "Example Markdown",
  extension: ".md",
  type_name: "Markdown Document",
  mime_type: "text/markdown",
  executable: Path[Process.executable_path.not_nil!],
  description: "A Markdown source file"
)

NativeDesktop.file_associations.register(association)
NativeDesktop.file_associations.unregister(association)
```

`application_id` is a stable, reverse-domain-style identifier used to keep registrations from different applications isolated. The extension may be provided with or without a leading dot, and the executable must be an absolute path.

Registration creates an application-owned Launch Services bundle on macOS, desktop entry and GIO association on Linux, or ProgID and `OpenWithProgids` entry in the current-user Windows registry. It makes the application available in the operating system's “Open With” interface without replacing the user's default application. Pass the same association to `unregister` to remove only resources owned by that application.

## Context menus

Context menus are attached to a host-owned native window and return the identifier of the selected item:

```crystal
items = [
  NativeDesktop::ContextMenuItem.new("copy", "Copy"),
  NativeDesktop::ContextMenuItem.new(type: NativeDesktop::ContextMenuItemType::Separator),
  NativeDesktop::ContextMenuItem.new(
    "enabled",
    "Enabled",
    checked: true,
    type: NativeDesktop::ContextMenuItemType::Checkbox
  )
]

selected = NativeDesktop.context_menus.show(items, x, y, native_window_handle)
```

The coordinates are relative to the host window's content. Platform code converts them as required by the native popup API. Calling `show` with an empty item list returns `nil`; a null window handle raises `ArgumentError`.

## System tray

Create and update the process-wide system tray icon after attaching the GUI runtime:

```crystal
icon = NativeDesktop::TrayIcon.bytes(File.read("tray.png").to_slice, key: "tray")
NativeDesktop.tray.create("com.example.application", icon, "Example Application")

NativeDesktop.tray.on_click do |button|
  puts "Tray button #{button} clicked"
end

NativeDesktop.tray.tooltip = "Application is running"
NativeDesktop.tray.destroy
```

Tray menus use typed recursive items. The shard flattens them internally as required by each native implementation.

```crystal
items = [
  NativeDesktop::TrayMenuItem.new("open", "Open", action: ->{ puts "Open" }),
  NativeDesktop::TrayMenuItem.new("quit", "Quit", accelerator: "Cmd+Q", action: ->{ exit })
]

NativeDesktop.tray.set_menu(items)
```

`TrayMenuItemType` supports normal, checkbox, radio, and separator entries. Tray resources are non-window resources but remain GUI-thread-bound and are released by `NativeDesktop.tray.destroy`.

## Application menus

Application menus use the same recursive model on every platform. macOS installs the menu as the application-wide main menu; Linux and Windows attach it to the supplied native window.

```crystal
menu_bar = NativeDesktop::MenuBar.new

menu_bar.menu("File", "file") do |file|
  file.item("open", "Open", accelerator: "Cmd+O") do
    puts "Open"
  end
  file.separator
  file.menu("Recent", "recent") do |recent|
    recent.item("first", "First document") { puts "First document" }
  end
  file.item("quit", "Quit", accelerator: "Cmd+Q") { exit }
end

NativeDesktop.application_menus.install(menu_bar, native_window_handle)
```

Menu item actions run on the GUI thread. Reinstall the menu bar after changing an item's `enabled` or `checked` property so the native menu reflects the new state.

On macOS, wait until the application event loop is active before installation. Hosts that install controls generically can query `NativeDesktop.application_menus.requires_running_event_loop?` instead of branching on the operating system.

Windows hosts must offer each native `MSG` to `NativeDesktop::Runtime.process_event` before calling their normal message translation and dispatch functions. This lets menus and other native services consume relevant messages. The method returns `false` on macOS and Linux.

## Global shortcuts

Global shortcuts fire even while another application has focus. Build shortcuts from typed modifiers and keys, register handlers, and then start the registry:

```crystal
shortcuts = NativeDesktop::GlobalShortcuts.new

show_window = NativeDesktop::Shortcut.new(
  [NativeDesktop::ShortcutModifier::Ctrl, NativeDesktop::ShortcutModifier::Shift],
  NativeDesktop::ShortcutKey::Space
)

shortcuts.register(show_window) { show_main_window }
shortcuts.start

# Registrations may be added or removed while listening.
shortcuts.unregister(show_window)
shortcuts.stop
shortcuts.cleanup
```

Modifier order does not affect shortcut identity. Letter, number, function, navigation, editing, and common punctuation keys are supported. Duplicate registrations raise `NativeDesktop::Error` with code `:shortcut_conflict`; native conflicts and unsupported mappings use `:shortcut_register_failed`.

Handlers run through the background executor supplied to `NativeDesktop::Runtime`. A handler exception is logged without stopping native event collection. Keep handlers short or hand work to an application-owned task queue.

macOS requires Accessibility permission for system-wide keyboard events. Linux uses X11 global key grabs and therefore needs an X11 or XWayland session. Windows hosts receive hotkeys through their normal message loop and must pass messages to `NativeDesktop::Runtime.process_event` as described above.

## Taskbar and Dock status

A taskbar controller is tied to a host-owned window. The application identifier is used on desktops whose taskbar protocol identifies applications rather than individual windows.

```crystal
taskbar = NativeDesktop::Taskbar.new(native_window_handle, "com.example.application")
taskbar.state = NativeDesktop::TaskbarProgressState::Normal
taskbar.progress = 0.45
taskbar.badge = "3"
taskbar.overlay_icon = NativeDesktop::TaskbarIcon.bytes(File.read("sync.png").to_slice)

taskbar.clear_progress
taskbar.cleanup
```

Progress values are clamped to `0.0..1.0`; non-finite values raise `ArgumentError`. Call `cleanup` before the host destroys the underlying native window.

Windows supports progress states, progress values, and overlay icons. macOS represents progress as a percentage Dock badge and supports explicit badge text, but does not provide a native overlay-icon API. Generic Linux desktops do not expose one portable taskbar progress protocol, so these operations are no-ops there.

## Kiosk presentation

Kiosk presentation removes ordinary window chrome, fills the current display, and restores the previous window state on exit:

```crystal
kiosk = NativeDesktop::Kiosk.new(native_window_handle)
kiosk.enter
puts kiosk.active?

kiosk.exit
kiosk.cleanup
```

The controller is non-owning: the host must keep the native window alive until `cleanup` completes. On Windows it preserves the original styles, placement, show state, and topmost state. Linux preserves decoration and an existing fullscreen state. macOS preserves the application's presentation options and requires a packaged application bundle.

Kiosk presentation is not a security boundary. It does not prevent operating-system escape sequences, privileged process management, or physical access. Deployments that require device lockdown must combine it with the operating system's managed kiosk facilities.

## System appearance

Read the operating system's effective application appearance without attaching the GUI runtime:

```crystal
case NativeDesktop.system_theme.current
when .dark?
  puts "dark"
when .light?
  puts "light"
end
```

Change monitoring polls through the background executor supplied to `NativeDesktop::Runtime` and invokes the callback only when the effective appearance changes:

```crystal
monitor = NativeDesktop::ThemeMonitor.new
monitor.start(2.seconds) do |appearance|
  puts "Appearance changed to #{appearance.to_s.downcase}"
end

# Stop before detaching the runtime.
monitor.stop
```

Calling `start` on an active monitor leaves the existing monitor in place. `stop` is safe to call more than once; a worker already sleeping exits when it wakes. Callback code runs on the host's background executor, so marshal UI updates through the host's GUI dispatcher.

macOS reads the effective application appearance preference, Linux uses the GNOME interface settings with `GTK_THEME` as a fallback, and Windows reads the current user's application-theme preference.

## Battery and power

Battery snapshots distinguish charging from connection to external power. This matters when a full battery is plugged in but is not actively charging.

```crystal
if battery = NativeDesktop.power.battery
  if level = battery.level
    puts "Battery: #{(level * 100).round}%"
  end
  puts battery.charging? ? "Charging" : "Not charging"
  puts battery.external_power? ? "External power" : "On battery"
  battery.remaining.try { |time| puts "Estimated time: #{time}" }
else
  puts "No battery"
end
```

`level` and `remaining` are `nil` when the operating system cannot provide them. `remaining` is a `Time::Span`, with platform-specific units normalized by the shard.

Monitor changes through the background executor attached to `NativeDesktop::Runtime`:

```crystal
monitor = NativeDesktop::PowerMonitor.new
monitor.start(30.seconds) do |battery|
  if battery
    puts "Power state changed: #{battery.level}"
  else
    puts "Battery removed"
  end
end

monitor.stop
```

Only changes are delivered. Calling `start` on an active monitor leaves the existing monitor in place, and `stop` is safe to call more than once.

macOS uses IOKit power-source information, Linux reads the kernel power-supply interface, and Windows uses `GetSystemPowerStatus`.

## User idle time

Read how long it has been since the operating system observed keyboard or pointer input:

```crystal
idle_for = NativeDesktop.idle.duration
puts "Idle for #{idle_for}"
puts "Away" if NativeDesktop.idle.idle?(10.minutes)
```

The snapshot API does not require an attached GUI runtime. Monitoring uses the host's background executor and reports the current state first, followed by transitions only:

```crystal
monitor = NativeDesktop::IdleMonitor.new
monitor.start(threshold: 5.minutes, interval: 15.seconds) do |change|
  if change.idle?
    puts "User became idle after #{change.duration}"
  else
    puts "User became active"
  end
end

monitor.stop
```

macOS reads the CoreGraphics combined-session input timer. Linux uses the XScreenSaver extension and returns zero when no X11 or XWayland display is available. Windows uses `GetLastInputInfo` and handles the system tick counter wrapping.

## CPU utilization

`NativeDesktop.cpu.times` returns exact cumulative aggregate counters. Their unit is platform-defined, so use differences rather than interpreting a counter as a duration:

```crystal
times = NativeDesktop.cpu.times
puts "busy=#{times.busy}, total=#{times.total}"
```

`NativeDesktop::CPUSampler` calculates utilization between successive samples. The first sample returns `nil` because it establishes the baseline:

```crystal
sampler = NativeDesktop::CPUSampler.new
sampler.sample # => nil

sleep 1.second
if usage = sampler.sample
  puts "CPU: #{usage.round(1)}%"
end
```

Sampling is safe from multiple execution contexts. Counter subtraction happens before conversion to `Float64`, avoiding precision loss on long-running systems. A counter reset establishes a new baseline and returns `nil` for that sample.

macOS reads Mach host CPU ticks, Linux reads the aggregate line from `/proc/stat`, and Windows uses `GetSystemTimes`.

## Speech synthesis

Create an owned speech engine, inspect the voices installed on the host, and submit text asynchronously:

```crystal
speech = NativeDesktop.speech

voice = speech.voices.find { |candidate| candidate.language.starts_with?("en") }
speech.speak(
  "Native speech from Crystal",
  NativeDesktop::SynthesisOptions.new(voice: voice, rate: 1.1, volume: 0.8)
)

speech.pause
speech.resume
speech.stop
speech.cleanup
```

Each voice has a stable platform identifier, display name, BCP 47 language tag, local-availability flag, and an optional variant. Variants distinguish separately installed forms of the same voice, such as compact, enhanced, or premium voices on macOS and named Speech Dispatcher variants on Linux.

Speech calls are marshalled to the attached GUI thread. The engine owns its AppKit object, Speech Dispatcher connection, or SAPI COM object and releases it in `cleanup`. Cleanup is idempotent; using the engine afterwards raises `NativeDesktop::Error` with code `:speech_closed`.

`rate`, `pitch`, and `volume` use Web Speech-style values: rate is `0.1..10.0`, pitch is `0.0..2.0`, and volume is `0.0..1.0`. These values are mapped onto each native engine's range; an individual installed voice may still clamp values it cannot render. Starting a new utterance stops the previous one, and `speaking?` returns to `false` after natural completion on every platform.

## Speech recognition

Speech recognition uses the operating system rather than a bundled model or third-party recognizer:

```crystal
recognizer = NativeDesktop.speech_recognizer
language = recognizer.languages.find(&.==("en-US")) || abort "English recognition is not supported"

unless recognizer.available?(language)
  abort "The requested system recognizer is unavailable"
end

if recognizer.request_permission == NativeDesktop::SpeechRecognitionPermission::Granted
  recognizer.on_result do |result|
    puts "#{result.final? ? "final" : "partial"}: #{result.transcript}"
  end
  recognizer.on_error { |error| STDERR.puts error.message }
  recognizer.on_end { puts "recognition ended" }
  recognizer.start(language, interim: true)
end
```

`languages` returns canonical BCP 47 tags supported by the installed system recognizers. A listed language can still be temporarily unavailable—for example, when its macOS recognizer requires a network connection—so check `available?(language)` before starting.

macOS uses `Speech.framework` with microphone capture from AVFoundation. Applications must provide `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` in their `Info.plist`. Windows uses the installed SAPI recognizer and default audio input. Recognition language packs must already be installed by the user. Linux reports `available? == false` because freedesktop.org provides no standard system STT API comparable to the macOS and Windows services.

`stop` finishes the current input and allows a final result; `abort` cancels immediately. Results and errors arrive asynchronously, and `on_end` fires after either normal completion or cancellation. Call `cleanup` when the recognizer is no longer needed.

## Biometric authentication

Inspect the current capability immediately before presenting an authentication action:

```crystal
info = NativeDesktop.biometric.info

if info.available?
  puts "Available modality: #{info.modality}"
  result = NativeDesktop.biometric.authenticate("Unlock encrypted settings")
  puts result.success? ? "Authenticated" : "Rejected: #{result.error}"
end
```

On Windows, pass the host-owned top-level window so the Windows Hello prompt has the correct owner:

```crystal
owner = NativeDesktop::Window.attach(native_window_handle)
result = NativeDesktop.biometric.authenticate("Confirm purchase", owner)
```

The window reference is non-owning and is ignored on platforms whose authentication prompt does not require an owner. Authentication blocks the calling fiber until the user responds, so GUI hosts should invoke it from their background execution context. Concurrent authentication requests are serialized to prevent overlapping operating-system prompts.

macOS uses LocalAuthentication and reports Touch ID or Face ID. Linux talks directly to fprintd over the system D-Bus and reports availability only when the current user has an enrolled fingerprint. Windows checks enrolled fingerprint factors and uses the window-aware Windows Hello consent API.

## Trash

Move a file, directory, or symbolic link to the operating system's recoverable trash location:

```crystal
NativeDesktop.trash.move(Path["downloads", "old-report.pdf"])
```

Relative paths are expanded before the native operation. A symbolic link itself is trashed without resolving or moving its target. Failures raise `NativeDesktop::TrashError`; its `code` is `:file_not_found`, `:permission_denied`, or `:trash_failed`.

macOS uses `NSFileManager`, Windows uses the Recycle Bin through the Win32 shell API, and Linux implements the FreeDesktop Trash specification without invoking command-line tools. Linux uses the home trash for files on the home filesystem and a volume-local trash for other mounts. Name allocation and metadata creation are serialized so concurrent requests from different execution contexts cannot select the same destination inside the process.

## Hardware enumeration

Enumerate connected devices without exposing IOKit, udev, SetupAPI, registry, or native handle types:

```crystal
if NativeDesktop.hardware.available?(NativeDesktop::HardwareKind::USB)
  NativeDesktop.hardware.enumerate(NativeDesktop::HardwareKind::USB).each do |device|
    puts "#{device.name} (#{device.id})"
    if (vendor = device.vendor_id) && (product = device.product_id)
      puts "vendor=#{vendor.to_s(16)} product=#{product.to_s(16)}"
    end
  end
end
```

`enumerate` performs a fresh, read-only scan and returns connected-device snapshots. IDs are derived from operating-system device identities, serial numbers, addresses, or native device paths; they are never randomly generated. Vendor and product IDs are populated when the platform reports them. NFC currently reports unavailable and returns an empty array.

Enumeration does not require an attached GUI runtime. A platform scan failure is logged and returned as an empty array, matching an enumeration with no connected devices.

## Single-instance locks

Use an owned, non-blocking operating-system lock to decide whether the current process is the primary application instance:

```crystal
lock = NativeDesktop.instance_lock("com.example.my-app")

unless lock.acquire
  puts "Another instance is already running"
  exit
end

begin
  run_application
ensure
  lock.release
end
```

Unix systems use an advisory file lock and Windows uses a session-local named mutex. The Unix lock file records the owner PID for diagnostics, but ownership is determined by the kernel lock rather than trusting the PID. A failed secondary acquisition never truncates or rewrites the primary process's file.

`acquire` and `release` are thread-safe and idempotent on the same lock object. `acquire` returns immediately rather than waiting for another process. `cleanup_stale` removes an unlocked file left after an unclean Unix shutdown.

For applications that also need to forward a payload from a secondary process, use the high-level manager:

```crystal
instance = NativeDesktop::SingleInstance.new("com.example.my-app")

if instance.first?
  instance.listen do |payload|
    puts "Secondary instance sent: #{payload}"
  end

  begin
    run_application
  ensure
    instance.cleanup
  end
else
  instance.send(ARGV.to_json)
end
```

`listen` starts the platform IPC listener only after this process acquires the lock. `send` connects to the primary instance and forwards one string payload. Call `cleanup` in the primary process to stop IPC and release the lock.

## Toolbars

A toolbar attaches to a host-owned window. The optional content handle identifies the host view that should be laid out below the toolbar; this is useful on Windows, where the shard must resize the content when the window changes size.

```crystal
toolbar = NativeDesktop::Toolbar.new
toolbar.button("save", "Save", NativeDesktop::ToolbarIcon.name("document-save")) do
  puts "Save"
end
toolbar.toggle("preview", "Preview") { puts "Toggle preview" }
toolbar.dropdown("format", "Format", ["PDF", "HTML"]) { puts "Format selected" }
toolbar.color("accent", "Accent", "#336699") { puts "Color changed" }
toolbar.separator

toolbar.attach(native_window_handle, native_content_handle)
toolbar.sync
toolbar.visible = false
toolbar.cleanup
```

Both handles are non-owning. The window handle is required; the content handle may be omitted when the host manages its own content layout. Toolbar operations and callbacks run on the attached GUI thread. Call `sync` after changing the item collection or mutable item state.

Only one toolbar may be attached by a process at a time. Attaching a second toolbar while another toolbar owns the native integration leaves the second toolbar unattached. Call `cleanup` on the owner before attaching a replacement. Creating another host window does not transfer toolbar ownership.

## Lifecycle checklist

The host owns the GUI loop and all native window handles. A typical shutdown order is:

1. Stop `ThemeMonitor`, `PowerMonitor`, and `IdleMonitor`.
2. Stop and clean up `GlobalShortcuts`.
3. Clean up speech synthesizers and recognizers, drag sources, toolbars, taskbar controllers, and kiosk controllers.
4. Destroy the tray and release application-owned single-instance resources.
5. Call `NativeDesktop::Runtime.detach`.
6. Destroy the host windows and stop the host’s background execution context.

Do not destroy a native window while a `Window`, `Toolbar`, `Taskbar`, `Kiosk`, `DragSource`, menu, or context-menu operation is still using its handle.

## Development

```bash
crystal spec
```

## License

MIT

## Contributors

- [Ali Naqvi](https://github.com/naqvis) — creator and maintainer
