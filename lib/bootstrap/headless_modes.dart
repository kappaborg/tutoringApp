import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' show pdfrxFlutterInitialize;

import '../db/db_helper.dart';
import '../repositories/book_repository.dart';
import '../repositories/page_repository.dart';
import '../repositories/word_repository.dart';
import '../services/book_share_service.dart';
import '../services/dictionary_service.dart';
import '../services/image_storage_service.dart';
import '../services/log_service.dart';
import '../services/neural_tts_service.dart';
import '../services/pdf_import_service.dart';
import '../services/seed_baker_service.dart';
import '../services/seed_service.dart';
import '../services/translation_lookup.dart';

/// Developer / CLI entry points that short-circuit the normal `runApp` flow:
///
///   * `--bake-dir=<src> [--bake-out=<dst>]` — batch-import every PDF under
///     [src] through the full pipeline and write a `.book.zip` per book to
///     [dst]. Used to regenerate the bundled Oxford library.
///   * `--probe-pdf=<file>` — open a single PDF page-by-page (render + OCR)
///     so we can see where pdfrx/Vision breaks for a particular file.
///
/// Returns `true` if a headless mode was requested and handled (and the
/// caller should `exit(0)`). Returns `false` otherwise — proceed with the
/// normal app startup.
Future<bool> runHeadlessModeIfRequested(List<String> args) async {
  final bakeDir =
      _argValue(args, 'bake-dir') ?? Platform.environment['BAKE_DIR'];
  if (bakeDir != null && bakeDir.isNotEmpty) {
    final bakeOut = _argValue(args, 'bake-out') ??
        Platform.environment['BAKE_OUT'] ??
        p.join(Directory.current.path, 'assets', 'seed', 'oxford');
    await _runHeadlessBake(sourceDir: bakeDir, destDir: bakeOut);
    return true;
  }

  final probePdf = _argValue(args, 'probe-pdf');
  if (probePdf != null && probePdf.isNotEmpty) {
    await _runProbePdf(probePdf);
    return true;
  }

  return false;
}

String? _argValue(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

Future<void> _runHeadlessBake({
  required String sourceDir,
  required String destDir,
}) async {
  // Ensure Flutter bindings before any plugin call. The caller (`main`)
  // already does this for the normal path; in headless mode we may have
  // returned before then.
  WidgetsFlutterBinding.ensureInitialized();
  // pdfrx's Flutter init is normally triggered by the widget tree on first
  // PdfDocument call; in headless mode (no `runApp`) we have to do it
  // ourselves before importing any PDF.
  await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);

  final db = await DbHelper.instance.database;
  await SeedService.seedIfEmpty(db);

  final pdfImport = PdfImportService();
  final dictionary = DictionaryService();
  await dictionary.init();
  final translationLookup = TranslationLookup(dictionary);
  final share = BookShareService();

  // Optional neural TTS pre-render. If the model isn't bundled or init
  // fails, the bake still completes — books just ship without audio and
  // the runtime falls back to live inference.
  final neural = NeuralTtsService();
  await neural.init();
  final neuralOk = neural.availability == NeuralTtsAvailability.ready;
  stdout.writeln(
    '[bake] neural TTS: ${neuralOk ? "ready (will render audio)" : neural.availability.name}',
  );
  if (!neuralOk) {
    LogService.instance.warn(
      'Bake proceeding without neural pre-render — '
      'availability=${neural.availability.name}',
    );
  }

  final baker = SeedBakerService(
    pdfService: pdfImport,
    lookup: translationLookup,
    share: share,
    bookRepo: BookRepository(),
    pageRepo: PageRepository(),
    wordRepo: WordRepository(),
    imageStorage: ImageStorageService(),
    neural: neuralOk ? neural : null,
  );

  stdout.writeln('[bake] source: $sourceDir');
  stdout.writeln('[bake] output: $destDir');
  final report = await baker.bakeAll(
    sourceDir: Directory(sourceDir),
    destDirPath: destDir,
    onProgress: (snap) {
      if (snap.total == 0) return;
      final pct = (snap.done * 100 / snap.total).toStringAsFixed(0);
      stdout.writeln(
        '[bake] $pct%  ${snap.done}/${snap.total}  ${snap.currentTitle}',
      );
    },
  );
  stdout.writeln(
    '[bake] done — success=${report.success} failed=${report.failed}',
  );
}

Future<void> _runProbePdf(String pdfPath) async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
  stdout.writeln('[probe] full import (render + ocr) of $pdfPath');
  final svc = PdfImportService();
  final result = await svc.importPdf(
    pdfPath,
    onProgress: (done, total) {
      stdout.writeln('[probe] importPdf $done/$total');
    },
  );
  for (var i = 0; i < result.pages.length; i++) {
    final pg = result.pages[i];
    stdout.writeln(
      '[probe] page ${i + 1}: ${pg.sentenceSource.name}, '
      '${pg.sentenceText.length} chars',
    );
  }
  stdout.writeln('[probe] done');
}
