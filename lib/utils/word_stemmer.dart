/// Suffix-stripping fallback used by [DictionaryService.lookup].
///
/// Given an inflected English word, [candidateStems] returns the original
/// plus a deterministic list of candidate stems to try against a
/// fixed-vocabulary dictionary. The caller walks the list and uses the
/// first hit.
///
/// Rules deliberately stay simple — no Porter stemmer, no Lancaster. The
/// goal is good coverage for picture-book vocabulary (cats/days/playing/
/// stopped/berries/bigger), not linguistic completeness.
library;

/// Returns the search order for stems of [word]. The first element is the
/// original (lowercased) word. Empty / single-char results are filtered out.
List<String> candidateStems(String word) {
  final w = word.trim().toLowerCase();
  if (w.length < 2) return const [];
  final seen = <String>{};
  final out = <String>[];
  void add(String s) {
    if (s.length >= 2 && seen.add(s)) out.add(s);
  }

  // 1. as-is
  add(w);

  // 2. strip 's / ’s
  if (w.endsWith("'s") || w.endsWith('’s')) {
    add(w.substring(0, w.length - 2));
  }

  // 3. strip trailing s (but not double-s endings — pass/grass etc.)
  if (w.endsWith('s') && !w.endsWith('ss')) {
    add(w.substring(0, w.length - 1));
  }

  // 4. strip es
  if (w.endsWith('es')) {
    add(w.substring(0, w.length - 2));
  }

  // 5. strip ies → y
  if (w.endsWith('ies') && w.length >= 4) {
    add('${w.substring(0, w.length - 3)}y');
  }

  // 6. strip ed
  if (w.endsWith('ed') && w.length >= 4) {
    final base = w.substring(0, w.length - 2);
    add(base);
    // 10a. de-double final consonant: stopped → stop
    if (base.length >= 3 &&
        base[base.length - 1] == base[base.length - 2] &&
        _isConsonant(base[base.length - 1])) {
      add(base.substring(0, base.length - 1));
    }
  }

  // 7. strip ied → y
  if (w.endsWith('ied') && w.length >= 4) {
    add('${w.substring(0, w.length - 3)}y');
  }

  // 8 + 9. strip ing (also try +e: making → make)
  if (w.endsWith('ing') && w.length >= 4) {
    final base = w.substring(0, w.length - 3);
    add(base);
    add('${base}e');
    // 10b. de-double final consonant: running → run
    if (base.length >= 3 &&
        base[base.length - 1] == base[base.length - 2] &&
        _isConsonant(base[base.length - 1])) {
      add(base.substring(0, base.length - 1));
    }
  }

  // 11. strip er / est (also de-double: bigger → big, biggest → big)
  if (w.endsWith('er') && w.length >= 4) {
    final base = w.substring(0, w.length - 2);
    add(base);
    if (base.length >= 3 &&
        base[base.length - 1] == base[base.length - 2] &&
        _isConsonant(base[base.length - 1])) {
      add(base.substring(0, base.length - 1));
    }
  }
  if (w.endsWith('est') && w.length >= 5) {
    final base = w.substring(0, w.length - 3);
    add(base);
    if (base.length >= 3 &&
        base[base.length - 1] == base[base.length - 2] &&
        _isConsonant(base[base.length - 1])) {
      add(base.substring(0, base.length - 1));
    }
  }

  return out;
}

bool _isConsonant(String ch) {
  if (ch.isEmpty) return false;
  final c = ch.toLowerCase();
  return !'aeiou'.contains(c) && RegExp(r'[a-z]').hasMatch(c);
}
