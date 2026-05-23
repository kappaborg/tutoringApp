import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sql;

import '../db/db_helper.dart';
import 'log_service.dart';

/// Single-book share format: a ZIP containing
///   • book.json — { schema_version, title, pages: [...] }
///   • images/*  — the JPEGs referenced by the pages
///
/// Lighter than the full `BackupService` ZIP and intended for AirDrop /
/// classroom-to-classroom swaps.
class BookShareService {
  BookShareService({DbHelper? dbHelper}) : _dbHelper = dbHelper ?? DbHelper.instance;
  final DbHelper _dbHelper;

  static const int _schemaVersion = 1;
  static const String _manifestName = 'book.json';

  /// Builds a .book.zip for [bookId] at [destinationPath].
  Future<File> exportBook(int bookId, String destinationPath) async {
    final db = await _dbHelper.database;
    final bookRows =
        await db.query('books', where: 'id = ?', whereArgs: [bookId], limit: 1);
    if (bookRows.isEmpty) {
      throw ArgumentError('Book $bookId not found');
    }
    final pageRows = await db.query(
      'pages',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'page_number ASC',
    );

    final wordsByPage = <int, List<Map<String, Object?>>>{};
    for (final p in pageRows) {
      final pageId = p['id']! as int;
      wordsByPage[pageId] = await db.query(
        'word_meanings',
        where: 'page_id = ?',
        whereArgs: [pageId],
      );
    }

    final archive = Archive();

    // Pull the image bytes for every page into the archive.
    final docs = await getApplicationDocumentsDirectory();
    for (final row in pageRows) {
      final relPath = row['image_path']! as String;
      final file = File(p.join(docs.path, relPath));
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
    }

    // Build the manifest with everything except DB-internal ids.
    final manifest = <String, Object?>{
      'schema_version': _schemaVersion,
      'title': bookRows.first['title'],
      'pages': [
        for (final page in pageRows)
          <String, Object?>{
            'page_number': page['page_number'],
            'image_path': page['image_path'],
            'sentence_text': page['sentence_text'],
            'chinese_translation': page['chinese_translation'] ?? '',
            'words': [
              for (final w in wordsByPage[page['id']! as int] ?? const [])
                <String, Object?>{
                  'word': w['word'],
                  'chinese_meaning': w['chinese_meaning'],
                  'english_definition': w['english_definition'],
                  'tts_override': w['tts_override'],
                  'source': w['source'],
                },
            ],
          },
      ],
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile(_manifestName, manifestBytes.length, manifestBytes),
    );

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw const FileSystemException('Failed to encode .book.zip');
    }
    final out = File(destinationPath);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(encoded, flush: true);
    LogService.instance.info('Exported book $bookId to ${out.path}');
    return out;
  }

  /// Imports a .book.zip. Image files inside the archive are copied into the
  /// app's images directory, with their relative paths preserved so the
  /// existing `pages.image_path` references stay valid.
  Future<int> importBook(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestEntry = archive.findFile(_manifestName);
    if (manifestEntry == null) {
      throw const FormatException('Backup is missing book.json');
    }
    final manifest = jsonDecode(
      utf8.decode(manifestEntry.content as List<int>),
    ) as Map<String, Object?>;
    final schemaVersion = manifest['schema_version'] as int? ?? -1;
    if (schemaVersion != _schemaVersion) {
      throw FormatException(
        'Book schema version $schemaVersion is not supported '
        '(expected $_schemaVersion).',
      );
    }
    final title = (manifest['title'] as String?) ?? 'Imported Book';
    final pages = (manifest['pages'] as List?) ?? const [];

    // Stage images into the docs directory, ignoring filename collisions
    // by renaming. We track the rename so manifest references update.
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final pathRemap = <String, String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name == _manifestName) continue;
      if (!file.name.startsWith('images/')) continue;
      var dest = File(p.join(docs.path, file.name));
      // If a file already exists at this path, rename ours to avoid clobber.
      if (await dest.exists()) {
        final base = p.basenameWithoutExtension(file.name);
        final ext = p.extension(file.name);
        final unique =
            '${base}_${DateTime.now().microsecondsSinceEpoch}$ext';
        final newRel = 'images/$unique';
        dest = File(p.join(docs.path, newRel));
        pathRemap[file.name] = newRel;
      }
      await dest.writeAsBytes(file.content as List<int>, flush: true);
    }

    final db = await _dbHelper.database;
    return db.transaction<int>((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final bookId = await txn.insert('books', <String, Object?>{
        'title': title,
        'created_at': now,
        'updated_at': now,
      });
      var pageNumber = 0;
      for (final raw in pages) {
        if (raw is! Map) continue;
        final pageMap = raw.cast<String, Object?>();
        pageNumber++;
        final origImage = pageMap['image_path'] as String? ?? '';
        final remapped = pathRemap[origImage] ?? origImage;
        final pageId = await txn.insert('pages', <String, Object?>{
          'book_id': bookId,
          'page_number': pageMap['page_number'] ?? pageNumber,
          'image_path': remapped,
          'sentence_text': pageMap['sentence_text'] ?? '',
          'chinese_translation': pageMap['chinese_translation'] ?? '',
        });
        for (final w in (pageMap['words'] as List?) ?? const []) {
          if (w is! Map) continue;
          final wm = w.cast<String, Object?>();
          await txn.insert(
            'word_meanings',
            <String, Object?>{
              'page_id': pageId,
              'word': (wm['word'] as String? ?? '').toLowerCase(),
              'chinese_meaning': wm['chinese_meaning'] ?? '',
              'english_definition': wm['english_definition'] ?? '',
              'tts_override': wm['tts_override'],
              'source': wm['source'] ?? 'manual',
            },
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        }
      }
      LogService.instance.info('Imported book "$title" ($bookId)');
      return bookId;
    });
  }
}
