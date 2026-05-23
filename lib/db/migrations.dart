import 'package:sqflite/sqflite.dart';

class Migrations {
  static const int latestVersion = 3;

  static Future<void> onCreate(Database db, int version) async {
    await _v1(db);
    await _v2(db);
    await _v3(db);
  }

  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 1) await _v1(db);
    if (oldVersion < 2) await _v2(db);
    if (oldVersion < 3) await _v3(db);
  }

  static Future<void> _v1(Database db) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        page_number INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        sentence_text TEXT NOT NULL,
        FOREIGN KEY (book_id) REFERENCES books(id) ON DELETE CASCADE,
        UNIQUE (book_id, page_number)
      )
    ''');
    await db.execute('''
      CREATE TABLE word_meanings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        page_id INTEGER NOT NULL,
        word TEXT NOT NULL,
        chinese_meaning TEXT NOT NULL,
        english_definition TEXT NOT NULL,
        tts_override TEXT,
        FOREIGN KEY (page_id) REFERENCES pages(id) ON DELETE CASCADE,
        UNIQUE (page_id, word)
      )
    ''');
    await db.execute('CREATE INDEX idx_pages_book ON pages(book_id, page_number)');
    await db.execute('CREATE INDEX idx_words_page ON word_meanings(page_id, word)');
  }

  /// v2: record where each word meaning came from.
  static Future<void> _v2(Database db) async {
    // Defensive: skip if the column is already present (e.g. fresh install
    // already ran _v1 + _v2 inside onCreate).
    final cols = await db.rawQuery("PRAGMA table_info(word_meanings)");
    final hasSource = cols.any((row) => row['name'] == 'source');
    if (hasSource) return;
    await db.execute(
      "ALTER TABLE word_meanings ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'",
    );
    await db.execute(
      "UPDATE word_meanings SET source = 'manual' WHERE source IS NULL OR source = ''",
    );
  }

  /// v3: each page can carry a whole-sentence Chinese translation.
  static Future<void> _v3(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(pages)");
    final hasIt = cols.any((row) => row['name'] == 'chinese_translation');
    if (hasIt) return;
    await db.execute(
      "ALTER TABLE pages ADD COLUMN chinese_translation TEXT NOT NULL DEFAULT ''",
    );
  }
}
