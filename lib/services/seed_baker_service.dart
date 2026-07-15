import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/word_meaning.dart';
import '../repositories/book_repository.dart';
import '../repositories/page_repository.dart';
import '../repositories/word_repository.dart';
import '../utils/sentence_splitter.dart';
import '../utils/tokenizer.dart';
import 'book_share_service.dart';
import 'image_storage_service.dart';
import 'log_service.dart';
import 'neural_tts_service.dart';
import 'pdf_import_service.dart';
import 'translation_lookup.dart';

class BakeProgress {
  const BakeProgress({
    required this.done,
    required this.total,
    required this.currentTitle,
  });
  final int done;
  final int total;
  final String currentTitle;
}

class BakeReport {
  const BakeReport({required this.success, required this.failed});
  final int success;
  final int failed;
}

/// Batch-imports a folder of PDFs through the full PDF→images→OCR→sanitize
/// pipeline, then writes a `.book.zip` per book into [destDir]. The freshly
/// imported books are deleted from the working DB once their zip is on disk,
/// so the admin's library doesn't accumulate the entire seed set.
///
/// When [neural] is supplied, each sentence is also rendered to a WAV that
/// gets packaged inside the resulting `.book.zip`. This is what makes
/// neural-voice taps feel instant in the shipped app — no on-device
/// inference for bundled books.
///
/// Used by both the admin screen "Bake seed library" action and the
/// headless `--bake-dir=…` startup flag in main.dart.
class SeedBakerService {
  SeedBakerService({
    required this.pdfService,
    required this.lookup,
    required this.share,
    required this.bookRepo,
    required this.pageRepo,
    required this.wordRepo,
    required this.imageStorage,
    this.neural,
  });

  final PdfImportService pdfService;
  final TranslationLookup lookup;
  final BookShareService share;
  final BookRepository bookRepo;
  final PageRepository pageRepo;
  final WordRepository wordRepo;
  final ImageStorageService imageStorage;
  final NeuralTtsService? neural;

  final _uuid = const Uuid();

  /// Finds every `.pdf` under [sourceDir] (recursive) and bakes each one
  /// into a `.book.zip` inside [destDirPath]. Reports progress through
  /// [onProgress]. Individual failures are logged and the batch continues.
  Future<BakeReport> bakeAll({
    required Directory sourceDir,
    required String destDirPath,
    void Function(BakeProgress)? onProgress,
  }) async {
    final dest = Directory(destDirPath);
    if (!await dest.exists()) await dest.create(recursive: true);

    final pdfs = await _findPdfs(sourceDir);
    onProgress?.call(
      BakeProgress(done: 0, total: pdfs.length, currentTitle: ''),
    );

    var success = 0;
    var failed = 0;
    for (var i = 0; i < pdfs.length; i++) {
      final pdfPath = pdfs[i];
      final title = p.basenameWithoutExtension(pdfPath);
      onProgress?.call(
        BakeProgress(done: i, total: pdfs.length, currentTitle: title),
      );
      try {
        // Idempotent resume: skip PDFs whose .book.zip is already on disk
        // and has non-zero size. Lets us restart after a macOS sudden-
        // termination event without re-rendering 100+ books.
        final outPath = p.join(
          destDirPath,
          '${_sanitiseFilename(title)}.book.zip',
        );
        final out = File(outPath);
        if (await out.exists() && (await out.length()) > 0) {
          success++;
          continue;
        }
        await _bakeOne(pdfPath, destDirPath);
        success++;
      } catch (e, st) {
        failed++;
        LogService.instance.error('SeedBaker: failed for $pdfPath', e, st);
      }
    }
    onProgress?.call(
      BakeProgress(
        done: pdfs.length,
        total: pdfs.length,
        currentTitle: '',
      ),
    );
    return BakeReport(success: success, failed: failed);
  }

  Future<void> _bakeOne(String pdfPath, String destDirPath) async {
    final result =
        await pdfService.importPdf(pdfPath, onProgress: (_, __) {});

    final allKeys = <String>{};
    for (final page in result.pages) {
      allKeys.addAll(Tokenizer.uniqueWords(page.sentenceText));
    }
    final translations = await lookup.resolveMany(allKeys);

    final title = p.basenameWithoutExtension(pdfPath);
    final book = await bookRepo.create(title);
    final renderedAudio = <String>[];
    try {
      for (var i = 0; i < result.pages.length; i++) {
        final src = result.pages[i];
        final sentence = src.sentenceText.trim();
        final placeholder =
            await lookup.concatenateChineseFromWords(sentence) ?? '';

        // Whole-page audio (matches the InkWell tap on the whole sentence
        // bar) plus a per-sub-sentence audio map so sentence-mode taps
        // hit a bundled clip too. Anything over the size cap gets skipped
        // by `_renderSentenceAudio` and falls back to live inference at
        // runtime.
        final audioRel = await _renderSentenceAudio(sentence);
        if (audioRel != null) renderedAudio.add(audioRel);
        final sentenceAudioMap = <String, String>{};
        if (audioRel != null) sentenceAudioMap[sentence] = audioRel;
        for (final sub in splitIntoSentences(sentence)) {
          if (sub == sentence) continue;
          if (sentenceAudioMap.containsKey(sub)) continue;
          final subRel = await _renderSentenceAudio(sub);
          if (subRel != null) {
            sentenceAudioMap[sub] = subRel;
            renderedAudio.add(subRel);
          }
        }

        final pageId = await pageRepo.create(
          bookId: book.id!,
          imagePath: src.imageRelPath,
          sentenceText: sentence,
          pageNumber: i + 1,
          chineseTranslation: placeholder,
          audioPath: audioRel ?? '',
          sentenceAudioMap: sentenceAudioMap,
        );
        if (sentence.isEmpty) continue;
        final words = <WordMeaning>[];
        for (final key in Tokenizer.uniqueWords(sentence)) {
          final entry = translations[key];
          if (entry == null) continue;
          words.add(
            WordMeaning(
              id: null,
              pageId: pageId,
              word: key,
              chineseMeaning: entry.chinese,
              englishDefinition: entry.definition,
              source: WordSource.pdf,
            ),
          );
        }
        if (words.isNotEmpty) await wordRepo.replaceForPage(pageId, words);
      }
      final outPath = p.join(
        destDirPath,
        '${_sanitiseFilename(title)}.book.zip',
      );
      await share.exportBook(book.id!, outPath);
    } finally {
      final imgs = await bookRepo.deleteAndCollectImagePaths(book.id!);
      await imageStorage.deleteMany(imgs);
      // The audio files live next to the images in the docs dir; remove the
      // ones we just rendered so the bake doesn't accumulate gigabytes of
      // stale WAVs across runs.
      final docs = await getApplicationDocumentsDirectory();
      for (final rel in renderedAudio) {
        final f = File(p.join(docs.path, rel));
        if (await f.exists()) await f.delete();
      }
    }
  }

  /// Hard upper bound on what we'll pre-render at bake time. Pages with
  /// longer text are almost always OCR pickup of publisher intros / talking-
  /// points / credits pages — kids don't tap-read those, and rendering them
  /// as audio takes 20–60 seconds per page and bloats the bundle. Anything
  /// over this just gets live inference if a user ever does tap.
  static const int _maxAudioRenderChars = 300;

  /// Renders [sentence] to a WAV in the docs dir and returns the relative
  /// path (`audio/<uuid>.wav`). Returns null if no neural service is
  /// configured, the sentence is empty / too long, or rendering fails.
  Future<String?> _renderSentenceAudio(String sentence) async {
    final tts = neural;
    if (tts == null) return null;
    final trimmed = sentence.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > _maxAudioRenderChars) {
      LogService.instance.info(
        'SeedBaker: skipping audio (len=${trimmed.length} > $_maxAudioRenderChars)',
      );
      return null;
    }
    final docs = await getApplicationDocumentsDirectory();
    final rel = 'audio/${_uuid.v4()}.wav';
    final abs = p.join(docs.path, rel);
    final ok = await tts.renderToFile(sentence, abs);
    if (!ok) {
      LogService.instance.warn(
        'SeedBaker: renderToFile returned false for sentence (len=${trimmed.length})',
      );
      return null;
    }
    return rel;
  }

  static String _sanitiseFilename(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '_').trim();

  Future<List<String>> _findPdfs(Directory root) async {
    final out = <String>[];
    await for (final entity
        in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
        out.add(entity.path);
      }
    }
    out.sort();
    return out;
  }
}
