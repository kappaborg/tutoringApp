import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picture_book/db/db_helper.dart';
import 'package:picture_book/repositories/book_repository.dart';
import 'package:picture_book/repositories/page_repository.dart';
import 'package:picture_book/services/backup_service.dart';
import 'package:picture_book/utils/sentence_splitter.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Verifies that a multi-sentence page round-trips through the v3 backup
/// and that the reader's sentence splitter still finds the same sentence
/// count after import.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory(p.join(root.path, 'support'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = Directory(p.join(root.path, 'docs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pb_backup_');
    PathProviderPlatform.instance = _FakePathProvider(tmp);
  });

  tearDown(() async {
    await DbHelper.instance.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('multi-sentence page survives v3 export/import + splits correctly',
      () async {
    // Force the DB to live under the fake support dir.
    final dbHelper = DbHelper.instance;
    final db = await dbHelper.database;
    // The DB just created should be at v3 from onCreate.
    final cols = await db.rawQuery('PRAGMA table_info(pages)');
    expect(cols.any((c) => c['name'] == 'chinese_translation'), isTrue);

    final bookRepo = BookRepository(dbHelper: dbHelper);
    final pageRepo = PageRepository(dbHelper: dbHelper);

    final docs = await PathProviderPlatform.instance.getApplicationDocumentsPath();
    final imagesDir = Directory(p.join(docs!, 'images'));
    await imagesDir.create(recursive: true);
    final fakeImage = File(p.join(imagesDir.path, 'fake.jpg'));
    await fakeImage.writeAsBytes(List.filled(64, 0));

    final book = await bookRepo.create('Roundtrip Book');
    const multiSentence =
        'The cat sat on the mat. A dog ran past. The sun was bright today.';
    await pageRepo.create(
      bookId: book.id!,
      imagePath: 'images/fake.jpg',
      sentenceText: multiSentence,
      pageNumber: 1,
    );

    // Export
    final zipPath = p.join(tmp.path, 'backup.zip');
    final backup = BackupService(dbHelper: dbHelper);
    await backup.exportToZip(zipPath);
    expect(await File(zipPath).exists(), isTrue);

    // Wipe local DB + images.
    await dbHelper.close();
    final dbFile = File(await dbHelper.resolveDbPath());
    if (await dbFile.exists()) await dbFile.delete();
    if (await imagesDir.exists()) {
      await for (final f in imagesDir.list()) {
        if (f is File) await f.delete();
      }
    }

    // Import
    final summary = await backup.importFromZip(zipPath);
    expect(summary.bookCount, 1);
    expect(summary.pageCount, 1);

    // Verify post-import: page text intact + splitter produces 3 sentences.
    final pages = await pageRepo.listByBook(book.id!);
    expect(pages.length, 1);
    expect(pages.first.sentenceText, multiSentence);
    final split = splitIntoSentences(pages.first.sentenceText);
    expect(split.length, 3);

    // Verify migration ran (chinese_translation column present and defaulted).
    expect(pages.first.chineseTranslation, '');
  });
}
