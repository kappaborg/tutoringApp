import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'log_service.dart';
import 'prefs_service.dart';

/// Status of the on-device TTS subsystem. `noVoice` means no offline voice
/// could be configured — the UI should surface a one-time tip.
enum TtsAvailability { unknown, ready, noVoice }

/// Wraps `flutter_tts`. Speaks sentences and individual words. Exposes the
/// current word range during sentence playback so word widgets can highlight
/// themselves. Strictly offline; never accepts network voices.
class TtsService extends ChangeNotifier {
  TtsService({PrefsService? prefs}) : _prefs = prefs;

  final FlutterTts _tts = FlutterTts();
  PrefsService? _prefs;

  bool _initialized = false;
  bool _speaking = false;
  String? _currentSentence;
  int _currentStart = -1;
  int _currentEnd = -1;
  TtsAvailability _availability = TtsAvailability.unknown;
  List<Map<String, String>> _voices = const [];

  bool get isSpeaking => _speaking;
  String? get currentSentence => _currentSentence;
  int get currentStart => _currentStart;
  int get currentEnd => _currentEnd;
  TtsAvailability get availability => _availability;
  List<Map<String, String>> get voices => _voices;

  void attachPrefs(PrefsService prefs) {
    _prefs = prefs;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(_prefs?.ttsRate ?? 0.45);
      await _tts.setPitch(_prefs?.ttsPitch ?? 1.0);
      await _tts.awaitSpeakCompletion(true);

      _tts.setStartHandler(() {
        _speaking = true;
        notifyListeners();
      });
      _tts.setCompletionHandler(() {
        _speaking = false;
        _currentStart = -1;
        _currentEnd = -1;
        _currentSentence = null;
        notifyListeners();
      });
      _tts.setCancelHandler(() {
        _speaking = false;
        _currentStart = -1;
        _currentEnd = -1;
        _currentSentence = null;
        notifyListeners();
      });
      _tts.setErrorHandler((msg) {
        _speaking = false;
        notifyListeners();
        LogService.instance.warn('TTS error: $msg');
      });
      _tts.setProgressHandler((text, start, end, word) {
        _currentSentence = text;
        _currentStart = start;
        _currentEnd = end;
        notifyListeners();
      });

      await _refreshVoices();
      await _applySavedVoice();
    } catch (e, st) {
      LogService.instance.error('TTS init failed', e, st);
      _availability = TtsAvailability.noVoice;
      notifyListeners();
    }
  }

  Future<void> _refreshVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        _voices = raw
            .whereType<Map<Object?, Object?>>()
            .map(
              (m) => m.map<String, String>(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            )
            .toList(growable: false);
      }
      final offlineish = _voices.where(_looksOffline).toList();
      _availability = offlineish.isEmpty ? TtsAvailability.noVoice : TtsAvailability.ready;
    } catch (e) {
      _availability = TtsAvailability.noVoice;
      LogService.instance.warn('Could not enumerate TTS voices: $e');
    }
  }

  bool _looksOffline(Map<String, String> v) {
    // Heuristic: treat any voice whose name does not hint at network as offline.
    final blob = '${v['name'] ?? ''} ${v['locale'] ?? ''}'.toLowerCase();
    const banned = ['network', 'cloud', 'remote', 'online'];
    return !banned.any(blob.contains);
  }

  Future<void> _applySavedVoice() async {
    final name = _prefs?.ttsVoiceName;
    final locale = _prefs?.ttsVoiceLocale;
    if (name == null) return;
    try {
      await _tts.setVoice({'name': name, if (locale != null) 'locale': locale});
    } catch (e) {
      LogService.instance.warn('Could not apply saved voice "$name": $e');
    }
  }

  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate);
    await _prefs?.setTtsRate(rate);
  }

  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch);
    await _prefs?.setTtsPitch(pitch);
  }

  Future<void> setVoice(Map<String, String> voice) async {
    await _tts.setVoice(voice);
    await _prefs?.setTtsVoice(voice['name'], voice['locale']);
  }

  Future<void> speakSentence(String sentence) async {
    await stop();
    _currentSentence = sentence;
    _currentStart = -1;
    _currentEnd = -1;
    notifyListeners();
    // On Windows the progress handler is not supported — speak the whole thing.
    if (Platform.isWindows) {
      await _tts.speak(sentence);
      return;
    }
    await _tts.speak(sentence);
  }

  Future<void> speakWord(String word, {String? override}) async {
    await stop();
    await _tts.speak(override ?? word);
  }

  Future<void> stop() async {
    if (_speaking) {
      await _tts.stop();
    }
    _speaking = false;
    _currentSentence = null;
    _currentStart = -1;
    _currentEnd = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }
}
