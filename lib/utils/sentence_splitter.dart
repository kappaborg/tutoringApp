/// Splits a paragraph of mixed-language text into individual sentences.
///
/// Used by Sentence Mode in the reader so kids can tap one sentence at a
/// time. Pure, no I/O. CJK-aware. Guards against common false splits:
///   • abbreviations (Mr., Dr., e.g.)
///   • initials (J. K. Rowling)
///   • decimals (3.50)
library;

const _abbreviations = <String>{
  'mr', 'mrs', 'ms', 'dr', 'st', 'jr', 'sr',
  'vs', 'etc', 'e.g', 'i.e', 'mt', 'no', 'fig',
};

const _terminators = {'.', '?', '!', '…', '。', '？', '！'};

List<String> splitIntoSentences(String text) {
  if (text.trim().isEmpty) return const [];

  // 1. Normalise whitespace.
  var s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 2. Strip space immediately before a terminator: "Foo ." → "Foo.".
  s = s.replaceAllMapped(
    RegExp(r' +([.!?…。？！])'),
    (m) => m.group(1)!,
  );

  final out = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    buf.write(c);
    if (!_terminators.contains(c)) continue;

    // Suppress split for ASCII '.'.
    if (c == '.') {
      // Decimal: next char is a digit.
      if (i + 1 < s.length && RegExp(r'\d').hasMatch(s[i + 1])) {
        continue;
      }
      // Initial or abbreviation: look back at the token before the dot.
      final preTrim = buf.toString();
      final preWithoutDot = preTrim.substring(0, preTrim.length - 1);
      final m = RegExp(r'(\S+)$').firstMatch(preWithoutDot);
      if (m != null) {
        final tok = m.group(0)!;
        // Single uppercase letter → initial.
        if (tok.length == 1 && RegExp(r'^[A-Z]$').hasMatch(tok)) continue;
        if (_abbreviations.contains(tok.toLowerCase())) continue;
      }
    }

    final segment = buf.toString().trim();
    if (segment.isNotEmpty) out.add(segment);
    buf.clear();
  }
  final tail = buf.toString().trim();
  if (tail.isNotEmpty) out.add(tail);
  if (out.isEmpty) return [s];
  return out;
}
