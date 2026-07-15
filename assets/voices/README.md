# Neural TTS voice models

The neural-TTS voice models live here when bundled. The Kokoro English voice
model is ~140 MB and is **not** committed to git — every developer runs the
fetch tool once:

```sh
dart run tool/fetch_kokoro.dart
```

After it finishes, this directory will contain `kokoro/model.onnx`,
`kokoro/voices.bin`, `kokoro/tokens.txt`, and a few config files. The Flutter
asset bundler picks them up automatically because `assets/voices/` is
declared under `flutter.assets` in `pubspec.yaml`.

These voice files ship inside the final App Store / Play Store package; the
running app never downloads anything.
