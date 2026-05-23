import 'package:flutter_test/flutter_test.dart';
import 'package:picture_book/utils/tokenizer.dart';

void main() {
  group('Tokenizer.tokenize', () {
    test('splits a simple sentence and lowercases lookup keys', () {
      final tokens = Tokenizer.tokenize('The cat sleeps on the mat.');
      expect(
        tokens.map((t) => t.display).toList(),
        ['The', 'cat', 'sleeps', 'on', 'the', 'mat.'],
      );
      expect(
        tokens.map((t) => t.lookupKey).toList(),
        ['the', 'cat', 'sleeps', 'on', 'the', 'mat'],
      );
    });

    test('keeps trailing punctuation visible but strips it from lookup', () {
      final tokens = Tokenizer.tokenize('Hello, world!');
      expect(tokens.length, 2);
      expect(tokens[0].display, 'Hello,');
      expect(tokens[0].lookupKey, 'hello');
      expect(tokens[1].display, 'world!');
      expect(tokens[1].lookupKey, 'world');
    });

    test('handles smart quotes and apostrophes', () {
      final tokens = Tokenizer.tokenize("It’s “okay” — really.");
      final keys = tokens.map((t) => t.lookupKey).toList();
      expect(keys, containsAllInOrder(["it's", 'okay', 'really']));
    });

    test('handles accented characters', () {
      final tokens = Tokenizer.tokenize('Café au lait, naïve résumé.');
      final keys = tokens.map((t) => t.lookupKey).toList();
      expect(keys, ['café', 'au', 'lait', 'naïve', 'résumé']);
    });

    test('empty input returns empty list', () {
      expect(Tokenizer.tokenize(''), isEmpty);
    });

    test('uniqueWords de-duplicates case-insensitively and preserves order', () {
      final unique = Tokenizer.uniqueWords('The cat and the Cat.');
      expect(unique, ['the', 'cat', 'and']);
    });

    test('digit-only tokens are tappable (lookup key = the digits)', () {
      final tokens = Tokenizer.tokenize('I have 3 apples.');
      final keys = tokens.map((t) => t.lookupKey).toList();
      expect(keys, contains('3'));
      expect(
        tokens.firstWhere((t) => t.lookupKey == '3').hasLetters,
        isTrue,
      );
    });

    test('uniqueWords includes digit-only tokens', () {
      final words = Tokenizer.uniqueWords('I have 3 apples and 12 oranges.');
      expect(words, contains('3'));
      expect(words, contains('12'));
    });

    test('char ranges cover the chunk including trailing punctuation', () {
      const sentence = 'Hello, world!';
      final tokens = Tokenizer.tokenize(sentence);
      expect(
        sentence.substring(tokens[0].charStart, tokens[0].charEnd),
        'Hello,',
      );
      expect(
        sentence.substring(tokens[1].charStart, tokens[1].charEnd),
        'world!',
      );
    });
  });
}
