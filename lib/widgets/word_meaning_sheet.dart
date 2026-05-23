import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/word_meaning.dart';
import '../services/dictionary_service.dart';
import '../services/word_examples_service.dart';

/// Rich word-detail sheet. Sections, in order:
///
/// 1. Header        — word + speak button.
/// 2. Translation   — curated or dictionary fallback.
/// 3. From your books — up to 3 cross-book sentences (tappable, jumps reader).
/// 4. More examples — up to 3 ECDICT example sentences.
/// 5. Footer        — Save-to-page (auto-translated), Edit (Teacher mode).
class WordMeaningSheet extends StatelessWidget {
  const WordMeaningSheet({
    super.key,
    required this.word,
    required this.meaning,
    required this.examplesFuture,
    required this.onSpeak,
    this.onEdit,
    this.dictionaryEntry,
    this.onSaveDictionaryEntry,
    this.onOpenExample,
    this.fontFamily,
  });

  final String word;
  final WordMeaning? meaning;
  final Future<List<WordExample>> examplesFuture;
  final VoidCallback onSpeak;
  final VoidCallback? onEdit;
  final DictionaryEntry? dictionaryEntry;
  final VoidCallback? onSaveDictionaryEntry;
  final void Function(WordExample example)? onOpenExample;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final isCurated = meaning != null;
    final isFallback = !isCurated && dictionaryEntry != null;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      word,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFamily: fontFamily,
                      ),
                    ),
                  ),
                  if (isFallback) const _AutoChip(),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: onSpeak,
                    icon: const Icon(Icons.volume_up),
                    tooltip: t.speakWord,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. Translation
              _TranslationCard(
                meaning: meaning,
                dictionaryEntry: dictionaryEntry,
                fontFamily: fontFamily,
              ),

              // 3. Examples (lazy)
              FutureBuilder<List<WordExample>>(
                future: examplesFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final examples = snap.data ?? const <WordExample>[];
                  if (examples.isEmpty) return const SizedBox.shrink();
                  final corpus =
                      examples.where((e) => e.isFromBookCorpus).toList();
                  final dict =
                      examples.where((e) => e.isFromDictionary).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (corpus.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const _SectionLabel('From your books'),
                        const SizedBox(height: 6),
                        for (final ex in corpus)
                          _BookExampleCard(
                            example: ex,
                            highlight: word,
                            onTap: onOpenExample,
                            fontFamily: fontFamily,
                          ),
                      ],
                      if (dict.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const _SectionLabel('More examples'),
                        const SizedBox(height: 6),
                        for (final ex in dict)
                          _DictionaryExampleCard(
                            example: ex,
                            highlight: word,
                            fontFamily: fontFamily,
                          ),
                      ],
                    ],
                  );
                },
              ),

              // 5. Footer actions
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onEdit != null)
                    OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit),
                      label: Text(t.edit),
                    ),
                  if (isFallback && onSaveDictionaryEntry != null)
                    OutlinedButton.icon(
                      onPressed: onSaveDictionaryEntry,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Save to this page'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({
    required this.meaning,
    required this.dictionaryEntry,
    required this.fontFamily,
  });
  final WordMeaning? meaning;
  final DictionaryEntry? dictionaryEntry;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    final card = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _rows(t, theme),
        ),
      ),
    );
    return card;
  }

  List<Widget> _rows(AppStrings t, ThemeData theme) {
    final m = meaning;
    final d = dictionaryEntry;
    final rows = <Widget>[];
    if (m != null) {
      rows.add(_Line(label: t.chineseMeaning, value: m.chineseMeaning, fontFamily: fontFamily));
      rows.add(const SizedBox(height: 6));
      rows.add(_Line(label: t.englishDefinition, value: m.englishDefinition, fontFamily: fontFamily));
    } else if (d != null) {
      if (d.pinyin.isNotEmpty) {
        rows.add(_Line(label: 'Pinyin', value: d.pinyin, fontFamily: fontFamily));
        rows.add(const SizedBox(height: 6));
      }
      if (d.chinese.isNotEmpty) {
        rows.add(_Line(label: t.chineseMeaning, value: d.chinese, fontFamily: fontFamily));
      }
      if (d.definition.isNotEmpty) {
        rows.add(const SizedBox(height: 6));
        rows.add(_Line(label: t.englishDefinition, value: d.definition, fontFamily: fontFamily));
      }
    } else {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(t.noMeaningRecorded, style: theme.textTheme.bodyLarge),
        ),
      );
    }
    return rows;
  }
}

class _AutoChip extends StatelessWidget {
  const _AutoChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'auto-translated',
        style: TextStyle(
          color: scheme.onTertiaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.1,
          ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.fontFamily});
  final String label;
  final String value;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(fontFamily: fontFamily),
          ),
        ),
      ],
    );
  }
}

class _BookExampleCard extends StatelessWidget {
  const _BookExampleCard({
    required this.example,
    required this.highlight,
    required this.onTap,
    required this.fontFamily,
  });
  final WordExample example;
  final String highlight;
  final void Function(WordExample)? onTap;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label =
        '${example.bookTitle ?? "Book"} · Page ${example.pageNumber ?? "?"}';
    final tappable = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: tappable ? () => onTap!(example) : null,
          borderRadius: BorderRadius.circular(10),
          child: Semantics(
            button: tappable,
            label: 'Example from $label',
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      if (tappable)
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _HighlightedSentence(
                    sentence: example.sentence,
                    highlight: highlight,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFamily: fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DictionaryExampleCard extends StatelessWidget {
  const _DictionaryExampleCard({
    required this.example,
    required this.highlight,
    required this.fontFamily,
  });
  final WordExample example;
  final String highlight;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        child: Semantics(
          label: 'Dictionary example',
          child: _HighlightedSentence(
            sentence: example.sentence,
            highlight: highlight,
            style: theme.textTheme.bodyMedium?.copyWith(fontFamily: fontFamily),
          ),
        ),
      ),
    );
  }
}

/// Bolds + underlines every case-insensitive occurrence of [highlight] in
/// [sentence]. Falls back to a plain Text when [highlight] is empty.
class _HighlightedSentence extends StatelessWidget {
  const _HighlightedSentence({
    required this.sentence,
    required this.highlight,
    required this.style,
  });
  final String sentence;
  final String highlight;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (highlight.isEmpty) return Text(sentence, style: style);
    final lower = sentence.toLowerCase();
    final needle = highlight.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (i < sentence.length) {
      final found = lower.indexOf(needle, i);
      if (found < 0) {
        spans.add(TextSpan(text: sentence.substring(i), style: style));
        break;
      }
      // Only treat as a word-boundary match to avoid highlighting "cat" inside "scatter".
      final beforeOk = found == 0 || !_isWordChar(sentence[found - 1]);
      final afterIdx = found + needle.length;
      final afterOk =
          afterIdx >= sentence.length || !_isWordChar(sentence[afterIdx]);
      if (!beforeOk || !afterOk) {
        spans.add(
          TextSpan(
            text: sentence.substring(i, found + 1),
            style: style,
          ),
        );
        i = found + 1;
        continue;
      }
      if (found > i) {
        spans.add(TextSpan(text: sentence.substring(i, found), style: style));
      }
      spans.add(
        TextSpan(
          text: sentence.substring(found, afterIdx),
          style: (style ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            color: scheme.primary,
          ),
        ),
      );
      i = afterIdx;
    }
    return RichText(text: TextSpan(children: spans));
  }

  bool _isWordChar(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    final isLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
    final isDigit = c >= 0x30 && c <= 0x39;
    return isLetter || isDigit || ch == "'" || ch == '’';
  }
}
