# Windows configuration notes

## SQLite
The app uses `sqflite_common_ffi` on Windows; `main.dart` calls
`sqfliteFfiInit()` and sets `databaseFactory = databaseFactoryFfi` when the
platform is Windows/macOS/Linux. No extra packaging is required at build time
— the FFI library ships with the package.

## TTS
`flutter_tts` uses Windows SAPI voices. If the user has no English voice
installed, the reader will show the on-first-launch SnackBar pointing them to
**Settings → Time & Language → Speech**.

## Network
Windows does not require any explicit capability removal — the Flutter
Windows runner does not request `internetClient`. Do not add it.

## Files
`file_picker` is used for image selection on desktop. No sandbox bookmark is
needed because we immediately copy the picked image into the app's documents
directory.
