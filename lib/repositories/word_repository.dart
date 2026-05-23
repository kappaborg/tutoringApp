import 'package:sqflite/sqflite.dart';

import '../db/db_helper.dart';
import '../models/word_meaning.dart';

class WordRepository {
  WordRepository({DbHelper? dbHelper}) : _dbHelper = dbHelper ?? DbHelper.instance;
  final DbHelper _dbHelper;

  Future<Database> get _db => _dbHelper.database;

  Future<List<WordMeaning>> listByPage(int pageId) async {
    final db = await _db;
    final rows = await db.query(
      'word_meanings',
      where: 'page_id = ?',
      whereArgs: [pageId],
      orderBy: 'word ASC',
    );
    return rows.map(WordMeaning.fromMap).toList();
  }

  /// Returns a map keyed by lowercase word for O(1) lookup from the reader.
  Future<Map<String, WordMeaning>> mapByPage(int pageId) async {
    final words = await listByPage(pageId);
    return <String, WordMeaning>{for (final w in words) w.word: w};
  }

  Future<WordMeaning?> findByPageAndWord(int pageId, String word) async {
    final db = await _db;
    final rows = await db.query(
      'word_meanings',
      where: 'page_id = ? AND word = ?',
      whereArgs: [pageId, word.toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WordMeaning.fromMap(rows.first);
  }

  /// Replaces the entire word list for a page atomically.
  Future<void> replaceForPage(int pageId, List<WordMeaning> words) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('word_meanings', where: 'page_id = ?', whereArgs: [pageId]);
      for (final w in words) {
        await txn.insert('word_meanings', <String, Object?>{
          'page_id': pageId,
          'word': w.word.toLowerCase().trim(),
          'chinese_meaning': w.chineseMeaning.trim(),
          'english_definition': w.englishDefinition.trim(),
          'tts_override': w.ttsOverride?.trim(),
          'source': w.source.value,
        });
      }
    });
  }

  Future<void> insert(WordMeaning meaning) async {
    final db = await _db;
    await db.insert(
      'word_meanings',
      meaning.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('word_meanings', where: 'id = ?', whereArgs: [id]);
  }
}
