import 'package:sqflite/sqflite.dart';

import '../db/db_helper.dart';
import '../models/page.dart';

class PageRepository {
  PageRepository({DbHelper? dbHelper}) : _dbHelper = dbHelper ?? DbHelper.instance;
  final DbHelper _dbHelper;

  Future<Database> get _db => _dbHelper.database;

  Future<List<BookPage>> listByBook(int bookId) async {
    final db = await _db;
    final rows = await db.query(
      'pages',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page_number ASC',
    );
    return rows.map(BookPage.fromMap).toList();
  }

  Future<BookPage?> findById(int id) async {
    final db = await _db;
    final rows = await db.query('pages', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return BookPage.fromMap(rows.first);
  }

  Future<int> _nextPageNumber(DatabaseExecutor txn, int bookId) async {
    final rows = await txn.rawQuery(
      'SELECT COALESCE(MAX(page_number), 0) + 1 AS n FROM pages WHERE book_id = ?',
      [bookId],
    );
    return rows.first['n']! as int;
  }

  Future<int> create({
    required int bookId,
    required String imagePath,
    required String sentenceText,
    int? pageNumber,
    String chineseTranslation = '',
  }) async {
    final db = await _db;
    return db.transaction<int>((txn) async {
      final number = pageNumber ?? await _nextPageNumber(txn, bookId);
      final id = await txn.insert('pages', <String, Object?>{
        'book_id': bookId,
        'page_number': number,
        'image_path': imagePath,
        'sentence_text': sentenceText,
        'chinese_translation': chineseTranslation,
      });
      await txn.update(
        'books',
        <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [bookId],
      );
      return id;
    });
  }

  /// Updates a page. Returns the previous image path if it changed (so caller
  /// can delete the orphan file), else null.
  Future<String?> update({
    required int id,
    required String imagePath,
    required String sentenceText,
    String chineseTranslation = '',
  }) async {
    final db = await _db;
    return db.transaction<String?>((txn) async {
      final rows = await txn.query(
        'pages',
        columns: ['image_path', 'book_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final oldImage = rows.first['image_path']! as String;
      final bookId = rows.first['book_id']! as int;
      await txn.update(
        'pages',
        <String, Object?>{
          'image_path': imagePath,
          'sentence_text': sentenceText,
          'chinese_translation': chineseTranslation,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'books',
        <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [bookId],
      );
      return oldImage == imagePath ? null : oldImage;
    });
  }

  /// Deletes a page and returns its image path so the caller can clean up disk.
  Future<String?> delete(int id) async {
    final db = await _db;
    return db.transaction<String?>((txn) async {
      final rows = await txn.query(
        'pages',
        columns: ['image_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final imagePath = rows.first['image_path']! as String;
      await txn.delete('pages', where: 'id = ?', whereArgs: [id]);
      return imagePath;
    });
  }

  Future<void> reorder(int bookId, List<int> orderedPageIds) async {
    final db = await _db;
    await db.transaction((txn) async {
      // Two-phase: move everyone to negative temporary numbers, then assign
      // the new positive numbers to satisfy the UNIQUE constraint.
      for (var i = 0; i < orderedPageIds.length; i++) {
        await txn.update(
          'pages',
          <String, Object?>{'page_number': -(i + 1)},
          where: 'id = ? AND book_id = ?',
          whereArgs: [orderedPageIds[i], bookId],
        );
      }
      for (var i = 0; i < orderedPageIds.length; i++) {
        await txn.update(
          'pages',
          <String, Object?>{'page_number': i + 1},
          where: 'id = ? AND book_id = ?',
          whereArgs: [orderedPageIds[i], bookId],
        );
      }
      await txn.update(
        'books',
        <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [bookId],
      );
    });
  }
}
