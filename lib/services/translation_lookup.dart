import 'dart:async';
import 'dart:collection';

import '../utils/tokenizer.dart';
import 'dictionary_service.dart';

/// Thin convenience layer around [DictionaryService] used by both the page
/// editor (auto-fill from dictionary) and the reader (fallback when no curated
/// entry exists). Keeps lookup logic in one place so caching can grow here.
class TranslationLookup {
  TranslationLookup(this._dict);
  final DictionaryService _dict;

  final Map<String, DictionaryEntry?> _cache = <String, DictionaryEntry?>{};

  // LRU for whole-sentence translations. Bounded to 256 entries — sentences
  // repeat across pages and across re-opens of the translation sheet, but we
  // don't want unbounded growth on a long session.
  static const int _sentenceCacheCap = 256;
  final LinkedHashMap<String, String> _sentenceCache = LinkedHashMap();

  Future<DictionaryEntry?> resolve(String key) async {
    final normalized = key.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (_cache.containsKey(normalized)) return _cache[normalized];
    final entry = await _dict.lookup(normalized);
    _cache[normalized] = entry;
    return entry;
  }

  Future<Map<String, DictionaryEntry>> resolveMany(Set<String> keys) async {
    final out = <String, DictionaryEntry>{};
    final missing = <String>{};
    for (final k in keys) {
      final n = k.trim().toLowerCase();
      if (n.isEmpty) continue;
      if (_cache.containsKey(n)) {
        final hit = _cache[n];
        if (hit != null) out[n] = hit;
      } else {
        missing.add(n);
      }
    }
    if (missing.isNotEmpty) {
      final fresh = await _dict.lookupMany(missing);
      final freshByKey = <String, DictionaryEntry>{
        for (final e in fresh) e.word: e,
      };
      for (final k in missing) {
        final hit = freshByKey[k];
        _cache[k] = hit;
        if (hit != null) out[k] = hit;
      }
    }
    return out;
  }

  void clearCache() {
    _cache.clear();
    _sentenceCache.clear();
  }

  /// Returns a literal-join Chinese rendering of one sentence. Unknown
  /// tokens are passed through unchanged. If more than half of the
  /// dictionary-eligible tokens miss, returns an empty string so the
  /// caller can show a "no translation" state instead of a useless mix.
  ///
  /// Results are cached in an LRU keyed by the exact sentence string.
  Future<String> chineseForSentence(String sentence) async {
    final cached = _sentenceCache.remove(sentence);
    if (cached != null) {
      _sentenceCache[sentence] = cached; // move-to-end (LRU)
      return cached;
    }
    final tokens = Tokenizer.tokenize(sentence);
    final wordTokens = tokens.where((t) => t.hasLetters).toList();
    if (wordTokens.isEmpty) {
      _putSentence(sentence, '');
      return '';
    }
    var hits = 0;
    final parts = <String>[];
    var anyCjk = false;
    for (final t in tokens) {
      if (!t.hasLetters) continue; // skip pure-punct tokens for translation
      final entry = await _dict.lookup(t.lookupKey);
      if (entry != null && entry.chinese.isNotEmpty) {
        hits++;
        final gloss = _firstGloss(entry.chinese);
        parts.add(gloss);
        if (_containsCjk(gloss)) anyCjk = true;
      } else {
        parts.add(t.display);
      }
    }
    if (hits / wordTokens.length < 0.5) {
      _putSentence(sentence, '');
      return '';
    }
    final separator = anyCjk ? '' : ' ';
    final result = parts.join(separator);
    _putSentence(sentence, result);
    return result;
  }

  void _putSentence(String key, String value) {
    _sentenceCache.remove(key);
    _sentenceCache[key] = value;
    while (_sentenceCache.length > _sentenceCacheCap) {
      _sentenceCache.remove(_sentenceCache.keys.first);
    }
  }

  bool _containsCjk(String s) {
    for (final r in s.runes) {
      if ((r >= 0x4E00 && r <= 0x9FFF) ||
          (r >= 0x3400 && r <= 0x4DBF) ||
          (r >= 0x20000 && r <= 0x2A6DF)) {
        return true;
      }
    }
    return false;
  }

  /// Produces a placeholder Chinese rendering of [sentence] by replacing each
  /// known English word with its top Chinese gloss and leaving unknown words
  /// untouched. This is NOT real machine translation — it's a literal join
  /// the teacher refines later. Returns `null` when fewer than [minCoverage]
  /// of the alphabetic tokens are present in the dictionary (a low-quality
  /// guess is worse than no guess).
  Future<String?> concatenateChineseFromWords(
    String sentence, {
    double minCoverage = 0.5,
  }) async {
    final keys = Tokenizer.uniqueWords(sentence).toSet();
    if (keys.isEmpty) return null;
    final hits = await resolveMany(keys);
    if (hits.length / keys.length < minCoverage) return null;

    final tokens = Tokenizer.tokenize(sentence);
    final out = StringBuffer();
    var firstWord = true;
    for (final t in tokens) {
      final entry = hits[t.lookupKey];
      if (!firstWord) out.write(' ');
      firstWord = false;
      if (entry != null && entry.chinese.isNotEmpty) {
        out.write(_firstGloss(entry.chinese));
      } else {
        out.write(t.display);
      }
    }
    return out.toString().trim();
  }

  /// Many ECDICT entries pack multiple translations into one cell separated
  /// by `;` `,` or newlines. For a literal join we only want the first one.
  String _firstGloss(String chinese) {
    final cleaned = chinese.replaceAll(RegExp(r'\\n'), '\n');
    for (final sep in const ['\n', ';', '；', ',', '，']) {
      final i = cleaned.indexOf(sep);
      if (i > 0) return cleaned.substring(0, i).trim();
    }
    return cleaned.trim();
  }
}
