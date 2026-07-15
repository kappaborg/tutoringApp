import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'neural_tts_service.dart';
import 'prefs_service.dart';
import 'tts_service.dart';

/// Picks between the system [TtsService] and the bundled [NeuralTtsService]
/// at every speak call, based on (a) the user's "Neural voice" preference
/// and (b) whether the Kokoro model assets are bundled in this build.
///
/// Mirrors the surface of [TtsService] so the reader code can stay
/// engine-agnostic.
class TtsRouter extends ChangeNotifier {
  TtsRouter({
    required this.system,
    required this.neural,
    required this.prefs,
  }) {
    // Re-emit when either engine notifies (e.g. word-highlight progress).
    system.addListener(notifyListeners);
    neural.addListener(notifyListeners);
  }

  final TtsService system;
  final NeuralTtsService neural;
  final PrefsService prefs;

  bool get _useNeural =>
      prefs.neuralVoiceEnabled &&
      neural.availability == NeuralTtsAvailability.ready;

  bool get isSpeaking => _useNeural ? neural.isSpeaking : system.isSpeaking;
  String? get currentSentence =>
      _useNeural ? neural.currentSentence : system.currentSentence;
  int get currentStart => _useNeural ? -1 : system.currentStart;
  int get currentEnd => _useNeural ? -1 : system.currentEnd;

  /// Speaks [text]. When [preRenderedAudioRelPath] is supplied and neural
  /// mode is active, the bundled clip at that docs-relative path is played
  /// directly — no on-device inference. The path is ignored for system TTS.
  Future<void> speakSentence(
    String text, {
    String? preRenderedAudioRelPath,
  }) async {
    if (_useNeural &&
        preRenderedAudioRelPath != null &&
        preRenderedAudioRelPath.isNotEmpty) {
      final docs = await getApplicationDocumentsDirectory();
      final abs = p.join(docs.path, preRenderedAudioRelPath);
      return neural.speakSentence(text, preRenderedPath: abs);
    }
    return _useNeural ? neural.speakSentence(text) : system.speakSentence(text);
  }

  Future<void> speakWord(String word, {String? override}) =>
      _useNeural
          ? neural.speakWord(word, override: override)
          : system.speakWord(word, override: override);

  Future<void> stop() async {
    // Stop both — when the user toggles between engines mid-playback we
    // want absolute silence either way.
    await neural.stop();
    await system.stop();
  }

  Future<void> setRate(double rate) async {
    await neural.setRate(rate);
    await system.setRate(rate);
  }

  /// System-voice availability. The reader uses this to show a one-time
  /// "install a voice" SnackBar — neural mode handles its own warnings via
  /// the Settings toggle subtitle.
  TtsAvailability get availability => system.availability;

  /// True when at least one engine can actually speak right now: the
  /// bundled Kokoro neural voice is ready (and the user has it enabled),
  /// OR the system TTS has at least one installed voice. The reader's
  /// "no voice — install one" tip uses this so it doesn't fire just
  /// because the OEM didn't pre-install Google TTS data.
  bool get hasAnyVoice {
    if (prefs.neuralVoiceEnabled &&
        neural.availability == NeuralTtsAvailability.ready) {
      return true;
    }
    return system.availability != TtsAvailability.noVoice;
  }

  @override
  void dispose() {
    system.removeListener(notifyListeners);
    neural.removeListener(notifyListeners);
    super.dispose();
  }
}
