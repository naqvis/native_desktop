# Resource Lifecycle

The host and the shard own different resources. The host owns the GUI event loop, background execution context, native windows, and native content views. `native_desktop` owns the operating-system objects it creates for controls and services.

## Ownership table

| API | Ownership | Release operation |
| --- | --- | --- |
| `NativeDesktop::Window` | Non-owning native window reference | Release the value before the host destroys the window |
| `NativeDesktop::DragSource` | Owns drag-source state; refers to a host window | `close` |
| `NativeDesktop::DropTarget` | Owns drop filtering/callback state; refers to a host window | `close` |
| `NativeDesktop::Toolbar` | Owns native toolbar controls; refers to host window/content handles | `cleanup` |
| `NativeDesktop::Taskbar` | Owns taskbar integration; refers to a host window | `cleanup` |
| `NativeDesktop::Kiosk` | Owns saved presentation state; refers to a host window | `exit`, then `cleanup` |
| `NativeDesktop::GlobalShortcuts` | Owns native registrations and its listener | `stop`, then `cleanup` |
| Speech synthesizer | Owns AppKit, Speech Dispatcher, or SAPI synthesis resources | `cleanup` |
| Speech recognizer | Owns Speech.framework/AVFoundation or SAPI recognition resources | `cleanup` |
| Theme, power, idle, display, clipboard, and hardware monitors | Own background polling work | `stop` |
| System tray | Process-wide native resource | `NativeDesktop.tray.destroy` |
| Application menu | Native menu installed for an application or window | Install a replacement; the installed menu follows the host application or window lifetime |
| Single-instance lock/manager | Owns lock and IPC listener resources | `release` or `cleanup` |

Cleanup methods are safe to call repeatedly where the API exposes them. Using a closed speech synthesizer, recognizer, or drag source raises a typed error rather than accessing released native state.

## GUI-bound operations

Window controls, displays, clipboard, dialogs, notifications, menus, tray, toolbar, shortcuts, taskbar, kiosk, drag sources, and speech are marshalled through `NativeDesktop::Runtime`.

Calls from a worker execution context suspend that fiber while the attached GUI dispatcher performs the operation. The GUI thread must continue processing its event loop; blocking it while waiting for a worker that is itself waiting for GUI dispatch creates an application-level deadlock.

## Callbacks

Menu, tray, toolbar, and other GUI control callbacks run on the GUI thread. Keep them short and move expensive work to an application-owned worker context.

Theme, power, idle, global-shortcut, and speech-recognition callbacks run through the background executor supplied at runtime attachment. Dispatch interface updates back to the GUI thread.

A global-shortcut callback exception is logged without stopping native event collection. Applications should still handle errors inside callbacks when they need retry, reporting, or recovery behavior.

## Monitors

Calling `start` on an active theme, power, or idle monitor leaves the existing monitor in place. `stop` is idempotent. A polling worker that is sleeping observes the stop request when it wakes, so the host must stop monitors before shutting down their execution context.

Power and theme monitors emit changes only. The idle monitor reports its initial state and then emits transitions.

## Host window lifetime

Native window and content handles are borrowed pointers. They must not outlive the host objects they identify.

Before destroying a native window:

1. Stop callbacks that can initiate work for that window.
2. Close its drag sources.
3. Clean up its toolbar, taskbar, and kiosk controllers.
4. Remove or replace installed menus as required by the host.
5. Release `NativeDesktop::Window` references.
6. Destroy the host window.

The shard does not retain or destroy host windows on the application’s behalf.

## Process-wide services

Tray state, application menus on macOS, and toolbar native integration have process-wide aspects. Treat their owners as application services even when their API refers to a specific window.

Only one toolbar may own the native integration. A second toolbar remains unattached until the existing owner is cleaned up. A newly created window does not inherit or take over the toolbar.

## Runtime detach

`NativeDesktop::Runtime.detach` rejects pending dispatched work and prevents later GUI-bound calls. It does not clean up native services automatically because the host controls their dependency order.

Stop and release owned services first, detach the runtime second, and destroy native windows last.
