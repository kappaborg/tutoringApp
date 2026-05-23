import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../utils/text_block_clusterer.dart';
import 'log_service.dart';

/// Calls the platform-native on-device OCR.
///
/// • iOS / macOS: Apple Vision (`VNRecognizeText`) — fully on-device, no
///   network, ships with the OS. No language packs to install.
/// • Android / Windows / Linux: returns `null` (caller falls back to manual
///   sentence entry). When the project ships Tesseract or ML-Kit-offline,
///   wire it in here behind the same interface.
class OcrService {
  static const _channel = MethodChannel('com.kappasutra.picturebook/ocr');

  /// Returns `true` if [recognize] is implemented on this platform.
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS;
  }

  /// Runs OCR on the file at [imagePath] (JPEG or PNG). Returns the recognized
  /// text joined with newlines, or `null` if OCR is unsupported, fails, or
  /// finds no text.
  Future<String?> recognize(
    String imagePath, {
    List<String> languages = const ['en-US'],
  }) async {
    if (!isSupported) return null;
    try {
      final result = await _channel.invokeMethod<String>('recognizeText', {
        'imagePath': imagePath,
        'languages': languages,
      });
      final text = (result ?? '').trim();
      return text.isEmpty ? null : text;
    } on PlatformException catch (e, st) {
      LogService.instance.error('OCR failed (${e.code})', e, st);
      return null;
    } catch (e, st) {
      LogService.instance.error('OCR failed', e, st);
      return null;
    }
  }

  /// Returns each detected text observation along with its normalised
  /// bounding box (0..1, top-left origin). Used by the PDF importer to
  /// cluster observations into the main paragraph and drop scattered
  /// labels picked up from inside the illustration. Returns `null` when
  /// the platform doesn't support OCR or the call fails; returns an empty
  /// list when OCR ran but found nothing.
  Future<List<OcrObservation>?> recognizeBlocks(
    String imagePath, {
    List<String> languages = const ['en-US'],
  }) async {
    if (!isSupported) return null;
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'recognizeTextBlocks',
        {'imagePath': imagePath, 'languages': languages},
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .map(OcrObservation.fromMap)
          .where((o) => o.text.isNotEmpty)
          .toList(growable: false);
    } on PlatformException catch (e, st) {
      LogService.instance.error('OCR blocks failed (${e.code})', e, st);
      return null;
    } catch (e, st) {
      LogService.instance.error('OCR blocks failed', e, st);
      return null;
    }
  }
}
