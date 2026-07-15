import 'dart:convert';

class BookPage {
  const BookPage({
    required this.id,
    required this.bookId,
    required this.pageNumber,
    required this.imagePath,
    required this.sentenceText,
    this.chineseTranslation = '',
    this.audioPath = '',
    this.sentenceAudioMap = const <String, String>{},
  });

  final int? id;
  final int bookId;
  final int pageNumber;
  final String imagePath;
  final String sentenceText;
  final String chineseTranslation;

  /// Relative path (under the docs dir) of a pre-rendered neural-TTS audio
  /// clip for [sentenceText]. Empty when the book wasn't baked with audio,
  /// in which case the TTS engine renders live.
  final String audioPath;

  /// Optional map from a sub-sentence (as produced by `splitIntoSentences`)
  /// to a docs-relative audio file rendered for that exact text. Populated
  /// at bake time so sentence-mode taps can play instantly instead of
  /// hitting live inference.
  final Map<String, String> sentenceAudioMap;

  BookPage copyWith({
    int? id,
    int? bookId,
    int? pageNumber,
    String? imagePath,
    String? sentenceText,
    String? chineseTranslation,
    String? audioPath,
    Map<String, String>? sentenceAudioMap,
  }) {
    return BookPage(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      pageNumber: pageNumber ?? this.pageNumber,
      imagePath: imagePath ?? this.imagePath,
      sentenceText: sentenceText ?? this.sentenceText,
      chineseTranslation: chineseTranslation ?? this.chineseTranslation,
      audioPath: audioPath ?? this.audioPath,
      sentenceAudioMap: sentenceAudioMap ?? this.sentenceAudioMap,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'book_id': bookId,
        'page_number': pageNumber,
        'image_path': imagePath,
        'sentence_text': sentenceText,
        'chinese_translation': chineseTranslation,
        'audio_path': audioPath,
        'sentence_audio_map': jsonEncode(sentenceAudioMap),
      };

  factory BookPage.fromMap(Map<String, Object?> map) => BookPage(
        id: map['id'] as int?,
        bookId: map['book_id']! as int,
        pageNumber: map['page_number']! as int,
        imagePath: map['image_path']! as String,
        sentenceText: map['sentence_text']! as String,
        chineseTranslation: (map['chinese_translation'] as String?) ?? '',
        audioPath: (map['audio_path'] as String?) ?? '',
        sentenceAudioMap: _decodeAudioMap(map['sentence_audio_map']),
      );

  static Map<String, String> _decodeAudioMap(Object? v) {
    if (v is! String || v.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(v);
      if (decoded is! Map) return const <String, String>{};
      return decoded.map(
        (k, val) => MapEntry(k.toString(), val.toString()),
      );
    } catch (_) {
      return const <String, String>{};
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BookPage &&
      other.id == id &&
      other.bookId == bookId &&
      other.pageNumber == pageNumber &&
      other.imagePath == imagePath &&
      other.sentenceText == sentenceText &&
      other.chineseTranslation == chineseTranslation &&
      other.audioPath == audioPath &&
      _mapEquals(other.sentenceAudioMap, sentenceAudioMap);

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        pageNumber,
        imagePath,
        sentenceText,
        chineseTranslation,
        audioPath,
        jsonEncode(_sortedCopy(sentenceAudioMap)),
      );

  static Map<String, String> _sortedCopy(Map<String, String> m) {
    final keys = m.keys.toList()..sort();
    return <String, String>{for (final k in keys) k: m[k]!};
  }

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}
