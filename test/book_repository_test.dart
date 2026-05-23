import 'package:flutter_test/flutter_test.dart';
import 'package:picture_book/db/migrations.dart';
import 'package:picture_book/repositories/book_repository.dart';
import 'package:picture_book/repositories/page_repository.dart';
import 'package:picture_book/repositories/word_repository.dart';
import 'package:picture_book/models/word_meaning.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db_helper.dart';

void main() {
  late Database db;
  late TestDbHelper helper;
  late BookRepository bookRepo;
  late PageRepository pageRepo;
  late WordRepository wordRepo;

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
  });

  tearDown(() async => db.close());

  test('create and read a book', () async {
    final book = await bookRepo.create('Hello');
    final loaded = await bookRepo.findById(book.id!);
    expect(loaded?.title, 'Hello');
  });

  test('cascade delete removes pages and words', () async {
    final book = await bookRepo.create('Hello');
    final pageId = await pageRepo.create(
      bookId: book.id!,
      imagePath: 'images/x.jpg',
      sentenceText: 'Hi there.',
    );
    await wordRepo.replaceForPage(pageId, [
      WordMeaning(
        id: null,
        pageId: pageId,
        word: 'hi',
        chineseMeaning: '你好',
        englishDefinition: 'Greeting.',
      ),
    ]);
    final paths = await bookRepo.deleteAndCollectImagePaths(book.id!);
    expect(paths, ['images/x.jpg']);
    final pages = await pageRepo.listByBook(book.id!);
    expect(pages, isEmpty);
    final words = await wordRepo.listByPage(pageId);
    expect(words, isEmpty);
  });

  test('replaceForPage atomically resets word list', () async {
    final book = await bookRepo.create('B');
    final pageId = await pageRepo.create(
      bookId: book.id!,
      imagePath: 'images/x.jpg',
      sentenceText: 'A b c.',
    );
    await wordRepo.replaceForPage(pageId, [
      WordMeaning(
        id: null,
        pageId: pageId,
        word: 'a',
        chineseMeaning: '甲',
        englishDefinition: 'A',
      ),
      WordMeaning(
        id: null,
        pageId: pageId,
        word: 'b',
        chineseMeaning: '乙',
        englishDefinition: 'B',
      ),
    ]);
    expect((await wordRepo.listByPage(pageId)).length, 2);
    await wordRepo.replaceForPage(pageId, [
      WordMeaning(
        id: null,
        pageId: pageId,
        word: 'c',
        chineseMeaning: '丙',
        englishDefinition: 'C',
      ),
    ]);
    final words = await wordRepo.listByPage(pageId);
    expect(words.map((w) => w.word), ['c']);
  });

  test('v1 → v2 migration adds source column with default "manual"', () async {
    // Build a v1 schema by running only _v1's worth of statements.
    final legacy = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE books (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'title TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE pages (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER NOT NULL, page_number INTEGER NOT NULL, '
            'image_path TEXT NOT NULL, sentence_text TEXT NOT NULL, '
            'FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE, '
            'UNIQUE (book_id, page_number))',
          );
          await db.execute(
            'CREATE TABLE word_meanings (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'page_id INTEGER NOT NULL, word TEXT NOT NULL, '
            'chinese_meaning TEXT NOT NULL, english_definition TEXT NOT NULL, '
            'tts_override TEXT, '
            'FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE, '
            'UNIQUE (page_id, word))',
          );
        },
      ),
    );
    // Insert a row pre-migration.
    final now = DateTime.now().millisecondsSinceEpoch;
    final bookId = await legacy.insert('books', {
      'title': 'Legacy',
      'created_at': now,
      'updated_at': now,
    });
    final pageId = await legacy.insert('pages', {
      'book_id': bookId,
      'page_number': 1,
      'image_path': 'images/x.jpg',
      'sentence_text': 'hi',
    });
    await legacy.insert('word_meanings', {
      'page_id': pageId,
      'word': 'hi',
      'chinese_meaning': '你好',
      'english_definition': 'Greeting.',
    });
    // Apply v2 migration manually.
    await Migrations.onUpgrade(legacy, 1, 2);
    final cols = await legacy.rawQuery('PRAGMA table_info(word_meanings)');
    expect(cols.any((c) => c['name'] == 'source'), isTrue);
    final rows = await legacy.query('word_meanings');
    expect(rows.first['source'], 'manual');
    await legacy.close();
  });

  test('v2 → v3 migration adds chinese_translation with default \'\'', () async {
    final legacy = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE books (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'title TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE pages (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'book_id INTEGER NOT NULL, page_number INTEGER NOT NULL, '
            'image_path TEXT NOT NULL, sentence_text TEXT NOT NULL, '
            'FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE, '
            'UNIQUE (book_id, page_number))',
          );
          await db.execute(
            'CREATE TABLE word_meanings (id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'page_id INTEGER NOT NULL, word TEXT NOT NULL, '
            'chinese_meaning TEXT NOT NULL, english_definition TEXT NOT NULL, '
            "tts_override TEXT, source TEXT NOT NULL DEFAULT 'manual', "
            'FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE, '
            'UNIQUE (page_id, word))',
          );
        },
      ),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final bookId = await legacy.insert('books', {
      'title': 'Legacy v2',
      'created_at': now,
      'updated_at': now,
    });
    await legacy.insert('pages', {
      'book_id': bookId,
      'page_number': 1,
      'image_path': 'images/x.jpg',
      'sentence_text': 'hello',
    });
    await Migrations.onUpgrade(legacy, 2, 3);
    final cols = await legacy.rawQuery('PRAGMA table_info(pages)');
    expect(cols.any((c) => c['name'] == 'chinese_translation'), isTrue);
    final rows = await legacy.query('pages');
    expect(rows.first['chinese_translation'], '');
    await legacy.close();
  });

  test('reorder respects UNIQUE(book_id, page_number)', () async {
    final book = await bookRepo.create('B');
    final p1 = await pageRepo.create(
      bookId: book.id!,
      imagePath: 'images/a.jpg',
      sentenceText: 'one',
    );
    final p2 = await pageRepo.create(
      bookId: book.id!,
      imagePath: 'images/b.jpg',
      sentenceText: 'two',
    );
    final p3 = await pageRepo.create(
      bookId: book.id!,
      imagePath: 'images/c.jpg',
      sentenceText: 'three',
    );
    await pageRepo.reorder(book.id!, [p3, p1, p2]);
    final pages = await pageRepo.listByBook(book.id!);
    expect(pages.map((p) => p.id), [p3, p1, p2]);
    expect(pages.map((p) => p.pageNumber), [1, 2, 3]);
  });
}
