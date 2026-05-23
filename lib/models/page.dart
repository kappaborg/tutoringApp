class BookPage {
  const BookPage({
    required this.id,
    required this.bookId,
    required this.pageNumber,
    required this.imagePath,
    required this.sentenceText,
    this.chineseTranslation = '',
  });

  final int? id;
  final int bookId;
  final int pageNumber;
  final String imagePath;
  final String sentenceText;
  final String chineseTranslation;

  BookPage copyWith({
    int? id,
    int? bookId,
    int? pageNumber,
    String? imagePath,
    String? sentenceText,
    String? chineseTranslation,
  }) {
    return BookPage(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      pageNumber: pageNumber ?? this.pageNumber,
      imagePath: imagePath ?? this.imagePath,
      sentenceText: sentenceText ?? this.sentenceText,
      chineseTranslation: chineseTranslation ?? this.chineseTranslation,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'book_id': bookId,
        'page_number': pageNumber,
        'image_path': imagePath,
        'sentence_text': sentenceText,
        'chinese_translation': chineseTranslation,
      };

  factory BookPage.fromMap(Map<String, Object?> map) => BookPage(
        id: map['id'] as int?,
        bookId: map['book_id']! as int,
        pageNumber: map['page_number']! as int,
        imagePath: map['image_path']! as String,
        sentenceText: map['sentence_text']! as String,
        chineseTranslation: (map['chinese_translation'] as String?) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is BookPage &&
      other.id == id &&
      other.bookId == bookId &&
      other.pageNumber == pageNumber &&
      other.imagePath == imagePath &&
      other.sentenceText == sentenceText &&
      other.chineseTranslation == chineseTranslation;

  @override
  int get hashCode => Object.hash(
        id,
        bookId,
        pageNumber,
        imagePath,
        sentenceText,
        chineseTranslation,
      );
}
