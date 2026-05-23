import 'dart:convert';

import '../db/db_helper.dart';
import 'dictionary_service.dart';
import 'log_service.dart';

enum WordExampleSource { bookCorpus, dictionary }

/// A single usage example surfaced when a child taps a word.
class WordExample {
  const WordExample({
    required this.sentence,
    required this.source,
    this.bookId,
    this.bookTitle,
    this.pageId,
    this.pageNumber,
  });

  /// The example sentence in its original language. For `bookCorpus`, this is
  /// the page's English sentence as the teacher saved it. For `dictionary`,
  /// it's the English example from ECDICT's `detail` payload.
  final String sentence;
  final WordExampleSource source;
  final int? bookId;
  final String? bookTitle;
  final int? pageId;
  final int? pageNumber;

  bool get isFromBookCorpus => source == WordExampleSource.bookCorpus;
  bool get isFromDictionary => source == WordExampleSource.dictionary;
}

/// Finds example sentences that use a given word, both from the user's own
/// books and from the bundled ECDICT detail payload.
class WordExamplesService {
  WordExamplesService({
    DbHelper? dbHelper,
    DictionaryService? dictionary,
  })  : _dbHelper = dbHelper ?? DbHelper.instance,
        _dictionary = dictionary;

  final DbHelper _dbHelper;
  final DictionaryService? _dictionary;

  /// Returns up to [bookLimit] examples from other pages plus up to [dictLimit]
  /// examples from the bundled dictionary. Pages with `id == excludePageId`
  /// are filtered out (so a child doesn't see the same page they just tapped).
  Future<List<WordExample>> findExamples(
    String word, {
    int? excludePageId,
    int bookLimit = 3,
    int dictLimit = 3,
  }) async {
    final key = word.trim().toLowerCase();
    if (key.isEmpty) return const [];

    final corpus = await _findFromBookCorpus(
      key,
      excludePageId: excludePageId,
      limit: bookLimit,
    );
    final dict = await _findFromDictionary(key, limit: dictLimit);
    return [...corpus, ...dict];
  }

  Future<List<WordExample>> _findFromBookCorpus(
    String key, {
    int? excludePageId,
    required int limit,
  }) async {
    try {
      final db = await _dbHelper.database;
      final exclusion = excludePageId != null ? 'AND p.id != ?' : '';
      final args = <Object?>[key];
      if (excludePageId != null) args.add(excludePageId);
      args.add(limit);
      final rows = await db.rawQuery(
        '''
        SELECT b.id   AS book_id,
               b.title AS book_title,
               p.id    AS page_id,
               p.page_number AS page_number,
               p.sentence_text AS sentence_text
        FROM word_meanings w
        JOIN pages p ON p.id = w.page_id
        JOIN books b ON b.id = p.book_id
        WHERE w.word = ? $exclusion
        ORDER BY b.updated_at DESC, p.page_number ASC
        LIMIT ?
        ''',
        args,
      );
      return rows
          .map(
            (r) => WordExample(
              sentence: r['sentence_text']! as String,
              source: WordExampleSource.bookCorpus,
              bookId: r['book_id'] as int?,
              bookTitle: r['book_title'] as String?,
              pageId: r['page_id'] as int?,
              pageNumber: r['page_number'] as int?,
            ),
          )
          .toList();
    } catch (e, st) {
      LogService.instance.error('Find book examples failed', e, st);
      return const [];
    }
  }

  Future<List<WordExample>> _findFromDictionary(
    String key, {
    required int limit,
  }) async {
    final dict = _dictionary;
    if (dict == null) return const [];
    final entry = await dict.lookup(key);
    if (entry == null || entry.detail.isEmpty) return const [];
    final parsed = _parseDetailExamples(entry.detail);
    return parsed
        .take(limit)
        .map(
          (s) => WordExample(
            sentence: s,
            source: WordExampleSource.dictionary,
          ),
        )
        .toList();
  }

  /// ECDICT's `detail` is community-maintained and shows up in several shapes:
  ///   - JSON array of `{eng, chi}` objects
  ///   - JSON array of `{en, zh}` objects
  ///   - JSON array of bare strings
  /// We accept any of these. On parse error we return an empty list — a
  /// broken detail payload should never crash the word-tap UX.
  List<String> _parseDetailExamples(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final data = jsonDecode(trimmed);
      if (data is List) {
        return data
            .map(_stringFromExample)
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Some sources stuff plain-text bullet lists into detail; fall through.
    }
    final lines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines;
  }

  String _stringFromExample(Object? item) {
    if (item is String) return item.trim();
    if (item is Map) {
      for (final key in ['eng', 'english', 'en', 'sentence', 'text']) {
        final v = item[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }
}
