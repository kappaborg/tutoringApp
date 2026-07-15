import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../utils/ocr_sanitizer.dart';
import '../utils/text_block_clusterer.dart';
import 'log_service.dart';
import 'ocr_service.dart';

typedef PdfImportProgress = void Function(int current, int total);

enum SentenceSource { embedded, ocr, missing }

class PdfImportedPage {
  PdfImportedPage({
    required this.pageNumber,
    required this.imageRelPath,
    required this.sentenceText,
    required this.textWasExtracted,
    this.sentenceSource = SentenceSource.missing,
  });
  final int pageNumber;
  final String imageRelPath; // relative to docs dir
  String sentenceText;
  final bool textWasExtracted;
  final SentenceSource sentenceSource;

  bool get sentenceFromEmbedded => sentenceSource == SentenceSource.embedded;
  bool get sentenceFromOcr => sentenceSource == SentenceSource.ocr;
}

class PdfImportResult {
  PdfImportResult({required this.suggestedTitle, required this.pages});
  final String suggestedTitle;
  final List<PdfImportedPage> pages;
  int get pageCount => pages.length;
}

/// Renders each PDF page to a JPEG, extracts embedded text. Pure local I/O —
/// no network usage of any kind. Wraps `pdfrx` (PDFium under the hood).
class PdfImportService {
  PdfImportService({Uuid? uuid, OcrService? ocr})
      : _uuid = uuid ?? const Uuid(),
        _ocr = ocr ?? OcrService();
  final Uuid _uuid;
  final OcrService _ocr;

  static const int _maxLongEdge = 2048;
  static const double _scale = 1.5;
  static const int _jpegQuality = 85;

  /// Lets the user pick a local PDF. Returns the path or `null` if cancelled.
  Future<String?> pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    return result?.files.single.path;
  }

  Future<PdfImportResult> importPdf(
    String pdfPath, {
    required PdfImportProgress onProgress,
  }) async {
    final source = File(pdfPath);
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

    final document = await PdfDocument.openFile(pdfPath);
    try {
      final total = document.pages.length;
      final pages = <PdfImportedPage>[];
      for (var i = 0; i < total; i++) {
        onProgress(i, total);
        final page = document.pages[i];
        final relImage = await _renderAndStore(page, imagesDir);
        var text = await _extractText(page);
        var source = SentenceSource.embedded;
        if (text.isEmpty && _ocr.isSupported) {
          final absImagePath = p.join(docs.path, relImage);
          // Use the block-aware OCR call so we can drop scattered labels
          // that came from inside the illustration. If the platform falls
          // back to plain recognizeText (older builds), use that.
          final blocks = await _ocr.recognizeBlocks(absImagePath);
          String? ocrText;
          if (blocks != null && blocks.isNotEmpty) {
            final picked = pickMainParagraph(blocks);
            ocrText = observationsToText(picked);
          } else if (blocks == null) {
            ocrText = await _ocr.recognize(absImagePath);
          }
          if (ocrText != null && ocrText.trim().isNotEmpty) {
            text = _normalize(ocrText);
            source = SentenceSource.ocr;
          }
        }
        // Sanitise *every* extracted sentence (both pdfrx and Vision results)
        // before it reaches the review screen / DB.
        if (text.isNotEmpty) {
          final before = text.length;
          text = sanitizeOcrText(text);
          if (before - text.length > before * 0.3) {
            LogService.instance.info(
              'ocr_sanitizer trimmed ${before - text.length} chars from page ${i + 1}',
            );
          }
        }
        pages.add(
          PdfImportedPage(
            pageNumber: i + 1,
            imageRelPath: relImage,
            sentenceText: text,
            textWasExtracted: text.isNotEmpty,
            sentenceSource: source,
          ),
        );
      }
      onProgress(total, total);
      final suggested = p.basenameWithoutExtension(source.path);
      return PdfImportResult(suggestedTitle: suggested, pages: pages);
    } finally {
      await document.dispose();
    }
  }

  Future<String> _renderAndStore(PdfPage page, Directory imagesDir) async {
    final pageW = page.width;
    final pageH = page.height;
    var targetW = (pageW * _scale).round();
    var targetH = (pageH * _scale).round();
    final longest = targetW > targetH ? targetW : targetH;
    if (longest > _maxLongEdge) {
      final f = _maxLongEdge / longest;
      targetW = (targetW * f).round();
      targetH = (targetH * f).round();
    }

    final image = await page.render(
      fullWidth: targetW.toDouble(),
      fullHeight: targetH.toDouble(),
      backgroundColor: 0xFFFFFFFF,
    );
    if (image == null) {
      throw const FormatException('pdfrx returned null image for page');
    }
    try {
      final raw = image.pixels;
      // pdfrx 2.x always returns BGRA8888 — the runtime format accessor was
      // dropped along with the legacy renderer.
      final encoded = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: _bytesAsByteBuffer(raw),
        order: img.ChannelOrder.bgra,
        numChannels: 4,
      );
      final jpeg = img.encodeJpg(encoded, quality: _jpegQuality);
      final filename = 'pdf_${_uuid.v4()}.jpg';
      final file = File(p.join(imagesDir.path, filename));
      await file.writeAsBytes(jpeg, flush: true);
      return 'images/$filename';
    } finally {
      image.dispose();
    }
  }

  ByteBuffer _bytesAsByteBuffer(Uint8List bytes) =>
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes).buffer;

  Future<String> _extractText(PdfPage page) async {
    try {
      final text = await page.loadText();
      if (text == null) return '';
      final raw = text.fullText.trim();
      if (raw.isEmpty) return '';
      return _normalize(raw);
    } catch (e, st) {
      LogService.instance.warn('PDF text extraction failed: $e');
      LogService.instance.error('PDF text extraction', e, st);
      return '';
    }
  }

  /// Collapse whitespace, drop soft hyphens, normalize newlines to spaces.
  String _normalize(String raw) {
    var s = raw.replaceAll('­', ''); // soft hyphen
    s = s.replaceAll(RegExp(r'[\r\n]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }
}
