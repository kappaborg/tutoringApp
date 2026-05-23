class Book {
  const Book({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  Book copyWith({int? id, String? title, DateTime? createdAt, DateTime? updatedAt}) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'title': title,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Book.fromMap(Map<String, Object?> map) => Book(
        id: map['id'] as int?,
        title: map['title']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
      );

  @override
  bool operator ==(Object other) =>
      other is Book &&
      other.id == id &&
      other.title == title &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, title, createdAt, updatedAt);
}
