import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picture_book/services/dictionary_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory(p.join(root.path, 'support'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async => root.path;

  @override
  Future<String?> getTemporaryPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pb_dict_');
    PathProviderPlatform.instance = _FakePathProvider(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('lookup is case- and trim-insensitive for shipped entries', () async {
    final svc = DictionaryService();
    await svc.init();
    expect(svc.isReady, isTrue, reason: 'asset must load');

    final a = await svc.lookup('cat');
    final b = await svc.lookup('CAT');
    final c = await svc.lookup('  cat ');
    expect(a, isNotNull);
    expect(a!.chinese.isNotEmpty, isTrue);
    expect(b?.word, a.word);
    expect(c?.word, a.word);
  });

  test('miss returns null', () async {
    final svc = DictionaryService();
    await svc.init();
    expect(await svc.lookup('zzznotaword'), isNull);
  });

  test('lookupMany returns hits in one round trip', () async {
    final svc = DictionaryService();
    await svc.init();
    final entries = await svc.lookupMany(['cat', 'dog', 'zzznotaword']);
    final words = entries.map((e) => e.word).toSet();
    expect(words, contains('cat'));
    expect(words, contains('dog'));
    expect(words, isNot(contains('zzznotaword')));
  });

  test('database is opened read-only — writes throw', () async {
    final svc = DictionaryService();
    await svc.init();
    // Reach the local DB file the service copied out of the asset bundle.
    final support = await Directory(p.join(tmp.path, 'support', 'dict')).list().toList();
    expect(support, isNotEmpty);
    final localDb = await openDatabase(support.first.path);
    expect(
      () => localDb.execute('INSERT INTO entries(word) VALUES (?)', ['x']),
      throwsA(isA<DatabaseException>()),
    );
    await localDb.close();
  });

  test('stemmer hits inflected forms via candidateStems', () async {
    // Build a minimal entries DB containing only the headwords we want.
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE entries (
              word TEXT PRIMARY KEY,
              pinyin TEXT NOT NULL DEFAULT '',
              chinese TEXT NOT NULL DEFAULT '',
              definition TEXT NOT NULL DEFAULT '',
              detail TEXT NOT NULL DEFAULT ''
            )
          ''');
          for (final w in const ['play', 'make', 'day', 'mum', 'big', 'try']) {
            await db.insert('entries', {
              'word': w,
              'chinese': 'X',
              'definition': 'X',
            });
          }
        },
      ),
    );

    final svc = DictionaryService();
    svc.setDatabaseForTesting(db);

    expect((await svc.lookup('playing'))?.word, 'play');
    expect((await svc.lookup('making'))?.word, 'make');
    expect((await svc.lookup('days'))?.word, 'day');
    expect((await svc.lookup("mum's"))?.word, 'mum');
    expect((await svc.lookup('bigger'))?.word, 'big');
    expect((await svc.lookup('tried'))?.word, 'try');
    expect(await svc.lookup('zzznotaword'), isNull);

    await db.close();
  });
}
