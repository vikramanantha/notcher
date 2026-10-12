# Notcher

Turns the MacBook notch into a little media + volume widget. What's playing sits on the left of the notch and the audio output on the right. Hover over it to get playback controls, a volume slider and an output device picker.

See [initial_plan.md](initial_plan.md) for the design notes.

## Build & run

Requires macOS 14+ and Xcode command line tools.

```sh
./build.sh          # builds build/Notcher.app
./build.sh --run    # builds, then (re)launches it
```

The app has no Dock icon. Hover over the notch and use the gear next to it to quit or turn on Launch at Login. Launch at Login registers the app from wherever it is, so copy `build/Notcher.app` to `/Applications` first.

## Layout

| Path | What |
| --- | --- |
| `Sources/Notcher/NotchWindowController.swift` | The panel over the notch: placement, hover/click-through, hiding for full-screen apps and when no notched screen is present |
| `Sources/Notcher/NotchView.swift` | SwiftUI: the notch shape, collapsed ears, expanded panel, sliders |
| `Sources/Notcher/NotchModel.swift` | Shared sizes and expanded state, so the hit areas match what's drawn |
| `Sources/Notcher/AudioController.swift` | CoreAudio: default output, volume, mute, device list (listeners, no polling) |
| `Sources/Notcher/NowPlayingController.swift` | Now playing info and controls through mediaremote-adapter |
| `Vendor/mediaremote-adapter` | Vendored [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3, commit in `COMMIT`) |

## Now playing

Since macOS 15.4, third-party apps can't use MediaRemote directly. `build.sh` compiles the vendored adapter into `MediaRemoteAdapter.framework` inside the app bundle. At runtime the app runs `/usr/bin/perl mediaremote-adapter.pl <framework> stream`. Perl is Apple-signed and allowed to load MediaRemote, and the adapter streams JSON lines back. Play/pause, next/previous and seek go through the same script.

Because of this the app isn't sandboxed, and it can't go on the App Store.

## Known limits (v1)

- The system volume HUD still appears when you use the volume keys.
- Built-in notched display only. External monitors don't get a fake notch.
- No AppleScript fallback. If a future macOS update breaks the adapter, the media side shows "Nothing playing".
