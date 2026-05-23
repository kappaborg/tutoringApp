import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Seeds a sample book on first launch so the reader never starts on a blank
/// screen. Images are generated procedurally so we bundle no copyrighted
/// content.
class SeedService {
  static Future<void> seedIfEmpty(Database db) async {
    final existing = await db.query('books', limit: 1);
    if (existing.isNotEmpty) return;
    await _seed(db);
  }

  static Future<void> _seed(Database db) async {
    final docs = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(docs.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

    final pages = <_SeedPage>[
      _SeedPage(
        label: 'cat',
        sentence: 'The cat sleeps on the mat.',
        chineseTranslation: '小猫睡在垫子上。',
        background: img.ColorRgb8(255, 200, 150),
        accent: img.ColorRgb8(150, 90, 60),
        words: const {
          'cat': _Word('猫', 'A small furry pet animal.'),
          'sleeps': _Word('睡觉', 'Rests with eyes closed.'),
          'mat': _Word('垫子', 'A small flat piece you sit or stand on.'),
        },
      ),
      _SeedPage(
        label: 'dog',
        sentence: 'A dog runs in the park.',
        chineseTranslation: '一只狗在公园里跑。',
        background: img.ColorRgb8(180, 220, 255),
        accent: img.ColorRgb8(40, 80, 140),
        words: const {
          'dog': _Word('狗', 'A friendly four-legged pet animal.'),
          'runs': _Word('跑', 'Moves quickly on foot.'),
          'park': _Word('公园', 'An open green space outdoors.'),
        },
      ),
      _SeedPage(
        label: 'sun',
        sentence: 'The sun shines bright today.',
        chineseTranslation: '今天太阳很明亮。',
        background: img.ColorRgb8(255, 240, 150),
        accent: img.ColorRgb8(200, 140, 30),
        words: const {
          'sun': _Word('太阳', 'The star at the centre of our solar system.'),
          'shines': _Word('照耀', 'Gives off light.'),
          'bright': _Word('明亮', 'Full of light.'),
          'today': _Word('今天', 'On this present day.'),
        },
      ),
    ];

    await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final bookId = await txn.insert('books', <String, Object?>{
        'title': 'Sample Book',
        'created_at': now,
        'updated_at': now,
      });

      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        final relPath = await _writeImage(imagesDir, page);
        final pageId = await txn.insert('pages', <String, Object?>{
          'book_id': bookId,
          'page_number': i + 1,
          'image_path': relPath,
          'sentence_text': page.sentence,
          'chinese_translation': page.chineseTranslation,
        });
        for (final entry in page.words.entries) {
          await txn.insert('word_meanings', <String, Object?>{
            'page_id': pageId,
            'word': entry.key,
            'chinese_meaning': entry.value.zh,
            'english_definition': entry.value.def,
          });
        }
      }
    });
  }

  static Future<String> _writeImage(Directory dir, _SeedPage page) async {
    final image = img.Image(width: 800, height: 600);
    img.fill(image, color: page.background);
    img.fillCircle(
      image,
      x: 400,
      y: 300,
      radius: 180,
      color: img.ColorRgb8(255, 255, 255),
    );
    img.drawString(
      image,
      page.label.toUpperCase(),
      font: img.arial48,
      x: 360,
      y: 280,
      color: page.accent,
    );
    final bytes = img.encodeJpg(image, quality: 85);
    final filename = 'seed_${page.label}.jpg';
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return 'images/$filename';
  }
}

class _SeedPage {
  _SeedPage({
    required this.label,
    required this.sentence,
    required this.chineseTranslation,
    required this.background,
    required this.accent,
    required this.words,
  });
  final String label;
  final String sentence;
  final String chineseTranslation;
  final img.Color background;
  final img.Color accent;
  final Map<String, _Word> words;
}

class _Word {
  const _Word(this.zh, this.def);
  final String zh;
  final String def;
}
