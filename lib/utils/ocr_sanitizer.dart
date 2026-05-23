/// Pure, side-effect-free sanitiser for OCR / PDF text-extraction output.
///
/// Real picture-book pages routinely include publisher footers, illustrated
/// signage, ISBN strings, copyright lines, page numbers, "TEACHERS:" /
/// "PARENTS:" marketing call-outs, and "BEFORE/AFTER READING" pedagogy
/// blocks. This function applies a small set of conservative regex rules to
/// strip those before they ever reach the DB, plus a stronger
/// "publisher-beacon" rule that truncates from the first publisher marker
/// onward.
///
/// If the cleaned result is empty (the page was entirely noise), we return
/// an empty string so the reader's "No text — type manually" banner takes
/// over instead of showing the noise. If sanitising would non-destructively
/// reduce the input to 1–3 characters we conservatively return the raw
/// input so a too-aggressive rule never silently swallows a real one-letter
/// sentence.
library;

/// Publisher / marketing "beacons". Everything from the earliest match
/// onward is dropped — picture books place these blocks at the END of a
/// page, never mid-story.
final _publisherBeacons = <RegExp>[
  // Teacher / parent pedagogy blocks (case-sensitive — these are typeset
  // in all caps and rarely capitalised that way in story text).
  RegExp(r'\bTEACHERS\s*:'),
  RegExp(r'\bPARENTS\s*:'),
  RegExp(r'\bBEFORE\s+READING\b'),
  RegExp(r'\bAFTER\s+READING\b'),
  // Copyright / publication metadata.
  RegExp(r'\ball\s+rights\s+reserved\b', caseSensitive: false),
  RegExp(r'\bfirst\s+published\b', caseSensitive: false),
  RegExp(r'\bedition\s+published\b', caseSensitive: false),
  RegExp(r'\bprinted\s+in\b', caseSensitive: false),
  RegExp(r'\bthe\s+country\s+of\s+origin\b', caseSensitive: false),
  // Sustainability / production blurbs.
  RegExp(r'\bpaper\s+used\s+in\s+the\s+production\b', caseSensitive: false),
  RegExp(r'\bsustainable\s+forests?\b', caseSensitive: false),
  RegExp(r'\bmanufacturing\s+process\b', caseSensitive: false),
  RegExp(r'\bphotocopying\b', caseSensitive: false),
  // Marketing taglines.
  RegExp(r'\bfor\s+inspirational\s+support\b', caseSensitive: false),
  RegExp(r"\bhelp\s+your\s+child'?s\s+reading\b", caseSensitive: false),
  RegExp(r'\bfree\s+resources?\s+and\s+e-?books?\b', caseSensitive: false),
  // Copyright lines that aren't on their own line ("Text © …", "Illus. © …").
  RegExp(
    r'\b(?:text|illustrations?|illus\.?)\s*[©Cc]\s*[A-Za-z]',
    caseSensitive: false,
  ),
];

String sanitizeOcrText(String raw) {
  if (raw.isEmpty) return raw;

  var text = raw;

  // 0. Truncate at the earliest publisher beacon (handles back-matter pages
  //    where everything from "TEACHERS:" / "AFTER READING" onward is junk).
  var beaconStart = text.length;
  for (final beacon in _publisherBeacons) {
    final m = beacon.firstMatch(text);
    if (m != null && m.start < beaconStart) {
      beaconStart = m.start;
    }
  }
  if (beaconStart < text.length) {
    text = text.substring(0, beaconStart);
  }

  // 1. Email addresses — must run BEFORE the URL rule so the domain half
  //    of an email isn't eaten as a bare hostname (leaving a stray "@").
  text = text.replaceAll(
    RegExp(r'[\w.+\-]+@[\w\-]+\.[\w.\-]+'),
    ' ',
  );

  // 2. URLs.
  text = text.replaceAll(RegExp(r'https?://\S+'), ' ');
  text = text.replaceAll(RegExp(r'www\.\S+'), ' ');
  // Bare hostnames with common TLDs (e.g. "oxfordprimary.co.uk").
  text = text.replaceAll(
    RegExp(
      r'\b[A-Za-z0-9][A-Za-z0-9\-]*\.(?:co\.uk|co\.jp|co\.kr|com|org|net|edu|gov|io|app|info|me|ai)\b',
      caseSensitive: false,
    ),
    ' ',
  );

  // 3. Phone numbers (must start + end with a digit, ≥ 8 chars inclusive).
  text = text.replaceAll(RegExp(r'\+?\d[\d\s().\-]{6,}\d'), ' ');

  // 4. ISBN-ish (10/13-digit blocks, optional ISBN prefix).
  text = text.replaceAll(
    RegExp(
      r'(?:ISBN[-\s:]*)?(?:97[89][-\s]?)?\d[\d\sX\-]{8,}\d',
      caseSensitive: false,
    ),
    ' ',
  );

  // 5 & 6. Per-line filters.
  final keptLines = <String>[];
  for (var line in text.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final lower = trimmed.toLowerCase();
    // 5. Copyright lines — drop entire line.
    if (trimmed.contains('©') ||
        lower.contains('(c)') ||
        lower.startsWith('copyright')) {
      continue;
    }
    // 6a. Lone page number — line has digits and no letters.
    final hasDigit = RegExp(r'\d').hasMatch(trimmed);
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(trimmed);
    if (hasDigit && !hasLetter) continue;
    // 6b. Trailing page number after a complete sentence:
    //     "The cat sat on the mat. 35" → drop the " 35".
    line = line.replaceFirstMapped(
      RegExp(r'([.!?…])\s+\d{1,3}\s*$'),
      (m) => m.group(1)!,
    );
    // 6c. Trailing bare number with no leading punctuation but at the end:
    //     "The cat sat 35" → drop the " 35". Only if there are at least two
    //     letter-tokens before it (so "I have 3" is preserved as content).
    final trailingMatch =
        RegExp(r'(.+?)\s+(\d{1,3})\s*$').firstMatch(line);
    if (trailingMatch != null) {
      final before = trailingMatch.group(1)!;
      final letterTokens = RegExp(r'[A-Za-z][A-Za-z]+')
          .allMatches(before)
          .length;
      if (letterTokens >= 2) {
        line = before;
      }
    }
    // 6d. Leading page number followed by a capitalised sentence:
    //     "35 The cat sat..." → drop the "35 ".
    line = line.replaceFirstMapped(
      RegExp(r'^\s*\d{1,3}\s+([A-Z])'),
      (m) => m.group(1)!,
    );
    if (line.trim().isEmpty) continue;
    keptLines.add(line);
  }
  text = keptLines.join('\n');

  // 7. Shouty-junk clusters: ≥ 2 consecutive ALL-CAPS tokens NOT followed
  //    by a sentence terminator.
  text = text.split('\n').map(_removeShoutyClusters).join('\n');

  // 8. OCR garbage tokens (length ≥ 3, alpha:digit ratio < 0.4).
  text = text.split('\n').map(_removeGarbageTokens).join('\n');

  // 9. Whitespace normalisation.
  final norm = text
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .join('\n');

  // Guard policy:
  //   • norm empty   → page was entirely publisher noise. Return "" so the
  //                    reader / review screen treats it as no-text.
  //   • norm 1–3 chr → a rule was too aggressive. Return raw defensively.
  //   • otherwise    → return the cleaned text.
  final trimmed = norm.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.length < 4) return raw;
  return norm;
}

final _shoutyCore = RegExp(r"^[A-Z0-9'\-]{2,}$");
final _shoutyEnd = RegExp(r"^[A-Z0-9'\-]{2,}[.!?]$");

String _removeShoutyClusters(String line) {
  final tokens = line.split(RegExp(r' +'));
  final out = <String>[];
  var i = 0;
  while (i < tokens.length) {
    final tok = tokens[i];
    if (_shoutyCore.hasMatch(tok)) {
      var j = i;
      var endedWithTerminator = false;
      while (j < tokens.length) {
        if (_shoutyCore.hasMatch(tokens[j])) {
          j++;
        } else if (_shoutyEnd.hasMatch(tokens[j])) {
          j++;
          endedWithTerminator = true;
          break;
        } else {
          break;
        }
      }
      if (j - i >= 2 && !endedWithTerminator) {
        // Only spare the cluster if the very next token starts with a
        // sentence terminator (rare; conservative).
        var keep = false;
        if (j < tokens.length) {
          final next = tokens[j];
          if (next.startsWith('.') ||
              next.startsWith('!') ||
              next.startsWith('?')) {
            keep = true;
          }
        }
        if (!keep) {
          i = j;
          continue;
        }
      }
    }
    out.add(tok);
    i++;
  }
  return out.where((t) => t.isNotEmpty).join(' ');
}

String _removeGarbageTokens(String line) {
  final tokens = line.split(RegExp(r' +'));
  final out = <String>[];
  for (final tok in tokens) {
    if (tok.isEmpty) continue;
    if (tok.length < 3) {
      out.add(tok);
      continue;
    }
    final letters = RegExp(r'[A-Za-z]').allMatches(tok).length;
    final digits = RegExp(r'[0-9]').allMatches(tok).length;
    final total = letters + digits;
    if (total == 0) {
      out.add(tok);
      continue;
    }
    final ratio = letters / total;
    if (ratio < 0.4) continue;
    out.add(tok);
  }
  return out.join(' ');
}
