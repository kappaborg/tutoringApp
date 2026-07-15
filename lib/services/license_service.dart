import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'log_service.dart';
import 'prefs_service.dart';

/// Result of inspecting a license string.
@immutable
class License {
  const License({
    required this.customer,
    required this.tier,
    required this.issuedAtIso,
  });
  final String customer;
  final String tier;
  final String issuedAtIso;

  DateTime? get issuedAt => DateTime.tryParse(issuedAtIso);

  @override
  String toString() => 'License($customer · $tier · $issuedAtIso)';
}

/// Offline activation gate. License codes are produced by
/// `tool/issue_license.dart` on the developer's machine and validated
/// here against an embedded public key — no network round-trip, no
/// revocation server, no ongoing cost.
///
/// Code shape:
///   `<base64url(payload_json)>.<base64url(ed25519_signature)>`
/// where `payload_json` is `{"customer":"…","tier":"…","issued":"yyyy-mm-dd"}`.
class LicenseService extends ChangeNotifier {
  LicenseService(this._prefs);

  final PrefsService _prefs;

  // Public key for the project's signing keypair. The private half lives
  // OUTSIDE the repo (default ~/.picturebook/private_key.bin) and never
  // ships to a device. Rotating this constant invalidates every existing
  // customer's activation — only do it after a private-key compromise.
  static const List<int> _kPublicKey = <int>[
    0xb6, 0x49, 0xa0, 0x7c, 0xfc, 0xcd, 0x08, 0xc2,
    0xcc, 0x9c, 0xe3, 0x64, 0xbc, 0xf4, 0x01, 0x9e,
    0x8d, 0x06, 0x5d, 0xe0, 0x2f, 0x98, 0x56, 0xcf,
    0xa4, 0xac, 0x22, 0xca, 0x64, 0x5d, 0x99, 0x2a,
  ];

  License? _current;
  License? get current => _current;
  bool get isActivated => _current != null;

  /// Loads the previously stored license (if any) and verifies the
  /// signature still matches the embedded public key. Tampered or
  /// stale-key codes are treated as not activated.
  Future<void> loadStored() async {
    final raw = _prefs.licenseCode;
    if (raw == null || raw.isEmpty) return;
    final lic = await _verify(raw);
    if (lic != null) {
      _current = lic;
      notifyListeners();
    } else {
      // Stored code no longer validates — wipe so the user is re-prompted
      // instead of silently appearing unlicensed.
      await _prefs.setLicenseCode(null);
      LogService.instance.warn(
        'LicenseService: stored license failed verification; cleared',
      );
    }
  }

  /// Verifies [code] and, on success, stores it + notifies listeners.
  /// Returns the parsed [License] on success, null on any failure.
  Future<License?> activate(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final lic = await _verify(trimmed);
    if (lic == null) return null;
    await _prefs.setLicenseCode(trimmed);
    _current = lic;
    notifyListeners();
    return lic;
  }

  Future<void> deactivate() async {
    await _prefs.setLicenseCode(null);
    _current = null;
    notifyListeners();
  }

  Future<License?> _verify(String code) async {
    try {
      final parts = code.split('.');
      if (parts.length != 2) return null;
      final payloadBytes = base64Url.decode(_pad(parts[0]));
      final sigBytes = base64Url.decode(_pad(parts[1]));
      final algo = Ed25519();
      final ok = await algo.verify(
        payloadBytes,
        signature: Signature(
          sigBytes,
          publicKey: SimplePublicKey(
            _kPublicKey,
            type: KeyPairType.ed25519,
          ),
        ),
      );
      if (!ok) return null;
      final payload =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, Object?>;
      return License(
        customer: (payload['customer'] as String?) ?? '',
        tier: (payload['tier'] as String?) ?? 'full',
        issuedAtIso: (payload['issued'] as String?) ?? '',
      );
    } catch (e, st) {
      LogService.instance.warn('LicenseService verify error: $e');
      LogService.instance.error('LicenseService verify', e, st);
      return null;
    }
  }

  /// base64url without padding is fine to emit, but `base64Url.decode`
  /// requires the padding be re-added before decode.
  String _pad(String s) {
    final mod = s.length % 4;
    if (mod == 0) return s;
    return s + ('=' * (4 - mod));
  }

  /// Encodes [bytes] as unpadded base64url — same encoding used in the
  /// issue tool. Exposed so tests can round-trip easily.
  @visibleForTesting
  static String encodeForTest(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
