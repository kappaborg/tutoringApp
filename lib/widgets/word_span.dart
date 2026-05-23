import 'package:flutter/material.dart';

import '../models/word_meaning.dart';
import '../utils/tokenizer.dart';

class WordSpan extends StatelessWidget {
  const WordSpan({
    super.key,
    required this.token,
    required this.meaning,
    required this.isHighlighted,
    required this.onTap,
    this.fontFamily,
    this.baseStyle,
  });

  final Token token;
  final WordMeaning? meaning;
  final bool isHighlighted;
  final VoidCallback onTap;
  final String? fontFamily;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasMeaning = meaning != null;
    final base = baseStyle ??
        Theme.of(context).textTheme.headlineSmall ??
        const TextStyle(fontSize: 22);
    final color = hasMeaning ? scheme.primary : scheme.onSurface;
    final style = base.copyWith(
      color: color,
      fontFamily: fontFamily,
      decoration: hasMeaning ? TextDecoration.underline : TextDecoration.none,
      decorationStyle: TextDecorationStyle.dotted,
      fontWeight: isHighlighted ? FontWeight.w700 : base.fontWeight,
    );
    final bg = isHighlighted ? scheme.primaryContainer : Colors.transparent;
    return Semantics(
      button: true,
      label: token.hasLetters
          ? 'Tap to read the word ${token.lookupKey}'
          : token.display,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: token.hasLetters ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(token.display, style: style),
          ),
        ),
      ),
    );
  }
}
