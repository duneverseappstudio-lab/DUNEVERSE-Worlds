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

The clean source snapshot passed 105 Flutter tests and 70 Python tests on 2026-11-25. These test counts do not establish phone startup or safety on real user data. No secrets, user databases, account/session files, build products, or private conversation history belong in this repository.

## Font
Cairo font is distributed under the SIL Open Font License. See `app/assets/fonts/OFL.txt`.

## Offline backup safety notes (review hardening)
The offline project validator now rejects triggers, views, virtual tables, application-defined indexes, unexpected project tables/columns, out-of-editor-range geometry and unsafe control characters in object names. The legacy single-world format is not a project import format; it must not be used to bypass project validation. Both formats reject executable schema. Restore publishes only the exact validated main database bytes, without validation-created WAL/SHM files.

Export must read the original live SQLite database through the SQLite backup API. Do not copy just the main `.sqlite` file from a running app: committed data may still be in its WAL and a main-only copy can look valid while stale. Do not copy the main file and WAL independently as a replacement for the backup API. A read-only SQLite export can still create empty WAL/SHM files beside a WAL-mode source; this is a known remaining side effect. Original database content is not rewritten, but the source directory is not guaranteed untouched. This is one reason the utility remains experimental and restricted to disposable data.

Android OS backup policy is still implicit in the platform template. It is not this offline utility, and its behavior has not been audited on a physical device. No Android startup fix or real-data backup-safety claim follows from these changes.

### Follow-up data and local-publication checks
Project history is an audit log, not the current in-memory editor undo stack. Validation now checks positive unique history IDs, existing same-world object references, JSON snapshot shape/identity, safe names and editor-range geometry. Before snapshots accept the SQLite row shape (including `world_id`); after snapshots accept the app's serialized object shape. World names follow the same safe-name policy, and per-world `schema_version` must be 1, as written by the current app even when SQLite `user_version` is 2. Older experimental packs containing placeholder/malformed history or incompatible metadata are intentionally rejected, not repaired silently.

Publication requires a destination parent owned by the current user with no group/world write bits. Use a private owned output directory, not `/tmp` itself or a shared-writable directory. Staging inode and byte checks detect the tested pre-publication replacement and modification cases. These checks do not make publication race-proof against a concurrent process running as the same user (or root) with access to the destination parent. That case remains outside the utility's threat model; do not use an output directory while another process is modifying it. This conditional local-filesystem issue does not establish remote exposure or explain Android startup.

## Startup observability candidate
The app now paints an Arabic loading screen before beginning storage initialization, offers a generic error/retry state, and records phase labels without database paths or raw errors. Async support-directory lookup and directory creation each have a 15-second timeout. Retry is single-flight, failed constructor handles are closed, and late results are closed if the startup widget has gone away. Timeouts do not cancel underlying platform/filesystem operations; a retry may overlap a previously timed-out directory operation. Synchronous SQLite initialization and native Flutter/plugin startup cannot be interrupted by these Dart timeouts. Local widget tests and an ARM64 build do not prove physical ARM64 opening or fix the reported phone failure. No new APK is presented as launch-tested.
