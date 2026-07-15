import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('License round-trip', () {
    test('valid code parses & verifies against the embedded public key',
        () async {
      // Same public key as license_service.dart's _kPublicKey constant.
      const publicKey = <int>[
        0xb6, 0x49, 0xa0, 0x7c, 0xfc, 0xcd, 0x08, 0xc2,
        0xcc, 0x9c, 0xe3, 0x64, 0xbc, 0xf4, 0x01, 0x9e,
        0x8d, 0x06, 0x5d, 0xe0, 0x2f, 0x98, 0x56, 0xcf,
        0xa4, 0xac, 0x22, 0xca, 0x64, 0x5d, 0x99, 0x2a,
      ];
      // A code produced by `dart run tool/issue_license.dart` with the
      // matching private key. If this fixture stops verifying, either the
      // private key was rotated or someone touched the encoding.
      const code =
          'eyJjdXN0b21lciI6ImtheXJheWlsbWF6ZWR1MjAzQGdtYWlsLmNvbSIsInRpZXIi'
          'OiJmdWxsIiwiaXNzdWVkIjoiMjAyNi0wNS0yNyJ9'
          '.'
          'eDTeccendiweA6-d2dYsFaJXw-uO_bB1xuzE4MC1XyR1WbS9HtahyqBb-QFfeW3-'
          'KNw-aM2RxsToJSIGibW_Bw';

      final parts = code.split('.');
      expect(parts, hasLength(2));
      final payload = base64Url.decode(_pad(parts[0]));
      final sig = base64Url.decode(_pad(parts[1]));

      final algo = Ed25519();
      final ok = await algo.verify(
        payload,
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
      expect(ok, isTrue);

      final json =
          jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
      expect(json['customer'], 'kayrayilmazedu203@gmail.com');
      expect(json['tier'], 'full');
      expect(json['issued'], '2026-05-27');
    });

    test('tampered payload fails verification', () async {
      const publicKey = <int>[
        0xb6, 0x49, 0xa0, 0x7c, 0xfc, 0xcd, 0x08, 0xc2,
        0xcc, 0x9c, 0xe3, 0x64, 0xbc, 0xf4, 0x01, 0x9e,
        0x8d, 0x06, 0x5d, 0xe0, 0x2f, 0x98, 0x56, 0xcf,
        0xa4, 0xac, 0x22, 0xca, 0x64, 0x5d, 0x99, 0x2a,
      ];
      // Original payload + a signature for a *different* payload. Mismatch
      // must be rejected.
      const tampered =
          'eyJjdXN0b21lciI6IkV2aWwgQXR0YWNrZXIiLCJ0aWVyIjoiZnVsbCIsImlzc3Vl'
          'ZCI6IjIwMjYtMDUtMjcifQ'
          '.'
          'eDTeccendiweA6-d2dYsFaJXw-uO_bB1xuzE4MC1XyR1WbS9HtahyqBb-QFfeW3-'
          'KNw-aM2RxsToJSIGibW_Bw';
      final parts = tampered.split('.');
      final payload = base64Url.decode(_pad(parts[0]));
      final sig = base64Url.decode(_pad(parts[1]));
      final algo = Ed25519();
      final ok = await algo.verify(
        payload,
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
      expect(ok, isFalse);
    });
  });
}

String _pad(String s) {
  final mod = s.length % 4;
  if (mod == 0) return s;
  return s + ('=' * (4 - mod));
}
