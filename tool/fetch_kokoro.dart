// Build-time helper that downloads the Kokoro-en-v0_19 neural TTS model
// (English-only, ~140 MB after extraction) into assets/voices/kokoro/.
//
// Usage:
//   dart run tool/fetch_kokoro.dart
//
// The model is the only neural-TTS variant we ship. The app at runtime
// never touches the network — this tool runs on a developer machine, and
// the resulting voice asset is bundled into the application package.
//
// Source: https://github.com/k2-fsa/sherpa-onnx (Apache-2.0).
// License of the model: Apache-2.0 (Kokoro-82M base) + per-voice notes.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

const String _archiveUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
    'kokoro-en-v0_19.tar.bz2';

const String _destDir = 'assets/voices/kokoro';

Future<int> main(List<String> args) async {
  final dest = Directory(p.absolute(_destDir));
  if (!await dest.exists()) await dest.create(recursive: true);

  stdout.writeln('Fetching Kokoro neural TTS model …');
  stdout.writeln('  (build-time only — the app stays 100% offline)');

  final tmp = await Directory.systemTemp.createTemp('kokoro_');
  final archivePath = p.join(tmp.path, 'kokoro-en.tar.bz2');
  try {
    final bytes = await _download(_archiveUrl);
    await File(archivePath).writeAsBytes(bytes, flush: true);
    final mb = (bytes.length / 1024 / 1024).toStringAsFixed(1);
    stdout.writeln('  downloaded $mb MB');

    stdout.writeln('Extracting …');
    final extracted = _extractTarBz2(bytes);
    var fileCount = 0;
    var totalBytes = 0;
    for (final entry in extracted) {
      if (entry.isFile) {
        // Strip the top-level "kokoro-en-v0_19/" prefix so files land
        // directly in assets/voices/kokoro/.
        final relName = entry.name.contains('/')
            ? entry.name.substring(entry.name.indexOf('/') + 1)
            : entry.name;
        if (relName.isEmpty) continue;
        final out = File(p.join(dest.path, relName));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.content as List<int>, flush: true);
        fileCount++;
        totalBytes += (entry.content as List<int>).length;
      }
    }
    final totalMb = (totalBytes / 1024 / 1024).toStringAsFixed(1);
    stdout.writeln('OK. Wrote $fileCount files ($totalMb MB) to ${dest.path}');
    stdout.writeln();
    stdout.writeln('Files now in $_destDir:');
    final entries = await dest.list(recursive: true).toList();
    for (final f in entries.whereType<File>()) {
      final relPath = p.relative(f.path, from: dest.path);
      final size = (await f.length() / 1024).toStringAsFixed(1);
      stdout.writeln('  $relPath  ($size KB)');
    }
    stdout.writeln();
    stdout.writeln('Next: add the asset directory to pubspec.yaml under '
        'flutter.assets if not already there, then `flutter pub get`.');
    return 0;
  } catch (e, st) {
    stderr.writeln('Failed: $e');
    stderr.writeln(st);
    return 1;
  } finally {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  }
}

Future<Uint8List> _download(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    var current = Uri.parse(url);
    HttpClientResponse response;
    var redirects = 0;
    while (true) {
      final request = await client.getUrl(current);
      request.followRedirects = false;
      response = await request.close();
      if (response.statusCode == 200) break;
      if ((response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) &&
          redirects < 10) {
        final loc = response.headers.value('location');
        if (loc == null) throw const HttpException('redirect without location');
        current = current.resolve(loc);
        redirects++;
        await response.drain<void>();
        continue;
      }
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode} for $current');
    }
    final builder = BytesBuilder();
    var total = 0;
    var lastReport = 0;
    final expected = response.contentLength;
    await for (final chunk in response) {
      builder.add(chunk);
      total += chunk.length;
      if (total - lastReport >= 4 * 1024 * 1024) {
        lastReport = total;
        final mb = (total / 1024 / 1024).toStringAsFixed(1);
        if (expected > 0) {
          final pct = (total * 100 / expected).toStringAsFixed(0);
          stdout.write('\r  $mb MB ($pct %)');
        } else {
          stdout.write('\r  $mb MB');
        }
      }
    }
    stdout.writeln();
    return builder.toBytes();
  } finally {
    client.close();
  }
}

List<ArchiveFile> _extractTarBz2(Uint8List bz2Bytes) {
  final tarBytes = BZip2Decoder().decodeBytes(bz2Bytes);
  final archive = TarDecoder().decodeBytes(tarBytes);
  return archive.files;
}
