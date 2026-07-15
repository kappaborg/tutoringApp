import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sql;

import '../db/db_helper.dart';
import 'log_service.dart';

class BackupSummary {
  const BackupSummary({
    required this.schemaVersion,
    required this.bookCount,
    required this.pageCount,
    required this.imageCount,
  });
  final int schemaVersion;
  final int bookCount;
  final int pageCount;
  final int imageCount;
}

class BackupService {
  BackupService({DbHelper? dbHelper}) : _dbHelper = dbHelper ?? DbHelper.instance;
  final DbHelper _dbHelper;

  static const int _schemaVersion = 3;

  /// Older backups are still importable — the onUpgrade migration runs on
  /// next openDatabase to bring them up to the current schema.
  static const Set<int> _acceptableImportVersions = {1, 2, 3};

  static const String _manifestName = 'manifest.json';
  static const String _dbName = 'picturebook.db';

  /// Exports DB + images to a ZIP at [destinationPath]. Returns the file.
  Future<File> exportToZip(String destinationPath) async {
    final support = await getApplicationSupportDirectory();
    final docs = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(support.path, _dbName));
    final imagesDir = Directory(p.join(docs.path, 'images'));

    final archive = Archive();

    if (await dbFile.exists()) {
      final bytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile(_dbName, bytes.length, bytes));
    }

    var imageCount = 0;
    if (await imagesDir.exists()) {
      await for (final entity in imagesDir.list()) {
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          archive.addFile(
            ArchiveFile('images/${p.basename(entity.path)}', bytes.length, bytes),
          );
          imageCount++;
        }
      }
    }

    final manifest = jsonEncode(<String, Object?>{
      'schema_version': _schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'image_count': imageCount,
    });
    final manifestBytes = utf8.encode(manifest);
    archive.addFile(ArchiveFile(_manifestName, manifestBytes.length, manifestBytes));

    final encoded = ZipEncoder().encode(archive);
    final dest = File(destinationPath);
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(encoded, flush: true);
    LogService.instance.info('Exported backup to $destinationPath');
    return dest;
  }

  /// Inspects a backup ZIP without applying it, for the pre-import diff.
  Future<BackupSummary> previewZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest = _readManifest(archive);
    var images = 0;
    var hasDb = false;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name == _dbName) hasDb = true;
      if (f.name.startsWith('images/')) images++;
    }
    if (!hasDb) {
      throw const FormatException('Backup is missing picturebook.db');
    }
    return BackupSummary(
      schemaVersion: manifest['schema_version'] as int? ?? -1,
      bookCount: -1, // unknown until applied
      pageCount: -1,
      imageCount: images,
    );
  }

  /// Reads a backup ZIP, validates manifest, and atomically replaces the local
  /// state. Returns a summary computed from the imported archive.
  Future<BackupSummary> importFromZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifest = _readManifest(archive);
    final schemaVersion = manifest['schema_version'] as int? ?? -1;
    if (!_acceptableImportVersions.contains(schemaVersion)) {
      throw FormatException(
        'Backup schema version $schemaVersion is not supported '
        '(expected one of $_acceptableImportVersions).',
      );
    }

    final tmp = await Directory.systemTemp.createTemp('picturebook_restore_');
    try {
      File? stagedDb;
      final stagedImages = <File>[];
      for (final file in archive.files) {
        if (!file.isFile) continue;
        if (file.name == _manifestName) continue;
        final dest = File(p.join(tmp.path, file.name));
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(file.content as List<int>, flush: true);
        if (file.name == _dbName) {
          stagedDb = dest;
        } else if (file.name.startsWith('images/')) {
          stagedImages.add(dest);
        }
      }
      if (stagedDb == null) {
        throw const FormatException('Backup is missing picturebook.db');
      }

      await _dbHelper.replaceDbFile(stagedDb);

      final docs = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(docs.path, 'images'));
      if (await imagesDir.exists()) {
        await for (final entity in imagesDir.list()) {
          if (entity is File) await entity.delete();
        }
      } else {
        await imagesDir.create(recursive: true);
      }
      for (final f in stagedImages) {
        final dest = File(p.join(imagesDir.path, p.basename(f.path)));
        await f.copy(dest.path);
      }

      final db = await _dbHelper.database;
      final books =
          sql.Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM books')) ?? 0;
      final pages =
          sql.Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM pages')) ?? 0;
      LogService.instance.info('Restored backup from $zipPath');
      return BackupSummary(
        schemaVersion: schemaVersion,
        bookCount: books,
        pageCount: pages,
        imageCount: stagedImages.length,
      );
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  Map<String, Object?> _readManifest(Archive archive) {
    final entry = archive.findFile(_manifestName);
    if (entry == null) {
      throw const FormatException('Backup is missing manifest.json');
    }
    return jsonDecode(utf8.decode(entry.content as List<int>)) as Map<String, Object?>;
  }
}
