# DUNEVERSE Worlds Trial

Flutter and Python development snapshot. This is an incomplete 2D world editor, not a production release or the planned 3D product.

## Current features
- Named independent worlds with stars, planets, moons and individual space rocks.
- Drag placement, movement, size and name edits with local SQLite storage.
- Saved circular paths with a chosen moving host, an independent period (1 to 3600 seconds) and direction per body. No gravity solver or freehand paths.
- Nested paths, such as a moon following a moving planet.

## Current limits
The latest ARM64 trial was reported not to open on the user's phone. The failure stage and cause remain unverified. Prior x64 emulator startup is not ARM64 runtime proof. Do not treat this snapshot as a fix.

No 3D integration, asteroid-belt generation, AdMob SDK, store release, cloud sync, or Android backup interface. Orbit changes are not covered by undo. Python backup is an experimental Linux-only utility and must only be tested on disposable data until the broader schema validation work is complete.

The Android package is `studio.duneverse.imperator_worlds_trial`. It is separate from the earlier trial and starts empty, without importing earlier worlds. Debug signing is used for development builds, never a production signing key.

## Development
Validated baseline: Flutter 3.50.1 / Dart 3.14, Java 17, Android SDK 36. Platform templates for other targets are not proof of platform support.

```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
cd ..
python3 -m unittest discover -s python_tools -v
```

The clean source snapshot passed 97 Flutter tests and 55 Python tests on 2026-11-24. These test counts do not establish phone startup or safety on real user data. No secrets, user databases, account/session files, build products, or private conversation history belong in this repository.

## Font
Cairo font is distributed under the SIL Open Font License. See `app/assets/fonts/OFL.txt`.
