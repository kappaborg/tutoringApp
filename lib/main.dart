import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'app.dart';
import 'db/db_helper.dart';
import 'repositories/book_repository.dart';
import 'repositories/page_repository.dart';
import 'repositories/word_repository.dart';
import 'services/book_share_service.dart';
import 'services/debug_network_probe.dart';
import 'services/dictionary_service.dart';
import 'services/image_storage_service.dart';
import 'services/log_service.dart';
import 'services/pdf_import_service.dart';
import 'services/prefs_service.dart';
import 'services/seed_service.dart';
import 'services/translation_lookup.dart';
import 'services/tts_service.dart';
import 'services/word_examples_service.dart';
import 'state/admin_auth.dart';
import 'state/library_notifier.dart';
import 'state/locale_notifier.dart';
import 'state/settings_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop SQLite uses sqflite_common_ffi.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    ffi.sqfliteFfiInit();
    ffi.databaseFactory = ffi.databaseFactoryFfi;
  }

  await LogService.instance.init();

  FlutterError.onError = (details) {
    LogService.instance.error(
      'FlutterError',
      details.exception,
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    LogService.instance.error('PlatformDispatcher', error, stack);
    return true;
  };

  final prefs = await PrefsService.init();
  final db = await DbHelper.instance.database;
  await SeedService.seedIfEmpty(db);

  // Debug-only reachability probe; no payload sent.
  await runDebugNetworkProbe();

  final imageStorage = ImageStorageService();
  final bookRepo = BookRepository();
  final pageRepo = PageRepository();
  final wordRepo = WordRepository();
  final tts = TtsService(prefs: prefs);
  await tts.init();

  final dictionary = DictionaryService();
  await dictionary.init();
  final translationLookup = TranslationLookup(dictionary);
  final pdfImport = PdfImportService();
  final wordExamples = WordExamplesService(dictionary: dictionary);
  final bookShare = BookShareService();

  runApp(
    MultiProvider(
      providers: [
        Provider<PrefsService>.value(value: prefs),
        Provider<ImageStorageService>.value(value: imageStorage),
        Provider<BookRepository>.value(value: bookRepo),
        Provider<PageRepository>.value(value: pageRepo),
        Provider<WordRepository>.value(value: wordRepo),
        Provider<DictionaryService>.value(value: dictionary),
        Provider<TranslationLookup>.value(value: translationLookup),
        Provider<PdfImportService>.value(value: pdfImport),
        Provider<WordExamplesService>.value(value: wordExamples),
        Provider<BookShareService>.value(value: bookShare),
        ChangeNotifierProvider<TtsService>.value(value: tts),
        ChangeNotifierProvider<AdminAuth>(create: (_) => AdminAuth()),
        ChangeNotifierProvider<SettingsNotifier>(
          create: (_) => SettingsNotifier(prefs),
        ),
        ChangeNotifierProvider<LocaleNotifier>(
          create: (_) => LocaleNotifier(prefs),
        ),
        ChangeNotifierProvider<LibraryNotifier>(
          create: (_) => LibraryNotifier(
            bookRepo: bookRepo,
            pageRepo: pageRepo,
            wordRepo: wordRepo,
            imageStorage: imageStorage,
            prefs: prefs,
          ),
        ),
      ],
      child: const PictureBookApp(),
    ),
  );
}
