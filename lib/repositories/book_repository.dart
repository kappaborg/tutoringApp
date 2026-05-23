import 'package:sqflite/sqflite.dart';

import '../db/db_helper.dart';
import '../models/book.dart';

class BookRepository {
  BookRepository({DbHelper? dbHelper}) : _dbHelper = dbHelper ?? DbHelper.instance;
  final DbHelper _dbHelper;

  Future<Database> get _db => _dbHelper.database;

  Future<List<Book>> listAll() async {
    final db = await _db;
    final rows = await db.query('books', orderBy: 'updated_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<Book?> findById(int id) async {
    final db = await _db;
    final rows = await db.query('books', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Book.fromMap(rows.first);
  }

  Future<Book> create(String title) async {
    final db = await _db;
    final now = DateTime.now();
    final id = await db.insert('books', <String, Object?>{
      'title': title.trim(),
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return Book(id: id, title: title.trim(), createdAt: now, updatedAt: now);
  }

  Future<void> rename(int id, String title) async {
    final db = await _db;
    await db.update(
      'books',
      <String, Object?>{
        'title': title.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touch(int id) async {
    final db = await _db;
    await db.update(
      'books',
      <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns the list of `image_path` rows that belonged to this book so the
  /// caller can delete orphaned files from disk after the row cascade.
  Future<List<String>> deleteAndCollectImagePaths(int id) async {
    final db = await _db;
    return db.transaction<List<String>>((txn) async {
      final imgs = await txn.query(
        'pages',
        columns: ['image_path'],
        where: 'book_id = ?',
        whereArgs: [id],
      );
      final paths = imgs.map((r) => r['image_path']! as String).toList();
      await txn.delete('books', where: 'id = ?', whereArgs: [id]);
      return paths;
    });
  }
}
