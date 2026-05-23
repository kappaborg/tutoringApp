import 'package:flutter_test/flutter_test.dart';
import 'package:picture_book/utils/sentence_splitter.dart';

void main() {
  group('splitIntoSentences', () {
    test('empty returns empty list', () {
      expect(splitIntoSentences(''), isEmpty);
      expect(splitIntoSentences('   '), isEmpty);
    });

    test('three simple sentences keep their terminators', () {
      final out = splitIntoSentences('One. Two? Three!');
      expect(out, ['One.', 'Two?', 'Three!']);
    });

    test('honours common abbreviations', () {
      final out = splitIntoSentences('Mr. Smith went home. Dr. Watson agreed.');
      expect(out, ['Mr. Smith went home.', 'Dr. Watson agreed.']);
    });

    test('does not split decimals', () {
      final out = splitIntoSentences('He paid 3.50 for it.');
      expect(out, ['He paid 3.50 for it.']);
    });

    test('does not split single-letter initials', () {
      final out = splitIntoSentences('J. K. Rowling wrote a book.');
      expect(out, ['J. K. Rowling wrote a book.']);
    });

    test('handles CJK terminators', () {
      final out = splitIntoSentences('今天很好。明天呢？');
      expect(out, ['今天很好。', '明天呢？']);
    });

    test('pathological whitespace before terminators', () {
      final out = splitIntoSentences('  Foo .   Bar ! ');
      expect(out, ['Foo.', 'Bar!']);
    });

    test('single sentence without terminator is preserved', () {
      final out = splitIntoSentences('Hello world');
      expect(out, ['Hello world']);
    });

    test('mixed English and CJK in same paragraph', () {
      final out = splitIntoSentences('Hello. 你好。Goodbye!');
      expect(out, ['Hello.', '你好。', 'Goodbye!']);
    });
  });
}
