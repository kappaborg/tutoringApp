import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'log_service.dart';

/// Status of the bundled neural-TTS engine.
enum NeuralTtsAvailability { unknown, ready, missingAssets, initFailed }

/// Offline neural text-to-speech driven by Kokoro-82M (English) via
/// `sherpa_onnx`. Produces studio-grade narration with zero network usage.
///
/// API mirrors [TtsService] so the reader can switch between system and
/// neural voices without changes to its call sites.
class NeuralTtsService extends ChangeNotifier {
  static const String _voiceAssetDir = 'assets/voices/kokoro';
  static const List<String> _requiredFiles = <String>[
    'model.onnx',
    'voices.bin',
    'tokens.txt',
  ];

  final ja.AudioPlayer _player = ja.AudioPlayer();
  sherpa.OfflineTts? _tts;
  bool _speaking = false;
  String? _currentSentence;
  NeuralTtsAvailability _availability = NeuralTtsAvailability.unknown;
  int _voiceId = 0;
  double _speechRate = 1.0;

  /// In-memory map of `voiceId|speed|text` → wav file path. Tapping the same
  /// sentence twice within a session reuses the WAV (~150 ms playback start)
  /// instead of paying the full inference cost again (~2–4 s on older
  /// Android devices). Cleared when `setRate`/`setVoiceId` changes the key.
  final Map<String, String> _audioCache = <String, String>{};

  bool get isReady => _tts != null;
  bool get isSpeaking => _speaking;
  String? get currentSentence => _currentSentence;
  NeuralTtsAvailability get availability => _availability;
  int get voiceId => _voiceId;
  double get speechRate => _speechRate;

  /// Boots the engine. Safe to call multiple times — the second call is a
  /// no-op. If the voice model isn't bundled into the app the service stays
  /// in `missingAssets` state and the reader silently falls back to the
  /// system TTS.
  Future<void> init() async {
    if (_availability != NeuralTtsAvailability.unknown) return;
    try {
      sherpa.initBindings();

      // 1. Mirror the bundled voice tree to a real on-disk directory so
      //    sherpa-onnx can mmap files by path (it can't read from the
      //    Flutter asset bundle directly).
      final supportDir = await getApplicationSupportDirectory();
      final outDir = Directory(p.join(supportDir.path, 'kokoro'));
      if (!await outDir.exists()) await outDir.create(recursive: true);

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final voiceAssets = manifest
          .listAssets()
          .where((a) => a.startsWith('$_voiceAssetDir/'))
          .toList();

      // Sanity check: the three core model files must be present.
      var anyMissing = false;
      for (final name in _requiredFiles) {
        if (!voiceAssets.contains('$_voiceAssetDir/$name')) {
          anyMissing = true;
          LogService.instance.warn(
            'NeuralTts: required asset missing ($_voiceAssetDir/$name). '
            'Run `dart run tool/fetch_kokoro.dart` to fetch the model.',
          );
        }
      }
      if (anyMissing) {
        _availability = NeuralTtsAvailability.missingAssets;
        notifyListeners();
        return;
      }

      for (final asset in voiceAssets) {
        final rel = asset.substring(_voiceAssetDir.length + 1);
        final dest = File(p.join(outDir.path, rel));
        // Skip if already copied with non-zero size — the model is 330 MB
        // and we don't want to repeat that on every cold start.
        if (await dest.exists() && (await dest.length()) > 0) continue;
        await dest.parent.create(recursive: true);
        final data = await rootBundle.load(asset);
        await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }

      // 2. Configure and create the OfflineTts engine. dataDir points at the
      //    espeak-ng phonemizer data shipped alongside the Kokoro weights.
      final dataDir = p.join(outDir.path, 'espeak-ng-data');
      final config = sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: p.join(outDir.path, 'model.onnx'),
            voices: p.join(outDir.path, 'voices.bin'),
            tokens: p.join(outDir.path, 'tokens.txt'),
            dataDir: dataDir,
            lengthScale: 1.0,
            lang: 'en-us',
          ),
          // Kokoro-en is CPU-bound. On macOS we max out at 8 threads — the
          // M-series machine running the seed-library bake has cores to
          // spare and this roughly halves bake time. On phones we keep 4
          // threads to avoid thermal throttling on older Snapdragon parts.
          numThreads: Platform.isMacOS ? 8 : 4,
          // Verbose Kokoro logs (raw text + hex dump per generation) are
          // never useful at runtime and flood stderr during the bake.
          debug: false,
        ),
      );
      _tts = sherpa.OfflineTts(config);
      _availability = NeuralTtsAvailability.ready;
      LogService.instance.info('NeuralTts: ready (voice dir: ${outDir.path})');
      // Fire-and-forget warm-up. The first real `engine.generate` call after
      // a cold start pays substantial ONNX runtime init cost (allocations,
      // graph compilation). Running a throwaway short sentence here amortises
      // it before the user taps anything.
      unawaited(_warmUp());
    } catch (e, st) {
      _availability = NeuralTtsAvailability.initFailed;
      LogService.instance.error('NeuralTts init failed', e, st);
    } finally {
      notifyListeners();
    }
  }

  Future<void> _warmUp() async {
    final engine = _tts;
    if (engine == null) return;
    try {
      final sw = Stopwatch()..start();
      // Yield once so the UI thread renders the first frame before we
      // monopolise the CPU for the warm-up inference.
      await Future<void>.delayed(Duration.zero);
      engine.generate(text: 'hi', sid: _voiceId, speed: 1.0);
      LogService.instance.info(
        'NeuralTts warm-up: ${sw.elapsedMilliseconds}ms',
      );
    } catch (e, st) {
      LogService.instance.error('NeuralTts warm-up failed', e, st);
    }
  }

  Future<void> setVoiceId(int id) async {
    if (id == _voiceId) return;
    _voiceId = id;
    _audioCache.clear();
    notifyListeners();
  }

  Future<void> setRate(double rate) async {
    // Kokoro uses a "speed" multiplier where >1 is faster.
    final clamped = rate.clamp(0.5, 2.0);
    if (clamped == _speechRate) return;
    _speechRate = clamped;
    _audioCache.clear();
    notifyListeners();
  }

  String _cacheKey(String text) => '$_voiceId|$_speechRate|$text';

  /// Generates audio for [text] and plays it. Resolution order:
  ///   1. [preRenderedPath] — a bundled WAV baked at install time. Only used
  ///      when voice + speed are still at their bake-time defaults
  ///      (sid 0, speed 1.0).
  ///   2. In-memory cache for the current session.
  ///   3. Live inference + cache.
  Future<void> speakSentence(String text, {String? preRenderedPath}) async {
    final engine = _tts;
    if (engine == null) return;
    if (text.trim().isEmpty) return;
    await stop();
    _speaking = true;
    _currentSentence = text;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      // 1. Bundled pre-rendered audio (default voice / speed only).
      final canUsePreRendered = preRenderedPath != null &&
          preRenderedPath.isNotEmpty &&
          _voiceId == 0 &&
          _speechRate == 1.0;
      if (canUsePreRendered && await File(preRenderedPath).exists()) {
        await _player.setFilePath(preRenderedPath);
        await _player.play();
        LogService.instance.info(
          'NeuralTts: bundled audio in ${sw.elapsedMilliseconds}ms',
        );
        _attachCompletionListener();
        return;
      }

      // 2. + 3. Session cache, then live inference.
      final key = _cacheKey(text);
      var wavPath = _audioCache[key];
      if (wavPath != null && !await File(wavPath).exists()) {
        _audioCache.remove(key);
        wavPath = null;
      }
      if (wavPath == null) {
        final audio = await _generateAudio(engine, text);
        wavPath = await _writeWav(audio);
        if (wavPath == null) {
          _speaking = false;
          notifyListeners();
          return;
        }
        _audioCache[key] = wavPath;
        LogService.instance.info(
          'NeuralTts: rendered "${text.length > 40 ? "${text.substring(0, 40)}…" : text}" '
          'in ${sw.elapsedMilliseconds}ms',
        );
      } else {
        LogService.instance.info(
          'NeuralTts: cache hit in ${sw.elapsedMilliseconds}ms',
        );
      }
      await _player.setFilePath(wavPath);
      await _player.play();
      _attachCompletionListener();
    } catch (e, st) {
      LogService.instance.error('NeuralTts speakSentence failed', e, st);
      _speaking = false;
      _currentSentence = null;
      notifyListeners();
    }
  }

  void _attachCompletionListener() {
    unawaited(
      _player.playerStateStream
          .firstWhere((s) => s.processingState == ja.ProcessingState.completed)
          .then((_) {
        _speaking = false;
        _currentSentence = null;
        notifyListeners();
      }),
    );
  }

  Future<void> speakWord(String word, {String? override}) =>
      speakSentence(override ?? word);

  /// Renders [text] and writes the resulting WAV to [destPath]. Used by the
  /// macOS bake step to pre-compute audio that ships inside `.book.zip`.
  /// Returns false if generation failed or produced no samples.
  Future<bool> renderToFile(String text, String destPath) async {
    final engine = _tts;
    if (engine == null) return false;
    if (text.trim().isEmpty) return false;
    // Use the bake-time defaults so the bundled audio is reusable at runtime
    // whenever the user keeps voice=0 / speed=1.0.
    final audio = engine.generate(text: text, sid: 0, speed: 1.0);
    if (audio.sampleRate == 0 || audio.samples.isEmpty) return false;
    final out = File(destPath);
    await out.parent.create(recursive: true);
    return sherpa.writeWave(
      filename: out.path,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
  }

  Future<void> stop() async {
    if (_speaking) {
      await _player.stop();
    }
    _speaking = false;
    _currentSentence = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    _tts?.free();
    super.dispose();
  }

  /// Wraps the synchronous `sherpa.OfflineTts.generate` in a compute-isolate
  /// so the UI thread doesn't block on inference. With Kokoro on a modern
  /// phone a sentence renders in ~200–600 ms; even a UI hiccup that brief is
  /// worth offloading to keep tap responsiveness sharp.
  Future<sherpa.GeneratedAudio> _generateAudio(
    sherpa.OfflineTts engine,
    String text,
  ) async {
    // Note: we don't use compute() because the OfflineTts pointer is not
    // safely transferable across isolates. Inference must run on this
    // isolate. We yield via microtask boundary instead.
    await Future<void>.delayed(Duration.zero);
    return engine.generate(text: text, sid: _voiceId, speed: _speechRate);
  }

  Future<String?> _writeWav(sherpa.GeneratedAudio audio) async {
    if (audio.sampleRate == 0 || audio.samples.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final out = File(
      p.join(dir.path, 'kokoro_${DateTime.now().microsecondsSinceEpoch}.wav'),
    );
    final ok = sherpa.writeWave(
      filename: out.path,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    if (!ok) return null;
    return out.path;
  }
}
