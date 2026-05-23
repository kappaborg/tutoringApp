import 'package:flutter/material.dart';

import '../services/prefs_service.dart';

/// Surfaces user preferences as a [ChangeNotifier] for theme + reader behavior.
class SettingsNotifier extends ChangeNotifier {
  SettingsNotifier(this.prefs);
  final PrefsService prefs;

  ThemeMode get themeMode => prefs.themeMode;
  Future<void> setThemeMode(ThemeMode m) async {
    await prefs.setThemeMode(m);
    notifyListeners();
  }

  bool get dyslexiaFont => prefs.dyslexiaFont;
  Future<void> setDyslexiaFont(bool v) async {
    await prefs.setDyslexiaFont(v);
    notifyListeners();
  }

  bool get tapAlsoSpeaks => prefs.tapAlsoSpeaks;
  Future<void> setTapAlsoSpeaks(bool v) async {
    await prefs.setTapAlsoSpeaks(v);
    notifyListeners();
  }

  ReadingMode get readingMode => prefs.readingMode;
  Future<void> setReadingMode(ReadingMode m) async {
    await prefs.setReadingMode(m);
    notifyListeners();
  }

  void toggleReadingMode() {
    final next = readingMode == ReadingMode.word
        ? ReadingMode.sentence
        : ReadingMode.word;
    setReadingMode(next);
  }
}
