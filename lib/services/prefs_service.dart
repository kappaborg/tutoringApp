import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reading interaction mode for the reader screen.
/// - [word]: tap individual words to hear them + see their meaning.
/// - [sentence]: tap the sentence area to hear the whole sentence and see
///   its Chinese translation.
enum ReadingMode { word, sentence }

/// Wraps SharedPreferences. PIN is stored as sha256 hash; never plaintext.
class PrefsService {
  PrefsService._(this._prefs);
  final SharedPreferences _prefs;

  static const _kPinHash = 'pin_hash';
  static const _kLastBookId = 'last_book_id';
  static const _kLastPageNumber = 'last_page_number';
  static const _kTtsRate = 'tts_rate';
  static const _kTtsPitch = 'tts_pitch';
  static const _kTtsVoiceName = 'tts_voice_name';
  static const _kTtsVoiceLocale = 'tts_voice_locale';
  static const _kTapAlsoSpeaks = 'tap_also_speaks';
  static const _kThemeMode = 'theme_mode';
  static const _kDyslexiaFont = 'dyslexia_font';
  static const _kVoiceWarningShown = 'voice_warning_shown';
  static const _kReadingMode = 'reading_mode';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kUiLocale = 'ui_locale';
  static const _kStatsPrefix = 'stats:';
  static const _kNeuralVoice = 'neural_voice_enabled';
  static const _kOxfordSeeded = 'oxford_seeded';
  static const _kLicenseCode = 'license_code';

  static Future<PrefsService> init() async {
    final p = await SharedPreferences.getInstance();
    return PrefsService._(p);
  }

  // ── PIN ──────────────────────────────────────────────────────────────────
  bool get hasPin => (_prefs.getString(_kPinHash) ?? '').isNotEmpty;
  bool verifyPin(String pin) => _prefs.getString(_kPinHash) == _hash(pin);
  Future<void> setPin(String pin) async => _prefs.setString(_kPinHash, _hash(pin));
  Future<void> clearPin() async => _prefs.remove(_kPinHash);
  String _hash(String pin) => sha256.convert(utf8.encode(pin.trim())).toString();

  // ── Resume position ──────────────────────────────────────────────────────
  int? get lastBookId => _prefs.getInt(_kLastBookId);
  int? get lastPageNumber => _prefs.getInt(_kLastPageNumber);
  Future<void> setLastPosition(int bookId, int pageNumber) async {
    await _prefs.setInt(_kLastBookId, bookId);
    await _prefs.setInt(_kLastPageNumber, pageNumber);
  }

  Future<void> clearLastPosition() async {
    await _prefs.remove(_kLastBookId);
    await _prefs.remove(_kLastPageNumber);
  }

  // ── TTS ──────────────────────────────────────────────────────────────────
  double get ttsRate => _prefs.getDouble(_kTtsRate) ?? 0.45;
  Future<void> setTtsRate(double v) async => _prefs.setDouble(_kTtsRate, v);

  double get ttsPitch => _prefs.getDouble(_kTtsPitch) ?? 1.0;
  Future<void> setTtsPitch(double v) async => _prefs.setDouble(_kTtsPitch, v);

  String? get ttsVoiceName => _prefs.getString(_kTtsVoiceName);
  String? get ttsVoiceLocale => _prefs.getString(_kTtsVoiceLocale);
  Future<void> setTtsVoice(String? name, String? locale) async {
    if (name == null) {
      await _prefs.remove(_kTtsVoiceName);
      await _prefs.remove(_kTtsVoiceLocale);
    } else {
      await _prefs.setString(_kTtsVoiceName, name);
      if (locale != null) await _prefs.setString(_kTtsVoiceLocale, locale);
    }
  }

  bool get tapAlsoSpeaks => _prefs.getBool(_kTapAlsoSpeaks) ?? true;
  Future<void> setTapAlsoSpeaks(bool v) async => _prefs.setBool(_kTapAlsoSpeaks, v);

  bool get voiceWarningShown => _prefs.getBool(_kVoiceWarningShown) ?? false;
  Future<void> setVoiceWarningShown(bool v) async =>
      _prefs.setBool(_kVoiceWarningShown, v);

  // ── Theme ────────────────────────────────────────────────────────────────
  ThemeMode get themeMode {
    final name = _prefs.getString(_kThemeMode);
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode m) async =>
      _prefs.setString(_kThemeMode, m.name);

  bool get dyslexiaFont => _prefs.getBool(_kDyslexiaFont) ?? false;
  Future<void> setDyslexiaFont(bool v) async => _prefs.setBool(_kDyslexiaFont, v);

  // ── Reading mode ─────────────────────────────────────────────────────────
  ReadingMode get readingMode {
    final v = _prefs.getString(_kReadingMode);
    return ReadingMode.values.firstWhere(
      (m) => m.name == v,
      orElse: () => ReadingMode.word,
    );
  }

  Future<void> setReadingMode(ReadingMode m) async =>
      _prefs.setString(_kReadingMode, m.name);

  // ── Onboarding ───────────────────────────────────────────────────────────
  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> markOnboardingDone() async =>
      _prefs.setBool(_kOnboardingDone, true);

  // ── UI locale ────────────────────────────────────────────────────────────
  /// Returns the persisted UI locale code ("en", "zh") or null for "follow
  /// system".
  String? get uiLocaleCode {
    final v = _prefs.getString(_kUiLocale);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setUiLocaleCode(String? code) async {
    if (code == null) {
      await _prefs.remove(_kUiLocale);
    } else {
      await _prefs.setString(_kUiLocale, code);
    }
  }

  // ── Daily reading stats ──────────────────────────────────────────────────
  /// `kind` is "pages" or "books". `day` is the yyyy-mm-dd string in local
  /// time. Increments by 1.
  Future<void> bumpStat(String kind, DateTime when) async {
    final day =
        '${when.year.toString().padLeft(4, '0')}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    final key = '$_kStatsPrefix$kind:$day';
    final current = _prefs.getInt(key) ?? 0;
    await _prefs.setInt(key, current + 1);
  }

  // ── Neural voice toggle ──────────────────────────────────────────────────
  bool get neuralVoiceEnabled => _prefs.getBool(_kNeuralVoice) ?? true;
  Future<void> setNeuralVoiceEnabled(bool v) async =>
      _prefs.setBool(_kNeuralVoice, v);

  // ── Bundled Oxford seed library ──────────────────────────────────────────
  bool get oxfordSeeded => _prefs.getBool(_kOxfordSeeded) ?? false;
  Future<void> setOxfordSeeded(bool v) async =>
      _prefs.setBool(_kOxfordSeeded, v);

  // ── License code ─────────────────────────────────────────────────────────
  /// Persisted activation code. Null means "no activation done yet" → app
  /// shows the activation screen. The code itself is verified on every load
  /// by [LicenseService] against the embedded public key.
  String? get licenseCode {
    final v = _prefs.getString(_kLicenseCode);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setLicenseCode(String? code) async {
    if (code == null || code.isEmpty) {
      await _prefs.remove(_kLicenseCode);
    } else {
      await _prefs.setString(_kLicenseCode, code);
    }
  }

  /// Sum of [kind] over the last [days] including today.
  int statTotal(String kind, {int days = 7}) {
    var total = 0;
    final now = DateTime.now();
    for (var i = 0; i < days; i++) {
      final d = now.subtract(Duration(days: i));
      final day =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      total += _prefs.getInt('$_kStatsPrefix$kind:$day') ?? 0;
    }
    return total;
  }
}
