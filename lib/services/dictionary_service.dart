import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../utils/word_stemmer.dart';
import 'log_service.dart';

/// One row of the bundled English→Chinese dictionary.
class DictionaryEntry {
  const DictionaryEntry({
    required this.word,
    required this.pinyin,
    required this.chinese,
    required this.definition,
    this.detail = '',
  });

  final String word; // lowercased English headword
  final String pinyin;
  final String chinese; // simplified Chinese translation(s)
  final String definition;

  /// Raw ECDICT `detail` payload — typically a JSON array of example objects,
  /// often `[{"eng": "...", "chi": "..."}]`. May be empty for entries the
  /// builder didn't import detail for.
  final String detail;

  factory DictionaryEntry.fromMap(Map<String, Object?> map) => DictionaryEntry(
        word: (map['word'] as String? ?? '').toLowerCase(),
        pinyin: map['pinyin'] as String? ?? '',
        chinese: map['chinese'] as String? ?? '',
        definition: map['definition'] as String? ?? '',
        detail: map['detail'] as String? ?? '',
      );
}

/// Opens the bundled `assets/dict/ecdict.db` once on app start. The asset is
/// copied to the app-support directory on first launch and opened read-only
/// from there — never modified, never re-fetched.
class DictionaryService {
  static const String _assetPath = 'assets/dict/ecdict.db';
  static const String _localName = 'ecdict.db';

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    try {
      final dest = await _ensureLocalCopy();
      _db = await openReadOnlyDatabase(dest.path);
    } catch (e, st) {
      // Dictionary is non-critical — log and continue without lookups.
      LogService.instance.error('DictionaryService init failed', e, st);
      _db = null;
    }
  }

  Future<File> _ensureLocalCopy() async {
    final supportDir = await getApplicationSupportDirectory();
    final dictDir = Directory(p.join(supportDir.path, 'dict'));
    if (!await dictDir.exists()) await dictDir.create(recursive: true);
    final dest = File(p.join(dictDir.path, _localName));

    final assetBytes = (await rootBundle.load(_assetPath)).buffer.asUint8List();
    final needsCopy = !await dest.exists() ||
        (await dest.length()) != assetBytes.lengthInBytes;
    if (needsCopy) {
      await dest.writeAsBytes(assetBytes, flush: true);
    }
    return dest;
  }

  bool get isReady => _db != null;

  /// Injects a database directly. For tests only — production code goes
  /// through [init].
  @visibleForTesting
  void setDatabaseForTesting(Database db) {
    _db = db;
  }

  Future<DictionaryEntry?> lookup(String word) async {
    final db = _db;
    if (db == null) return null;
    final key = word.trim().toLowerCase();
    if (key.isEmpty) return null;
    final stems = candidateStems(key);
    if (stems.isEmpty) return null;
    final placeholders = List.filled(stems.length, '?').join(',');
    // Single round trip: ask for every candidate, then return the entry that
    // matches the highest-priority stem (the order of [stems]).
    final rows = await db.query(
      'entries',
      where: 'word IN ($placeholders)',
      whereArgs: stems,
    );
    if (rows.isEmpty) return null;
    final byWord = <String, Map<String, Object?>>{
      for (final r in rows) (r['word']! as String): r,
    };
    for (final stem in stems) {
      final hit = byWord[stem];
      if (hit != null) {
        if (kDebugMode && stem != key) {
          LogService.instance.info('lookup miss for $key hit on stem $stem');
        }
        return DictionaryEntry.fromMap(hit);
      }
    }
    return null;
  }

  Future<List<DictionaryEntry>> lookupMany(Iterable<String> words) async {
    final db = _db;
    if (db == null) return const [];
    final keys = words
        .map((w) => w.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet();
    if (keys.isEmpty) return const [];
    // Walks the stemmer for each input so inflected forms hit. Returns at
    // most one entry per *input* word — duplicates (multiple inputs that
    // stem to the same headword) are de-duped by entry word.
    final out = <String, DictionaryEntry>{};
    for (final k in keys) {
      final entry = await lookup(k);
      if (entry != null) out[entry.word] = entry;
    }
    return out.values.toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
