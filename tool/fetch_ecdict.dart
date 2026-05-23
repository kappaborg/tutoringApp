// Build-time helper: downloads the ECDICT CSV from GitHub and rebuilds
// assets/dict/ecdict.db with full coverage (~70 000 entries).
//
// This is the ONLY tool in the project allowed to touch the network — and
// it never runs on user devices. The app itself remains 100 % offline at
// runtime. The CSV is fetched once on a developer machine, the resulting
// .db is committed, and end users never see a network call.
//
// Usage:
//   dart run tool/fetch_ecdict.dart                          # auto download
//   dart run tool/fetch_ecdict.dart --url <csv-url>          # custom source
//   dart run tool/fetch_ecdict.dart --local /path/to.csv     # use a file
//   dart run tool/fetch_ecdict.dart --keep                   # keep the CSV
//
// ECDICT is MIT-licensed (https://github.com/skywind3000/ECDICT). We only
// ship the produced .db; the CSV itself is not redistributed.

import 'dart:io';

import 'package:path/path.dart' as p;

// Candidate CSV URLs in priority order. We try each until one returns 200.
// Both are mirrors of the same upstream ECDICT data.
const _candidateUrls = <String>[
  'https://raw.githubusercontent.com/skywind3000/ECDICT/master/ecdict.csv',
];

Future<int> main(List<String> args) async {
  String? overrideUrl;
  String? localPath;
  var keepCsv = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--url':
        if (i + 1 >= args.length) {
          stderr.writeln('--url requires a value.');
          return 2;
        }
        overrideUrl = args[++i];
      case '--local':
        if (i + 1 >= args.length) {
          stderr.writeln('--local requires a path.');
          return 2;
        }
        localPath = args[++i];
      case '--keep':
        keepCsv = true;
      case '-h':
      case '--help':
        _printUsage();
        return 0;
      default:
        stderr.writeln('Unknown argument: $a');
        _printUsage();
        return 2;
    }
  }

  // Resolve the CSV path: --local skips network entirely.
  String csvPath;
  Directory? tempDir;
  if (localPath != null) {
    if (!await File(localPath).exists()) {
      stderr.writeln('No such file: $localPath');
      return 1;
    }
    csvPath = localPath;
    stdout.writeln('Using local CSV: $csvPath');
  } else {
    tempDir = await Directory.systemTemp.createTemp('ecdict_fetch_');
    final urls = overrideUrl != null ? [overrideUrl] : _candidateUrls;
    String? downloaded;
    for (final url in urls) {
      stdout.writeln('Fetching $url …');
      try {
        downloaded = await _download(url, tempDir);
        break;
      } catch (e) {
        stderr.writeln('  → failed: $e');
      }
    }
    if (downloaded == null) {
      stderr.writeln(
        '\nCould not download ECDICT automatically. Two paths:\n'
        '  1. Grab the CSV manually from https://github.com/skywind3000/ECDICT\n'
        '     (look in the "Releases" tab for the latest .zip / .csv asset),\n'
        '     then run:\n'
        '         dart run tool/fetch_ecdict.dart --local /path/to/ecdict.csv\n'
        '  2. Or pass a known mirror URL:\n'
        '         dart run tool/fetch_ecdict.dart --url <https-url>',
      );
      return 1;
    }
    csvPath = downloaded;
  }

  // Hand off to build_dict.
  stdout.writeln('Building dictionary from CSV …');
  final result = await Process.start(
    Platform.resolvedExecutable, // current `dart` binary
    ['run', 'tool/build_dict.dart', '--full', csvPath],
    mode: ProcessStartMode.inheritStdio,
  );
  final exit = await result.exitCode;
  if (exit != 0) {
    stderr.writeln('build_dict exited with code $exit.');
    return exit;
  }

  // Clean up the temp CSV unless --keep.
  if (tempDir != null && !keepCsv) {
    await tempDir.delete(recursive: true);
  } else if (tempDir != null) {
    stdout.writeln('CSV kept at ${tempDir.path}');
  }

  stdout.writeln('\nDone. Commit assets/dict/ecdict.db.');
  return 0;
}

Future<String> _download(String url, Directory dir) async {
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
        if (loc == null) {
          throw const HttpException('redirect without location');
        }
        current = current.resolve(loc);
        redirects++;
        await response.drain<void>();
        continue;
      }
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode} for $current');
    }
    final filename = p.basename(current.path).isEmpty
        ? 'ecdict.csv'
        : p.basename(current.path);
    final dest = File(p.join(dir.path, filename));
    final sink = dest.openWrite();
    var total = 0;
    final expected = response.contentLength;
    var lastReport = 0;
    await for (final chunk in response) {
      sink.add(chunk);
      total += chunk.length;
      if (total - lastReport >= 2 * 1024 * 1024) {
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
    await sink.close();
    final mb = (total / 1024 / 1024).toStringAsFixed(2);
    stdout.writeln('\r  done: $mb MB at ${dest.path}');
    return dest.path;
  } finally {
    client.close();
  }
}

void _printUsage() {
  stdout.writeln('''
fetch_ecdict — build-time helper to populate assets/dict/ecdict.db

Usage:
  dart run tool/fetch_ecdict.dart
  dart run tool/fetch_ecdict.dart --url <csv-url>
  dart run tool/fetch_ecdict.dart --local <path-to-csv>
  dart run tool/fetch_ecdict.dart --keep                 # don't delete CSV

The fetched CSV is fed to tool/build_dict.dart --full.
This tool is the ONLY part of the project that touches the network, and it
runs on a developer machine only. The shipped app makes no network calls.
''');
}
