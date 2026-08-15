# Walkie Talkie

A fully offline push-to-talk (walkie-talkie) app built with Flutter. One codebase
runs on **Android**, **iOS** and **Windows**.

No internet is required: devices talk to each other over your local Wi-Fi
network using **UDP broadcast**. Press and hold the button to talk, release to
listen — just like a real radio.

## How it works

```
+----------------------+   UDP broadcast (port 48005)   +----------------------+
|  Android / iOS / PC  | <----------------------------> |  Android / iOS / PC  |
+----------------------+                                 +----------------------+
```

- **Discovery** — every device broadcasts a tiny JSON *beacon* every 2 seconds.
  The app shows live peers and removes them if they go quiet for ~8 seconds.
- **Voice** — while you hold the button, the microphone is recorded as 16 kHz
  mono 16-bit PCM, cut into ~300 ms chunks, wrapped in WAV containers and
  broadcast as UDP datagrams.
- **Playback** — incoming chunks are played in order through the speaker.
- **Half-duplex** — the channel is marked *busy* while another device talks and
  you cannot transmit over it. Your own voice is never played back to you.
- **Channels** — up to 9 independent channels (like radio frequencies); devices
  on different channels ignore each other.
- **Fully offline** — everything runs on the local network. Nothing is sent to
  the internet, no server is required.

## Project layout

```
lib/
  main.dart                        App entry point & theme
  src/
    config.dart                    Tunables (port, chunk size, timeouts)
    models.dart                    Peer & radio status models
    protocol.dart                  Beacon/voice packet encode + decode
    wav.dart                       WAV container builder
    walkie_controller.dart         UDP transport, mic, playback, state
    home_page.dart                 Main screen
    widgets/ptt_button.dart        Hold-to-talk button
test/                              Unit tests (WAV + protocol)
```

## Requirements

| Platform  | Toolchain |
|-----------|-----------|
| **Android** | [Flutter SDK](https://docs.flutter.dev/get-started/install) + Android Studio / Android SDK |
| **iOS**     | Flutter SDK + Xcode (macOS only) |
| **Windows** | Flutter SDK + [Visual Studio 2022](https://visualstudio.microsoft.com/) with the "Desktop development with C++" workload. Windows 10/11 **Developer Mode** must be enabled (`Start → Settings → For developers → Developer Mode`) for Flutter to build plugins. |

This project targets Flutter 3.47+ (Dart 3.13+).

## Build & run

### Windows

```powershell
flutter pub get
flutter run -d windows
```

Or build a release installer/exe:

```powershell
flutter build windows
```

The executable lands in `build\windows\x64\runner\Release\`.

### Android

```powershell
flutter pub get
flutter run                # with a device/emulator connected
flutter build apk          # release APK in build\app\outputs\flutter-apk\
```

### iOS (requires a Mac)

```bash
flutter pub get
flutter run                # with a device/simulator connected
flutter build ios --no-codesign   # or sign with your team for a device
```

iOS will prompt for **microphone** and **local network** access on first launch —
allow both.

## Using it

1. Connect all devices to the **same Wi-Fi network** (or a phone's hotspot).
2. Open the app on each device. Give them a second to discover each other.
3. Press and hold the red button to talk. Release to listen.

## Automatic builds with GitHub Actions

Push this project to a GitHub repo and it builds for you in the cloud — no local
toolchains needed:

- **On every push to `main`** → builds a Windows `.exe` and Android `.apk` and
  uploads them as **Artifacts** (Actions → *Build* run → Artifacts).
- **On every `v*` tag** (e.g. `v1.0.0`) → same builds, plus a **GitHub Release**
  is created automatically with the `.exe` (zipped) and `.apk` attached:

  ```bash
  git tag v1.0.0
  git push origin v1.0.0
  ```

- You can also trigger a build manually: **Actions → Build → Run workflow**.

## Troubleshooting

- **Peers never appear**
  - All devices must be on the same network/subnet.
  - Some routers/hotspots enable *AP/client isolation*, which blocks
    device-to-device traffic. Disable it or use a normal router/hotspot.
  - On iOS, make sure the **Local Network** permission was granted for the app
    (Settings → Privacy & Security → Local Network).
- **No voice heard**
  - Grant the **microphone** permission (the app shows a banner if denied).
  - Check that both devices are on the same channel (the channel icon in the
    top bar).
  - Turn volume up and check the channel is not busy.
- **Channel stuck on "busy"** — wait ~1 second after the other side stops
  talking; half-duplex radios keep the channel busy briefly.
- **Windows build errors about symlinks / Developer Mode** — enable Windows
  Developer Mode, restart the terminal, and run `flutter clean` first.
- **Latency** — chunks are ~300 ms, so end-to-end delay is roughly 0.5–1 s per
  direction. This is normal for chunked voice; it is a walkie-talkie, not a
  phone call.

## Notes & limitations

- Offline communication only works for devices on the same local network.
  Devices on different networks (e.g. one on 4G) cannot reach each other.
- iOS builds require a Mac and an Apple developer setup to install on a device.
- Voice is uncompressed PCM, so it needs a decent Wi-Fi link. On very congested
  or slow networks, reduce `chunkSamples` in `lib/src/config.dart` if needed.
