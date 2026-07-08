# kio

A Flutter prototype for a fullscreen mobile MMD player/exporter. The app is intentionally one workspace screen with a collapsible left sidebar and floating controls over a fullscreen player.

## Implemented in this package

- One-screen fullscreen player workspace.
- Left sidebar with two independently collapsible sections:
  - Projects: default project plus a `New project` action.
  - Assets: import buttons and typed asset list.
- Asset import for four types: Model, Motion, Music, Camera.
- Imported assets are copied into the app's private document storage.
- Duplicate import prevention by SHA-256 checksum per asset type.
- Long-press an asset list item to rename its display name.
- Different icons for different asset types.
- Right-side import flyout: Import -> Model / Motion / Music / Camera.
- Right-side camera preset flyout.
- Empty player area supports drag-to-orbit and pinch-to-zoom camera interaction.
- Applied model assets are rendered in the fullscreen player with a built-in PMX/PMD mesh preview.
- The current project's applied Model / Motion / Music / Camera assets are visible on the player.
- Bottom playback progress and playback controls.
- VMD motion playback drives a lightweight PMX/PMD bone skinning preview for common MMD bones.
- VMD camera playback drives the preview camera.
- Export writes a PNG frame-sequence ZIP plus `manifest.json` to `Downloads/kio_exports`.
- Modern dark glass UI with animated panels and flyouts.
- UI copy is English-only.
- Inter typography through `google_fonts`.
- Dart and native Android crash handlers.
- Crash logs are written to `Downloads/kio_crash_logs` on Android 10+ through MediaStore, with fallback to app files.
- Fixed Android release signing file included for reproducible prototype APK signing.
- GitHub Actions workflow builds and uploads a signed APK artifact.

## Build locally

```bash
flutter pub get
flutter build apk --release
```

If the Android Gradle wrapper is missing locally, generate it once:

```bash
cd android
gradle wrapper --gradle-version 8.10.2 --distribution-type all
```

The GitHub Actions workflow does this automatically.

## GitHub Actions APK

Push the repository to GitHub and run **Actions -> Build signed APK**. The workflow uploads `kio-release-apk`, containing `app-release.apk`.

The workflow uses `subosito/flutter-action@v2` with stable Flutter and cache enabled. `subosito/flutter-action` is a common Flutter setup action for GitHub Actions, and the official Flutter Android deployment docs describe release signing for Android apps.

## Prototype signing note

This repository includes a fixed demo keystore at:

```text
android/app/kio-release.keystore
android/key.properties
```

Password and alias are intentionally committed for reproducible prototype builds. Replace them before production release.

## Scope note

This is still not a full nanoem port. It supports lightweight PMX/PMD mesh rendering, common-bone VMD motion playback, VMD camera playback, audio playback, manual camera presets, and PNG frame-sequence ZIP export. It does not yet implement nanoem's full material/texture renderer, full Shift-JIS bone-name coverage, inverse-kinematics solving, physics, morph animation, NMD playback, or MP4 encoding.
