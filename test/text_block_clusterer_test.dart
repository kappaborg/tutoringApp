import 'package:flutter_test/flutter_test.dart';
import 'package:picture_book/utils/text_block_clusterer.dart';

OcrObservation o({
  required String text,
  required double y,
  double x = 0.1,
  double width = 0.8,
  double height = 0.04,
  double confidence = 0.95,
}) {
  return OcrObservation(
    text: text,
    x: x,
    y: y,
    width: width,
    height: height,
    confidence: confidence,
  );
}

void main() {
  group('pickMainParagraph', () {
    test('returns input unchanged when there are 0–2 observations', () {
      final input = [
        o(text: 'Hello', y: 0.1),
        o(text: 'World', y: 0.2),
      ];
      expect(pickMainParagraph(input), input);
    });

    test('drops scattered illustration labels and keeps the story block', () {
      // Simulated picture-book page (top-left origin):
      // y = 0.05  → "Chocolate" (label inside drawing, small width)
      // y = 0.20  → "Net weight" (label inside drawing)
      // y = 0.32  → "Beans"      (label inside drawing)
      // y = 0.70  → "Wilf came to play with Chip. They made"  (story)
      // y = 0.75  → "a rocket ship out of bits and pieces."   (story)
      // y = 0.80  → "The rocket ship looked quite good."      (story)
      final input = [
        o(text: 'Chocolate', y: 0.05, x: 0.45, width: 0.12, height: 0.02),
        o(text: 'Net weight', y: 0.20, x: 0.50, width: 0.10, height: 0.02),
        o(text: 'Beans', y: 0.32, x: 0.55, width: 0.08, height: 0.02),
        o(
          text: 'Wilf came to play with Chip. They made',
          y: 0.70,
          width: 0.85,
          height: 0.035,
        ),
        o(
          text: 'a rocket ship out of bits and pieces.',
          y: 0.75,
          width: 0.85,
          height: 0.035,
        ),
        o(
          text: 'The rocket ship looked quite good.',
          y: 0.80,
          width: 0.85,
          height: 0.035,
        ),
      ];
      final picked = pickMainParagraph(input);
      final joined = picked.map((p) => p.text).join(' ');
      expect(joined, contains('Wilf came to play'));
      expect(joined, contains('rocket ship'));
      expect(joined, isNot(contains('Chocolate')));
      expect(joined, isNot(contains('Net weight')));
      expect(joined, isNot(contains('Beans')));
    });

    test('keeps everything when no single cluster dominates the page', () {
      // Two small clusters of equal size → neither passes the area-share
      // gate; the function falls back to returning all observations.
      final input = [
        o(text: 'A', y: 0.10, height: 0.03, width: 0.10),
        o(text: 'B', y: 0.13, height: 0.03, width: 0.10),
        o(text: 'C', y: 0.70, height: 0.03, width: 0.10),
        o(text: 'D', y: 0.73, height: 0.03, width: 0.10),
      ];
      final picked = pickMainParagraph(input);
      expect(picked.length, 4);
    });
  });

  group('observationsToText', () {
    test('joins observations in the same visual line with spaces', () {
      final input = [
        o(text: 'Wilf', y: 0.70, x: 0.10, width: 0.10),
        o(text: 'came', y: 0.70, x: 0.22, width: 0.10),
        o(text: 'to', y: 0.70, x: 0.35, width: 0.05),
      ];
      expect(observationsToText(input), 'Wilf came to');
    });

    test('separates visual lines with newlines', () {
      final input = [
        o(text: 'first line', y: 0.70, x: 0.10, width: 0.40),
        o(text: 'second line', y: 0.76, x: 0.10, width: 0.40),
      ];
      expect(observationsToText(input), 'first line\nsecond line');
    });
  });
}
