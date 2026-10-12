# Mac Notcher (name is WIP)
Vikram Anantha
Oct 2026

## Motiviation

I have seen a few mac apps that use the Mac Notch to store some information, and when you hover over it you can do stuff.
I want to do the same

## Initial Idea

The Mac Notch will show the media currently playing on the left side of the notch, and the volume / audio output status on the right side.
When hovering over it, it will basically replicate the media playing and volume control menus.

There isn't much else to it.

## Claude's Notes
### Stack
- Swift + SwiftUI for the views, AppKit for the window. Menu-bar-style app with no Dock icon (`LSUIElement = YES` in Info.plist).
- Launch at login with `SMAppService.mainApp.register()`.
- Not sandboxed (the now-playing workaround below won't run in the sandbox), so no App Store. Run it locally or sign it with a Developer ID.

### Drawing over the notch
- Use a borderless, non-activating `NSPanel` with a clear background. Put it above the menu bar (`level = .statusBar` or higher) and set `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]` so it stays put across Spaces.
- Full-screen apps: **hide it.** Leaving `.fullScreenAuxiliary` out of `collectionBehavior` should already keep the panel off full-screen Spaces. If that isn't enough, check whether the frontmost window covers the whole screen when `NSWorkspace.activeSpaceDidChangeNotification` fires, and hide it then.
- Finding the notch: **built-in display only.** Pick the `NSScreen` with `safeAreaInsets.top > 0`. If there isn't one (lid closed, or a Mac with no notch), don't show the panel. External monitors never get a fake notch. `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` (macOS 12+) give the usable rects on each side. Notch width = screen width − left width − right width.
- Collapsed state: a black pill a bit wider than the notch, with album art or a playing indicator in the left "ear" and the volume icon in the right "ear". Keep it black so it blends into the notch.
- When nothing is playing, the left ear shrinks away and the pill becomes lopsided: notch + volume ear only. Animate the width change so it doesn't jump.
- Expanded state: on hover, animate the pill down and out into a rounded panel. SwiftUI `.onHover` plus a spring animation is enough.
- Gotcha: a big invisible window blocks clicks to the menu bar underneath it. Either size the window to the collapsed pill and resize it on hover, or keep the window big and toggle `ignoresMouseEvents` based on where the mouse is.
- Watch `NSApplication.didChangeScreenParametersNotification` to reposition when displays change (lid closed, external monitor plugged in or removed). Show or hide the panel depending on whether a notched screen is present.

### Volume / audio output (right side)
- CoreAudio, no permissions needed:
  - Default output device: `kAudioHardwarePropertyDefaultOutputDevice`.
  - Volume: `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (get and set, 0–1).
  - Mute: `kAudioDevicePropertyMute`.
  - Device name: `kAudioObjectPropertyName`. Transport type (`kAudioDevicePropertyTransportType`) tells you which icon to show: built-in speakers, Bluetooth/AirPods, AirPlay, HDMI.
- Use `AudioObjectAddPropertyListenerBlock` to get callbacks when the device, volume or mute changes. That's better than polling.
- Expanded view: a volume slider, a mute toggle and a list of output devices (enumerate with `kAudioHardwarePropertyDevices` and keep only the ones with output streams). Click one to set it as the default.
- Gotcha: some devices (HDMI and some USB DACs) have no software volume, so the slider should disable itself for those.
- Gotcha: the system volume HUD will still appear when you use the volume keys. Hiding it isn't really possible without hacks, so live with it for v1.

### Now playing (left side) — the hard part
- The system-wide "now playing" info comes from the private `MediaRemote.framework` (`MRMediaRemoteGetNowPlayingInfo`, `MRMediaRemoteRegisterForNowPlayingNotifications`, `MRMediaRemoteSendCommand` for play/pause/next/prev).
- **Since macOS 15.4, Apple blocks MediaRemote for third-party apps.** The common workaround is [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), which loads the framework through the system `/usr/bin/perl` (Apple-signed, so it's allowed) and streams JSON back to your app. Check that it still works on the current macOS before building on it.
- Fallback: script Spotify and Apple Music directly with AppleScript / ScriptingBridge. This is reliable but only covers those two apps (no browser audio), and it asks for Automation permission.
- Expanded view: album art, title/artist, a scrubber (elapsed + duration + playback rate, which you interpolate locally) and prev/play-pause/next. Optional: tint the background with the album art's dominant color.

### Prior art to read before building
- **Boring Notch** (open source, `TheBoredTeam/boring.notch`): the closest match to this idea. Reading its window and notch-sizing code will save a lot of trial and error.
- **DynamicNotchKit** (Swift package): handles the notch window and animation. It could be the whole window layer.
- **NotchDrop** (open source), **NotchNook** and **Alcove** (paid): good for seeing how the UI feels.

### Suggested build order
1. A black pill window sitting exactly on the notch that stays there across Spaces and full screen.
2. Hover expand/collapse animation, with clicks still passing through to the menu bar.
3. Volume: read, show and listen for changes, then the slider and output device picker.
4. Now playing via mediaremote-adapter: show info first, then the controls.
5. Polish: launch at login, hiding for full-screen apps and when there's no notched screen, settings (maybe a menu bar icon to quit).

### Decisions
- Media is on the left side and volume is on the right.
- Hide it while a full-screen app is in front.
- Built-in notched display only. No fake notch on external monitors.
- When nothing is playing, the media (left) ear shrinks away.
