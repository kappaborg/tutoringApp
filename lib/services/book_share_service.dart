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

  // v1 = images + text.
  // v2 = adds per-page `audio_path` for bundled neural-TTS clips.
  // v3 = adds per-sentence audio map (`sentence_audio_map`) so reader
  //      sentence-mode taps also hit a bundled clip.
  // Importer accepts any earlier version; missing audio fields fall back
  // to live inference at runtime.
  static const int _schemaVersion = 3;
  static const Set<int> _acceptedSchemaVersions = {1, 2, 3};
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
    final docs = await getApplicationDocumentsDirectory();
    final addedToZip = <String>{};

    Future<void> includeAudio(String? rel) async {
      if (rel == null || rel.isEmpty) return;
      if (!addedToZip.add(rel)) return; // de-dup
      final audioFile = File(p.join(docs.path, rel));
      if (!await audioFile.exists()) return;
      final bytes = await audioFile.readAsBytes();
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
    }

    // Pull the image, the whole-page audio AND every per-sentence audio
    // referenced by sentence_audio_map for every page into the archive.
    for (final row in pageRows) {
      final imageRel = row['image_path']! as String;
      final imageFile = File(p.join(docs.path, imageRel));
      if (await imageFile.exists()) {
        final bytes = await imageFile.readAsBytes();
        archive.addFile(ArchiveFile(imageRel, bytes.length, bytes));
      }
      await includeAudio((row['audio_path'] as String?) ?? '');
      final mapJson = (row['sentence_audio_map'] as String?) ?? '{}';
      for (final v in _decodeMap(mapJson).values) {
        await includeAudio(v);
      }
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
            'audio_path': page['audio_path'] ?? '',
            'sentence_audio_map':
                (page['sentence_audio_map'] as String?) ?? '{}',
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
    if (!_acceptedSchemaVersions.contains(schemaVersion)) {
      throw FormatException(
        'Book schema version $schemaVersion is not supported '
        '(expected one of ${_acceptedSchemaVersions.join(", ")}).',
      );
    }
    final title = (manifest['title'] as String?) ?? 'Imported Book';
    final pages = (manifest['pages'] as List?) ?? const [];

    // Stage images and audio into the docs directory, ignoring filename
    // collisions by renaming. We track each rename so manifest references
    // can be rewritten before the DB inserts.
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final audioDir = Directory(p.join(docs.path, 'audio'));
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    final pathRemap = <String, String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name == _manifestName) continue;
      if (!file.name.startsWith('images/') &&
          !file.name.startsWith('audio/')) {
        continue;
      }
      var dest = File(p.join(docs.path, file.name));
      if (await dest.exists()) {
        final base = p.basenameWithoutExtension(file.name);
        final ext = p.extension(file.name);
        final unique =
            '${base}_${DateTime.now().microsecondsSinceEpoch}$ext';
        final subdir = file.name.startsWith('audio/') ? 'audio' : 'images';
        final newRel = '$subdir/$unique';
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
        final imageRemapped = pathRemap[origImage] ?? origImage;
        final origAudio = pageMap['audio_path'] as String? ?? '';
        final audioRemapped =
            origAudio.isEmpty ? '' : (pathRemap[origAudio] ?? origAudio);

        // Rewrite each value in sentence_audio_map through the collision
        // remap so it points at the on-device staging location.
        final origMapJson =
            pageMap['sentence_audio_map'] as String? ?? '{}';
        final origMap = _decodeMap(origMapJson);
        final remappedMap = <String, String>{};
        for (final e in origMap.entries) {
          remappedMap[e.key] = pathRemap[e.value] ?? e.value;
        }
        final remappedMapJson = jsonEncode(remappedMap);

        final pageId = await txn.insert('pages', <String, Object?>{
          'book_id': bookId,
          'page_number': pageMap['page_number'] ?? pageNumber,
          'image_path': imageRemapped,
          'sentence_text': pageMap['sentence_text'] ?? '',
          'chinese_translation': pageMap['chinese_translation'] ?? '',
          'audio_path': audioRemapped,
          'sentence_audio_map': remappedMapJson,
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

  /// Decodes a `{sentence: audio_relpath}` map stored as JSON in either an
  /// `sentence_audio_map` DB cell or a manifest field. Tolerant of empty /
  /// missing / malformed values — always returns a (possibly empty) Map.
  static Map<String, String> _decodeMap(String json) {
    if (json.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const <String, String>{};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } catch (_) {
      return const <String, String>{};
    }
  }
}
