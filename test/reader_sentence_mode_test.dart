import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picture_book/utils/sentence_splitter.dart';

/// Pure widget-shape test that mirrors what the reader's Sentence Mode
/// renders for a multi-sentence page. We can't easily pump the real
/// ReaderScreen here because it depends on flutter_tts and other platform
/// plugins, so we verify the contract:
///
/// 1. A 3-sentence page produces exactly 3 sentence cards.
/// 2. Tapping a specific card surfaces exactly that sentence to the
///    callback.
///
/// This is the same contract `reader_screen.dart::_SentenceArea` relies on.
void main() {
  testWidgets('three sentences → three cards; tap reports correct sentence',
      (tester) async {
    const pageText =
        'The cat sat on the mat. A dog ran past. The sun was bright today.';
    final sentences = splitIntoSentences(pageText);
    expect(sentences.length, 3);

    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in sentences)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: InkWell(
                      onTap: () => tapped = s,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(s),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Three cards rendered.
    expect(find.text(sentences[0]), findsOneWidget);
    expect(find.text(sentences[1]), findsOneWidget);
    expect(find.text(sentences[2]), findsOneWidget);

    // Tap the second card → callback receives the second sentence.
    await tester.tap(find.text(sentences[1]));
    expect(tapped, sentences[1]);
  });
}
