import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Greps the `lib/` tree for banned tokens that imply outbound network usage.
/// `lib/services/debug_network_probe.dart` is exempt — it is debug-only and
/// documented as the one allowlisted file (must contain `offline-guard:allow`).
void main() {
  test('lib/ contains no banned network tokens', () async {
    final bannedPackages = <RegExp>[
      RegExp(r"package:http(_io)?/"),
      RegExp(r'package:dio/'),
      RegExp(r'package:chopper/'),
      RegExp(r'package:retrofit/'),
      RegExp(r'package:graphql(_flutter)?/'),
      RegExp(r'package:web_socket_channel/'),
      RegExp(r'package:firebase_'),
      RegExp(r'package:cloud_firestore'),
      RegExp(r'package:google_(sign_in|api|analytics)'),
      RegExp(r'package:google_mlkit_'),
      RegExp(r'package:ml_kit_'),
      RegExp(r'package:apple_translation'),
      RegExp(r'package:sentry'),
    ];
    final bannedApis = <RegExp>[
      RegExp(r'\bHttpClient\b'),
      RegExp(r'\bSocket\.connect\b'),
      RegExp(r'\bRawSocket\b'),
      RegExp(r'\bWebSocket\.connect\b'),
      RegExp(r'\bdart:html\b'),
    ];

    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'Run from project root with `dart test test/offline_guard_test.dart`.',
    );

    final offenders = <String>[];
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final src = await entity.readAsString();
      final allowFile = src.contains('offline-guard:allow');
      for (final r in bannedPackages) {
        if (r.hasMatch(src)) {
          offenders.add('${entity.path}: banned import "${r.pattern}"');
        }
      }
      if (allowFile) continue;
      for (final r in bannedApis) {
        if (r.hasMatch(src)) {
          offenders.add('${entity.path}: banned API "${r.pattern}"');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Offline guarantee violated:\n${offenders.join('\n')}',
    );
  });
}
