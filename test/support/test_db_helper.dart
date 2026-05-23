import 'dart:io';

import 'package:picture_book/db/db_helper.dart';
import 'package:sqflite/sqflite.dart';

/// In-memory replacement for DbHelper used in unit tests. Implements only the
/// surface that the repositories touch.
class TestDbHelper implements DbHelper {
  TestDbHelper(this._db);
  final Database _db;

  @override
  Future<Database> get database async => _db;

  @override
  Future<void> close() async => _db.close();

  @override
  Future<String> resolveDbPath() async => ':memory:';

  @override
  Future<void> replaceDbFile(File source) async =>
      throw UnsupportedError('Not used in tests');
}
