# Platform Support

`native_desktop` supports macOS, Linux with GTK 3, and Windows. Platform selection is automatic.

A supported API means the shard provides a native implementation for that operating system. Hardware, permissions, desktop services, session type, or compositor support may still affect runtime availability.

## Native windows and desktop controls

| Service | macOS | Linux | Windows |
| --- | --- | --- | --- |
| Existing-window attachment and common window operations | Supported | Supported | Supported |
| Window effects | Vibrancy and materials | Blur where the X11 compositor supports it | Mica, Acrylic, and blur-behind |
| Display geometry, work areas, scale, and pointer position | Supported | Supported | Supported |
| Clipboard: text, HTML, RTF, and images | Supported | Supported | Supported |
| Open, save, folder, message, and confirmation dialogs | Supported | Supported | Supported |
| Notifications | Supported | Supported through libnotify | Supported through notification-area balloons |
| Context menus | Supported | Supported | Supported |
| Drag sources | Supported | Supported | Supported |
| Drop targets | Supported through AppKit | Supported through GTK | Supported through OLE |
| File type associations | Supported | Supported | Supported |
| System tray | Supported | Supported through AppIndicator | Supported |
| Application menus | Application-wide menu | Attached to a window | Attached to a window |
| Window toolbars | Supported | Supported | Supported |
| Kiosk presentation | Supported in an application bundle | Supported | Supported |

Notification activation is normalized by platform-owned `NotificationEventSource` implementations. macOS receives UserNotifications delegate responses, Linux receives libnotify action and close signals, and Windows receives notification-area callback messages. Legacy macOS notifications do not expose the same response contract.

Only one toolbar owns the process-wide native toolbar integration at a time. Creating another host window does not transfer that ownership.

File type associations advertise the application in the platform's “Open With” interface without replacing the user's default handler. They create an application-owned Launch Services bundle on macOS, desktop entry and GIO association on Linux, or ProgID and `OpenWithProgids` entry in the current-user registry on Windows.

## Operating-system integration

| Service | macOS | Linux | Windows |
| --- | --- | --- | --- |
| Open URL or path | Supported | Supported through GIO | Supported |
| Foreground application name | Supported | X11 sessions | Supported |
| Custom URL schemes | Per-user Launch Services bundle | Per-user desktop entry | Current-user registry |
| Login autostart | LaunchAgent | Desktop entry | Current-user registry |
| Global shortcuts | Requires Accessibility permission | Requires X11 or XWayland | Supported through the host message loop |
| Taskbar or Dock progress | Percentage represented through the Dock badge | No portable progress protocol | Progress states and values |
| Badge text | Supported | No portable API | Not provided by the taskbar API |
| Overlay icon | Not provided by the Dock API | Not portable | Supported |
| Trash | `NSFileManager` | FreeDesktop Trash specification | Recycle Bin |
| Single-instance lock and payload forwarding | Supported | Supported | Supported |
| URL/file activation delivery | Apple events | Command-line arguments or another installed source | Command-line arguments or another installed source |
| Session suspend/resume/lock/unlock | NSWorkspace notifications | systemd-logind D-Bus signals | Windows messages through runtime forwarding |

Generic Wayland clients cannot query another application’s focused surface without compositor-specific protocols. The foreground application name can therefore be unavailable on Wayland.

Autostart delay is represented by `X-GNOME-Autostart-Delay` on Linux. Windows login registry entries and macOS LaunchAgents do not provide the same delay behavior.

Owned file dialogs are window-modal sheets on macOS and native owned dialogs on Windows and Linux. Windows' legacy folder picker cannot force hidden files to be visible, and macOS always retains the system overwrite confirmation; the corresponding options preserve the safer native behavior on those two platform-specific edges.

## Monitoring and hardware

| Service | macOS | Linux | Windows |
| --- | --- | --- | --- |
| System appearance | Supported | GNOME settings with `GTK_THEME` fallback | Supported |
| Battery and external-power state | IOKit | Kernel power-supply interface | `GetSystemPowerStatus` |
| Idle duration | CoreGraphics | XScreenSaver on X11/XWayland | `GetLastInputInfo` |
| Aggregate CPU counters | Mach host counters | `/proc/stat` | `GetSystemTimes` |
| Speech synthesis and voice discovery | AppKit speech | Speech Dispatcher | SAPI |
| Speech recognition and language discovery | Speech.framework and AVFoundation | Unavailable: no standard system STT service | Installed SAPI recognizers |
| Biometric authentication | LocalAuthentication | fprintd over D-Bus | Windows Hello |
| USB, Bluetooth, serial, and HID enumeration | Supported | Supported through udev | Supported |
| NFC enumeration | Unavailable | Unavailable | Unavailable |
| Display, clipboard, and hardware changes | Polling monitor | Polling monitor | Polling monitor |

Biometric support is a runtime result. It depends on hardware, enrolled credentials, permissions, and the relevant operating-system service. Check `NativeDesktop.biometric.info.available?` immediately before presenting authentication.

Linux idle duration returns zero when no X11 or XWayland display is available.

Speech-recognition language discovery reports BCP 47 tags supported by the system recognizer. A listed macOS language may still be temporarily unavailable when its recognizer requires network access, so callers should also check `SpeechRecognizer#available?`. Windows recognition requires an installed SAPI recognition language pack. Linux returns an empty language list and reports recognition unavailable.

## Runtime attachment

GUI controls require an attached `NativeDesktop::Runtime`. Snapshot services such as CPU counters, hardware enumeration, trash, autostart, URL schemes, and single-instance locking do not.

Theme, power, and idle snapshots work without GUI dispatch, while their monitors require the runtime’s background executor. See [Host integration](host-integration.md) for the threading and shutdown contract.

## Build-time feature flags (Linux)

Some Linux subsystems depend on optional native libraries that may not be installed everywhere. By default every subsystem is compiled and links its library; a missing library produces a link error. To build without one of these optional subsystems, pass the matching `-D` flag to `crystal`:

| Flag | Disabled subsystem | Optional library |
| --- | --- | --- |
| `-Dnative_desktop_no_tray` | System tray | AppIndicator 3 |
| `-Dnative_desktop_no_notifications` | Desktop notifications | libnotify |
| `-Dnative_desktop_no_speech` | Speech synthesis and recognition | Speech Dispatcher |
| `-Dnative_desktop_no_biometric` | Biometric authentication | fprintd (D-Bus) |
| `-Dnative_desktop_no_hardware` | USB/Bluetooth/serial/HID enumeration | libudev |

A disabled subsystem is omitted entirely: its accessor and any capability or permission registrations it owns are not compiled, so `NativeDesktop.tray` (for example) does not exist in the build. For the subsystems that register a cataloged feature — notifications, speech, biometrics, and hardware — `Capabilities.status` then reports `Unavailable` rather than failing at link time.

Core Linux dependencies — GTK 3, GDK, GLib/GObject/GIO, X11, and XScreenSaver — remain required and are not optional.

## Capability and permission discovery

Use `NativeDesktop.capabilities.status(feature)` before presenting a feature. The result distinguishes supported, unsupported, temporarily unavailable, permission-required, and host-integration-required states. This is especially important for taskbar features, speech recognition, notification actions, drop targets, and activation delivery.

`NativeDesktop.permissions` provides common preflight, request, and settings operations. Feature-specific APIs remain available when the operating system returns more detailed information.
