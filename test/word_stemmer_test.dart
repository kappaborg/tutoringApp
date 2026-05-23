import 'package:flutter_test/flutter_test.dart';
import 'package:picture_book/utils/word_stemmer.dart';

void main() {
  group('candidateStems', () {
    test('plain word yields just itself', () {
      expect(candidateStems('day'), ['day']);
    });

    test('regular plural strips s', () {
      expect(candidateStems('days'), contains('day'));
    });

    test("possessive 's strips it", () {
      expect(candidateStems("mum's"), contains('mum'));
    });

    test('curly possessive strips it too', () {
      expect(candidateStems('mum’s'), contains('mum'));
    });

    test('present participle strips ing', () {
      expect(candidateStems('playing'), contains('play'));
    });

    test('ing→e for "making"', () {
      final stems = candidateStems('making');
      expect(stems, contains('make'));
    });

    test('past tense de-doubles for "stopped"', () {
      final stems = candidateStems('stopped');
      expect(stems, contains('stop'));
    });

    test('-ies → y for "berries"', () {
      final stems = candidateStems('berries');
      expect(stems, contains('berry'));
    });

    test('comparative -er de-doubles for "bigger"', () {
      final stems = candidateStems('bigger');
      expect(stems, contains('big'));
    });

    test('superlative -est de-doubles for "biggest"', () {
      final stems = candidateStems('biggest');
      expect(stems, contains('big'));
    });

    test('-ied → y for "tried"', () {
      expect(candidateStems('tried'), contains('try'));
    });

    test('-ing de-doubles for "running"', () {
      expect(candidateStems('running'), contains('run'));
    });

    test('does not produce length-1 stems', () {
      // "as" → as-is. Rule 3 would propose "a", but minimum length 2 filters
      // it out.
      final stems = candidateStems('as');
      expect(stems, ['as']);
      expect(stems.every((s) => s.length >= 2), isTrue);
    });

    test('1-char input returns empty', () {
      expect(candidateStems('a'), isEmpty);
    });

    test('case-insensitive input is lowercased', () {
      expect(candidateStems('DAYS'), contains('day'));
    });

    test('-ss endings are not split', () {
      // "grass" should not propose "gras".
      final stems = candidateStems('grass');
      expect(stems, contains('grass'));
      expect(stems.contains('gras'), isFalse);
    });
  });
}
