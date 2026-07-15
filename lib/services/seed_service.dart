import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'book_share_service.dart';
import 'log_service.dart';
import 'prefs_service.dart';

/// Progress snapshot for the first-launch Oxford-library import. UI binds to
/// [SeedService.progress] to render a loading screen.
@immutable
class SeedProgress {
  const SeedProgress({
    required this.done,
    required this.total,
    required this.currentTitle,
    required this.inProgress,
  });
  final int done;
  final int total;
  final String currentTitle;
  final bool inProgress;

  static const idle =
      SeedProgress(done: 0, total: 0, currentTitle: '', inProgress: false);
}

/// Seeds a sample book on first launch so the reader never starts on a blank
/// screen. Images are generated procedurally so we bundle no copyrighted
/// content. On builds that ship a baked Oxford library (`.book.zip` files
/// under `assets/seed/oxford/`), those are imported on first launch.
class SeedService {
  static const String _oxfordAssetPrefix = 'assets/seed/oxford/';

  /// Broadcasts progress of the Oxford-library import. UI screens listen
  /// here to render a "Setting up your library…" screen.
  static final ValueNotifier<SeedProgress> progress =
      ValueNotifier<SeedProgress>(SeedProgress.idle);

  static Future<void> seedIfEmpty(Database db) async {
    final existing = await db.query('books', limit: 1);
    if (existing.isNotEmpty) return;
    await _seed(db);
  }

  /// Imports every `.book.zip` shipped under `assets/seed/oxford/` into the
  /// user's DB. Idempotent: tracked via [PrefsService.oxfordSeeded]. Failures
  /// for individual books are logged and skipped so a corrupt zip doesn't
  /// kill the whole import.
  static Future<void> importBundledOxford({
    required PrefsService prefs,
    required BookShareService share,
  }) async {
    if (prefs.oxfordSeeded) return;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final zipAssets = manifest
        .listAssets()
        .where(
          (a) => a.startsWith(_oxfordAssetPrefix) && a.endsWith('.book.zip'),
        )
        .toList()
      ..sort();
    if (zipAssets.isEmpty) {
      // No baked library in this build — nothing to do, and don't mark the
      // pref so a later install that DOES bundle them can still seed.
      return;
    }

    final tmp = await getTemporaryDirectory();
    final stagingDir = Directory(p.join(tmp.path, 'oxford_seed_staging'));
    if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
    await stagingDir.create(recursive: true);

    progress.value = SeedProgress(
      done: 0,
      total: zipAssets.length,
      currentTitle: '',
      inProgress: true,
    );

    var success = 0;
    for (var i = 0; i < zipAssets.length; i++) {
      final asset = zipAssets[i];
      final title = p.basenameWithoutExtension(
        p.basenameWithoutExtension(asset),
      );
      progress.value = SeedProgress(
        done: i,
        total: zipAssets.length,
        currentTitle: title,
        inProgress: true,
      );
      try {
        final data = await rootBundle.load(asset);
        final stagePath = p.join(stagingDir.path, p.basename(asset));
        await File(stagePath)
            .writeAsBytes(data.buffer.asUint8List(), flush: true);
        await share.importBook(stagePath);
        await File(stagePath).delete();
        success++;
      } catch (e, st) {
        LogService.instance.error('Oxford seed import failed for $asset', e, st);
      }
    }

    await stagingDir.delete(recursive: true);
    await prefs.setOxfordSeeded(true);
    progress.value = SeedProgress(
      done: zipAssets.length,
      total: zipAssets.length,
      currentTitle: '',
      inProgress: false,
    );
    LogService.instance.info(
      'Oxford seed: imported $success of ${zipAssets.length} books',
    );
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
