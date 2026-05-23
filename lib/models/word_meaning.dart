enum WordSource {
  manual('manual'),
  dictionary('dictionary'),
  pdf('pdf');

  const WordSource(this.value);
  final String value;

  static WordSource fromValue(String? v) {
    for (final s in WordSource.values) {
      if (s.value == v) return s;
    }
    return WordSource.manual;
  }
}

class WordMeaning {
  const WordMeaning({
    required this.id,
    required this.pageId,
    required this.word,
    required this.chineseMeaning,
    required this.englishDefinition,
    this.ttsOverride,
    this.source = WordSource.manual,
  });

  final int? id;
  final int pageId;
  final String word; // stored lowercased
  final String chineseMeaning;
  final String englishDefinition;
  final String? ttsOverride;
  final WordSource source;

  WordMeaning copyWith({
    int? id,
    int? pageId,
    String? word,
    String? chineseMeaning,
    String? englishDefinition,
    String? ttsOverride,
    WordSource? source,
  }) {
    return WordMeaning(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      word: word ?? this.word,
      chineseMeaning: chineseMeaning ?? this.chineseMeaning,
      englishDefinition: englishDefinition ?? this.englishDefinition,
      ttsOverride: ttsOverride ?? this.ttsOverride,
      source: source ?? this.source,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'page_id': pageId,
        'word': word.toLowerCase(),
        'chinese_meaning': chineseMeaning,
        'english_definition': englishDefinition,
        'tts_override': ttsOverride,
        'source': source.value,
      };

  factory WordMeaning.fromMap(Map<String, Object?> map) => WordMeaning(
        id: map['id'] as int?,
        pageId: map['page_id']! as int,
        word: map['word']! as String,
        chineseMeaning: map['chinese_meaning']! as String,
        englishDefinition: map['english_definition']! as String,
        ttsOverride: map['tts_override'] as String?,
        source: WordSource.fromValue(map['source'] as String?),
      );

  @override
  bool operator ==(Object other) =>
      other is WordMeaning &&
      other.id == id &&
      other.pageId == pageId &&
      other.word == word &&
      other.chineseMeaning == chineseMeaning &&
      other.englishDefinition == englishDefinition &&
      other.ttsOverride == ttsOverride &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
        id,
        pageId,
        word,
        chineseMeaning,
        englishDefinition,
        ttsOverride,
        source,
      );
}
