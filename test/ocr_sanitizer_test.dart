import 'package:flutter_test/flutter_test.dart';
import 'package:picture_book/utils/ocr_sanitizer.dart';

void main() {
  group('sanitizeOcrText', () {
    test('empty input returns empty', () {
      expect(sanitizeOcrText(''), '');
    });

    test('Garden Centre noise is stripped, story sentences kept', () {
      const raw =
          'Garden 2I313-01g entre Sell slug pailan Biff asked Anneena\'s mum to help her '
          'buy a plant. They went into a big greenhouse. The greenhouse was hot, '
          'and it was full of plants.';
      final cleaned = sanitizeOcrText(raw);
      // The OCR-garbage token "2I313-01g" must be gone.
      expect(cleaned.contains('2I313-01g'), isFalse);
      // The story content must survive.
      expect(cleaned.contains('Biff asked'), isTrue);
      expect(cleaned.contains('big greenhouse'), isTrue);
      expect(cleaned.contains('full of plants'), isTrue);
    });

    test('phone numbers are removed', () {
      final cleaned = sanitizeOcrText('Call us at +1 (555) 123-4567 today.');
      expect(cleaned.contains('123'), isFalse);
      expect(cleaned.contains('today'), isTrue);
    });

    test('email addresses are removed', () {
      final cleaned = sanitizeOcrText('Hello, email me at foo.bar@example.com here.');
      expect(cleaned.contains('@'), isFalse);
      expect(cleaned.contains('Hello'), isTrue);
      expect(cleaned.contains('here'), isTrue);
    });

    test('URLs are removed', () {
      final cleaned = sanitizeOcrText('See https://example.org/page for more.');
      expect(cleaned.contains('http'), isFalse);
      expect(cleaned.contains('example.org'), isFalse);
      expect(cleaned.contains('See'), isTrue);
      expect(cleaned.contains('more'), isTrue);
    });

    test('ISBN-like blocks are removed', () {
      final cleaned = sanitizeOcrText('ISBN 978-0-19-273452-1 published 2003.');
      expect(cleaned.contains('978-0-19'), isFalse);
      expect(cleaned.contains('published'), isTrue);
    });

    test('copyright line is dropped entirely', () {
      const raw = 'The cat sat on the mat.\n© 2003 Oxford University Press\nMore story.';
      final cleaned = sanitizeOcrText(raw);
      expect(cleaned.contains('Oxford'), isFalse);
      expect(cleaned.contains('cat sat'), isTrue);
      expect(cleaned.contains('More story'), isTrue);
    });

    test('all-uppercase shouty cluster is removed mid-sentence', () {
      final cleaned = sanitizeOcrText('Look at WE SELL SLUG POISON and walk away.');
      expect(cleaned.contains('SELL'), isFalse);
      expect(cleaned.contains('Look at'), isTrue);
      expect(cleaned.contains('walk away'), isTrue);
    });

    test('shouty cluster ending with terminator is retained', () {
      // The cluster ends with a token like "ANGRY!" (token includes the !);
      // entire sentence "I am ANGRY!" should be retained.
      const raw = 'I am ANGRY!';
      final cleaned = sanitizeOcrText(raw);
      expect(cleaned.contains('ANGRY!'), isTrue);
    });

    test('lone ALL-CAPS word inside a sentence is retained', () {
      const raw = 'Today HELP arrived just in time.';
      final cleaned = sanitizeOcrText(raw);
      // Single shouty token — not a cluster — must stay.
      expect(cleaned.contains('HELP'), isTrue);
    });

    test('pure junk that boils down to nothing returns empty', () {
      // After every rule fires there's nothing usable left.
      const raw = '©';
      // Copyright filter drops the line entirely → result is empty → "".
      expect(sanitizeOcrText(raw), '');
    });

    test('lone page number line is dropped', () {
      const raw = 'A normal sentence.\n34\nAnother sentence.';
      final cleaned = sanitizeOcrText(raw);
      expect(cleaned.contains('\n34\n'), isFalse);
      expect(cleaned.contains('A normal'), isTrue);
      expect(cleaned.contains('Another'), isTrue);
    });

    test('TEACHERS: marketing block is truncated', () {
      const raw =
          'The cat sat on the mat. TEACHERS: For inspirational support plus '
          'free resources and eBooks www.oxfordprimary.co.uk';
      final cleaned = sanitizeOcrText(raw);
      expect(cleaned.contains('TEACHERS'), isFalse);
      expect(cleaned.contains('inspirational'), isFalse);
      expect(cleaned.contains('oxfordprimary'), isFalse);
      expect(cleaned.contains('cat sat'), isTrue);
    });

    test('PARENTS: marketing block is truncated', () {
      const raw =
          'Story sentence here. PARENTS: Help your child\'s reading with tips.';
      final cleaned = sanitizeOcrText(raw);
      expect(cleaned.contains('PARENTS'), isFalse);
      expect(cleaned.contains('Help your child'), isFalse);
      expect(cleaned.contains('Story sentence'), isTrue);
    });

    test('AFTER READING / BEFORE READING pedagogy blocks are truncated', () {
      const raw =
          'A grand adventure begins. AFTER READING Turn to page 9. Ask: Why?';
      final cleaned = sanitizeOcrText(raw);
      expect(cleaned.contains('AFTER READING'), isFalse);
      expect(cleaned.contains('Turn to page'), isFalse);
      expect(cleaned.contains('grand adventure'), isTrue);
    });

    test('publisher metadata page returns empty', () {
      // Real back-matter content from a typical picture book.
      const raw =
          'Text © Roderick Hunt 1997\n'
          'Illustrations © Alex Brychta 1997\n'
          'First published 1997\n'
          'ISBN 978-0-19-848406-1\n'
          'All rights reserved. Photocopying of this book is illegal.\n'
          'Printed in China by Imago\n'
          'TEACHERS: For inspirational support visit www.oxfordprimary.co.uk\n'
          'PARENTS: Help your child\'s reading at www.oxfordowl.co.uk';
      final cleaned = sanitizeOcrText(raw);
      expect(cleaned, '');
    });

    test('bare-domain URL without www. is removed', () {
      final cleaned = sanitizeOcrText('See oxfordowl.co.uk for more.');
      expect(cleaned.contains('oxfordowl'), isFalse);
      expect(cleaned.contains('See'), isTrue);
      expect(cleaned.contains('more'), isTrue);
    });

    test('trailing page number after a sentence terminator is stripped', () {
      final cleaned =
          sanitizeOcrText('The cat sat on the mat. 35');
      expect(cleaned.trim(), 'The cat sat on the mat.');
    });

    test('trailing bare page number (no period) is stripped from a real line',
        () {
      final cleaned = sanitizeOcrText('The cat sat on the mat 35');
      expect(cleaned.trim(), 'The cat sat on the mat');
    });

    test('leading page number before a capital is stripped', () {
      final cleaned = sanitizeOcrText('35 The cat sat on the mat.');
      expect(cleaned.trim(), 'The cat sat on the mat.');
    });

    test('number inside a paragraph is preserved', () {
      // "3 apples" is content, not a page number — must survive.
      final cleaned =
          sanitizeOcrText('I have 3 apples and 12 oranges in the basket.');
      expect(cleaned.contains('3'), isTrue);
      expect(cleaned.contains('12'), isTrue);
      expect(cleaned.contains('apples'), isTrue);
    });

    test('two-word sentence with trailing number is NOT stripped (defensive)',
        () {
      // "I have 12" has only one letter token before the number — that's not
      // enough evidence to assume "12" is a page number; keep it as content.
      final cleaned = sanitizeOcrText('I have 12');
      expect(cleaned.contains('12'), isTrue);
    });
  });
}
