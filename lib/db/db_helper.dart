import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// Singleton wrapper around the application SQLite database.
///
/// Database lives in `getApplicationSupportDirectory()` because it is not
/// user-facing content; user images live in documents directory instead.
class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static const String dbFileName = 'picturebook.db';

  Database? _db;
  Completer<Database>? _opening;

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;
    final completer = Completer<Database>();
    _opening = completer;
    try {
      final db = await _open();
      _db = db;
      completer.complete(db);
      return db;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _opening = null;
    }
  }

  Future<String> resolveDbPath() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return p.join(dir.path, dbFileName);
  }

  Future<Database> _open() async {
    final path = await resolveDbPath();
    return openDatabase(
      path,
      version: Migrations.latestVersion,
      onConfigure: (db) async {
        // sqflite drops PRAGMA state per connection; re-enable each time.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: Migrations.onCreate,
      onUpgrade: Migrations.onUpgrade,
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  /// Replaces the underlying DB file (used by restore). Closes any open handle
  /// first; the next call to [database] reopens against the new file.
  Future<void> replaceDbFile(File source) async {
    await close();
    final target = File(await resolveDbPath());
    await source.copy(target.path);
  }
}
