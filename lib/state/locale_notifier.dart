import 'package:flutter/material.dart';

import '../services/prefs_service.dart';

/// Controls the active UI locale. `locale == null` means "follow system".
class LocaleNotifier extends ChangeNotifier {
  LocaleNotifier(this._prefs);
  final PrefsService _prefs;

  Locale? get locale {
    final code = _prefs.uiLocaleCode;
    if (code == null) return null;
    return Locale(code);
  }

  Future<void> setLocaleCode(String? code) async {
    await _prefs.setUiLocaleCode(code);
    notifyListeners();
  }
}
