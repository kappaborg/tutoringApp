// Offline-enforcement CI guard. Run via:
//   dart run tool/check_offline.dart
//
// Exits non-zero if it finds:
//   • a banned dependency in pubspec.yaml or pubspec.lock
//   • a banned API token in lib/ (with one documented allowlisted file)
//   • Android INTERNET permission without tools:node="remove"
//   • macOS network entitlement set to true

import 'dart:io';

const bannedPackages = <String>[
  'http',
  'dio',
  'chopper',
  'retrofit',
  'graphql',
  'graphql_flutter',
  'web_socket_channel',
  'firebase_core',
  'firebase_analytics',
  'firebase_crashlytics',
  'google_sign_in',
  'google_analytics',
  'google_mlkit_translation',
  'google_mlkit_text_recognition',
  'apple_translation',
  'sentry_flutter',
];

const bannedApiPatterns = <String>[
  r'\bHttpClient\b',
  r'\bSocket\.connect\b',
  r'\bRawSocket\b',
  r'\bWebSocket\.connect\b',
  r'\bdart:html\b',
];

const allowMarker = 'offline-guard:allow';

Future<int> main() async {
  final offenders = <String>[];

  // 1. pubspec.yaml — only DIRECT deps. Transitive deps in pubspec.lock are
  //    unavoidable (Flutter itself pulls http for its tooling); we just make
  //    sure they are never used from our `lib/` code (step 2).
  final pubspec = File('pubspec.yaml');
  if (await pubspec.exists()) {
    final src = await pubspec.readAsString();
    final inDeps = RegExp(
      r'^(dependencies|dev_dependencies):\s*$([\s\S]*?)(?=^[a-zA-Z_]+:\s*$|\Z)',
      multiLine: true,
    );
    for (final match in inDeps.allMatches(src)) {
      final block = match.group(2) ?? '';
      for (final pkg in bannedPackages) {
        if (RegExp('^\\s{2,}$pkg\\s*:', multiLine: true).hasMatch(block)) {
          offenders.add('pubspec.yaml: banned direct dependency "$pkg"');
        }
      }
    }
  }

  // 1b. pubspec.lock — flag only entries marked `dependency: "direct main"` or
  //    `dependency: "direct dev"` for banned packages. Transitive entries are
  //    allowed because we cannot stop them from existing, only from being used.
  final lock = File('pubspec.lock');
  if (await lock.exists()) {
    final src = await lock.readAsString();
    for (final pkg in bannedPackages) {
      final r = RegExp(
        '^  $pkg:\\s*\$\\s+dependency: "direct',
        multiLine: true,
      );
      if (r.hasMatch(src)) {
        offenders.add('pubspec.lock: banned direct dependency "$pkg"');
      }
    }
  }

  // 2. lib/*.dart
  final libDir = Directory('lib');
  if (await libDir.exists()) {
    final patterns = bannedApiPatterns.map(RegExp.new).toList();
    await for (final entity in libDir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = await entity.readAsString();
      if (src.contains(allowMarker)) continue;
      for (final r in patterns) {
        if (r.hasMatch(src)) {
          offenders.add('${entity.path}: banned API "${r.pattern}"');
        }
      }
    }
  }

  // 3. Android Manifest — only the main (release) manifest is checked.
  //    debug and profile manifests legitimately require INTERNET so the
  //    Flutter tool can hot-reload over USB/Wi-Fi; those flavors never ship
  //    to end users.
  final mainManifest = File('android/app/src/main/AndroidManifest.xml');
  if (await mainManifest.exists()) {
    final xml = await mainManifest.readAsString();
    final hasInternet = xml.contains('android.permission.INTERNET');
    final hasRemove = xml.contains('tools:node="remove"');
    if (hasInternet && !hasRemove) {
      offenders.add(
        '${mainManifest.path}: declares android.permission.INTERNET without tools:node="remove"',
      );
    }
  }

  // 4. macOS entitlements
  //    - network.client TRUE is banned in both Debug and Release (outbound).
  //    - network.server TRUE is banned in Release, allowed in Debug because
  //      the Dart VM service binds a localhost socket for hot reload.
  for (final path in const [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    final f = File(path);
    if (!await f.exists()) continue;
    final xml = await f.readAsString();
    final isRelease = path.endsWith('Release.entitlements');
    final clientTrue = RegExp(
      r'<key>com\.apple\.security\.network\.client</key>\s*<true/>',
    );
    final serverTrue = RegExp(
      r'<key>com\.apple\.security\.network\.server</key>\s*<true/>',
    );
    if (clientTrue.hasMatch(xml)) {
      offenders.add('$path: network.client entitlement is TRUE');
    }
    if (isRelease && serverTrue.hasMatch(xml)) {
      offenders.add('$path: network.server entitlement is TRUE in Release');
    }
  }

  if (offenders.isEmpty) {
    stdout.writeln('offline guard: OK — no banned dependencies or APIs found.');
    return 0;
  }
  stderr.writeln('offline guard: FAILED');
  for (final o in offenders) {
    stderr.writeln('  - $o');
  }
  exitCode = 1;
  return 1;
}
