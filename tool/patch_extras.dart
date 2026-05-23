// Patches an already-built assets/dict/ecdict.db with the numeric extras
// from build_dict.dart, without re-downloading ECDICT.
//
// Use this after pulling a v5+ change that adds extras to an existing
// `--full` dictionary you already have committed:
//
//   dart run tool/patch_extras.dart
//
// Future fresh builds (`dart run tool/fetch_ecdict.dart` or
// `dart run tool/build_dict.dart --starter`) include these extras
// automatically — this tool is only a one-shot for already-committed DBs.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _dbRelPath = 'assets/dict/ecdict.db';

const Map<String, (String chinese, String definition)> _numericExtras = {
  '0': ('零', 'Number 0.'),
  '1': ('一', 'Number 1.'),
  '2': ('二', 'Number 2.'),
  '3': ('三', 'Number 3.'),
  '4': ('四', 'Number 4.'),
  '5': ('五', 'Number 5.'),
  '6': ('六', 'Number 6.'),
  '7': ('七', 'Number 7.'),
  '8': ('八', 'Number 8.'),
  '9': ('九', 'Number 9.'),
  '10': ('十', 'Number 10.'),
  '11': ('十一', 'Number 11.'),
  '12': ('十二', 'Number 12.'),
  '13': ('十三', 'Number 13.'),
  '14': ('十四', 'Number 14.'),
  '15': ('十五', 'Number 15.'),
  '16': ('十六', 'Number 16.'),
  '17': ('十七', 'Number 17.'),
  '18': ('十八', 'Number 18.'),
  '19': ('十九', 'Number 19.'),
  '20': ('二十', 'Number 20.'),
  '21': ('二十一', 'Number 21.'),
  '22': ('二十二', 'Number 22.'),
  '25': ('二十五', 'Number 25.'),
  '30': ('三十', 'Number 30.'),
  '40': ('四十', 'Number 40.'),
  '50': ('五十', 'Number 50.'),
  '60': ('六十', 'Number 60.'),
  '70': ('七十', 'Number 70.'),
  '80': ('八十', 'Number 80.'),
  '90': ('九十', 'Number 90.'),
  '100': ('一百', 'Number 100.'),
  '1000': ('一千', 'Number 1000.'),
  '10000': ('一万', 'Number 10 000.'),
  '1st': ('第一', '1st (first).'),
  '2nd': ('第二', '2nd (second).'),
  '3rd': ('第三', '3rd (third).'),
  '4th': ('第四', '4th (fourth).'),
  '5th': ('第五', '5th (fifth).'),
  '6th': ('第六', '6th (sixth).'),
  '7th': ('第七', '7th (seventh).'),
  '8th': ('第八', '8th (eighth).'),
  '9th': ('第九', '9th (ninth).'),
  '10th': ('第十', '10th (tenth).'),
};

Future<int> main(List<String> args) async {
  sqfliteFfiInit();
  final dbPath = p.absolute(_dbRelPath);
  if (!await File(dbPath).exists()) {
    stderr.writeln('No DB at $dbPath. Run tool/fetch_ecdict.dart first.');
    return 1;
  }
  // sqflite_common_ffi remaps relative paths under .dart_tool; wipe any
  // stale copy so the patched DB is what gets committed.
  final cached = File(
    p.join(
      Directory.current.path,
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      'assets',
      'dict',
      'ecdict.db',
    ),
  );
  if (await cached.exists()) await cached.delete();

  final db = await databaseFactoryFfi.openDatabase(dbPath);
  try {
    var inserted = 0;
    await db.transaction((txn) async {
      for (final entry in _numericExtras.entries) {
        await txn.insert(
          'entries',
          <String, Object?>{
            'word': entry.key,
            'pinyin': '',
            'chinese': entry.value.$1,
            'definition': entry.value.$2,
            'detail': '',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        inserted++;
      }
    });
    stdout.writeln('Patched $inserted numeric extras into $dbPath.');
  } finally {
    await db.close();
  }
  return 0;
}
