/// A single visible chunk of a sentence: the original characters and the
/// lowercased alphabetic core used for dictionary lookup.
class Token {
  const Token({
    required this.display,
    required this.lookupKey,
    required this.charStart,
    required this.charEnd,
  });

  /// Characters as they appear in the sentence (e.g. "Hello,").
  final String display;

  /// Lowercased core used for `word_meanings.word` lookup (e.g. "hello").
  /// Empty when the chunk contains no letters (pure punctuation).
  final String lookupKey;

  /// Inclusive start index of the chunk in the source sentence.
  final int charStart;

  /// Exclusive end index of the chunk in the source sentence.
  final int charEnd;

  bool get hasLetters => lookupKey.isNotEmpty;
}

/// Splits a sentence into [Token]s for tappable rendering. The regex captures
/// Unicode letters and combining marks plus the trailing punctuation/whitespace
/// so that each token stays visually intact while the lookup key is the
/// lowercased letter-only core. Handles smart quotes, em-dashes, accented
/// characters.
class Tokenizer {
  // Letter clusters OR digit-only clusters. We don't combine letters + digits
  // into a single word (so "Anna3" splits) — that prevents OCR garbage like
  // "Garden2I313" from masquerading as a single tappable token.
  static final RegExp _word =
      RegExp(r"[\p{L}\p{M}’']+|\d+", unicode: true);

  static List<Token> tokenize(String sentence) {
    if (sentence.isEmpty) return const <Token>[];
    final tokens = <Token>[];
    final chunks = sentence.split(RegExp(r'\s+'));
    var cursor = 0;
    for (final chunk in chunks) {
      if (chunk.isEmpty) continue;
      final start = sentence.indexOf(chunk, cursor);
      if (start < 0) continue;
      cursor = start + chunk.length;
      final match = _word.firstMatch(chunk);
      final lookup = (match?.group(0) ?? '').toLowerCase().replaceAll('’', "'");
      tokens.add(
        Token(
          display: chunk,
          lookupKey: lookup,
          charStart: start,
          charEnd: start + chunk.length,
        ),
      );
    }
    return tokens;
  }

  /// Returns the de-duplicated lowercase word keys present in [sentence].
  static List<String> uniqueWords(String sentence) {
    final seen = <String>{};
    final out = <String>[];
    for (final t in tokenize(sentence)) {
      if (t.hasLetters && seen.add(t.lookupKey)) out.add(t.lookupKey);
    }
    return out;
  }
}
