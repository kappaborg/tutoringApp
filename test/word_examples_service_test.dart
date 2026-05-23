import 'package:flutter_test/flutter_test.dart';
import 'package:picture_book/db/migrations.dart';
import 'package:picture_book/models/word_meaning.dart';
import 'package:picture_book/repositories/book_repository.dart';
import 'package:picture_book/repositories/page_repository.dart';
import 'package:picture_book/repositories/word_repository.dart';
import 'package:picture_book/services/word_examples_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db_helper.dart';

void main() {
  late Database db;
  late TestDbHelper helper;
  late BookRepository bookRepo;
  late PageRepository pageRepo;
  late WordRepository wordRepo;
  late WordExamplesService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: Migrations.latestVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: Migrations.onCreate,
      ),
    );
    helper = TestDbHelper(db);
    bookRepo = BookRepository(dbHelper: helper);
    pageRepo = PageRepository(dbHelper: helper);
    wordRepo = WordRepository(dbHelper: helper);
    service = WordExamplesService(dbHelper: helper);
  });

  tearDown(() async => db.close());

  Future<int> seedPage(int bookId, int n, String sentence, List<String> keys) async {
    final pageId = await pageRepo.create(
      bookId: bookId,
      imagePath: 'images/p$n.jpg',
      sentenceText: sentence,
      pageNumber: n,
    );
    await wordRepo.replaceForPage(
      pageId,
      keys
          .map(
            (k) => WordMeaning(
              id: null,
              pageId: pageId,
              word: k,
              chineseMeaning: '猫',
              englishDefinition: 'animal',
            ),
          )
          .toList(),
    );
    return pageId;
  }

  test('findExamples returns book-corpus sentences and respects excludePageId',
      () async {
    final bookA = await bookRepo.create('Book A');
    final bookB = await bookRepo.create('Book B');
    final pa1 = await seedPage(bookA.id!, 1, 'The cat sleeps.', ['cat', 'sleeps']);
    await seedPage(bookA.id!, 2, 'A black cat sat.', ['cat', 'sat']);
    await seedPage(bookB.id!, 1, 'The cat runs.', ['cat', 'runs']);

    final out = await service.findExamples('cat', excludePageId: pa1);
    expect(out.length, greaterThanOrEqualTo(2));
    expect(out.every((e) => e.isFromBookCorpus), isTrue);
    expect(out.every((e) => e.pageId != pa1), isTrue);
    expect(out.map((e) => e.bookTitle).toSet(), {'Book A', 'Book B'});
  });

  test('findExamples returns nothing for a word that does not appear', () async {
    final book = await bookRepo.create('B');
    await seedPage(book.id!, 1, 'Hello world.', ['hello', 'world']);
    expect(await service.findExamples('elephant'), isEmpty);
  });
}
