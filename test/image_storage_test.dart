import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picture_book/services/image_storage_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final dir = Directory(p.join(root.path, 'docs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    final dir = Directory(p.join(root.path, 'support'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => root.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late ImageStorageService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pb_imgstore_');
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    service = ImageStorageService();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('storeFromFile produces a JPEG under images/<uuid>.jpg', () async {
    final source = await _writeSamplePng(tmp);
    final rel = await service.storeFromFile(source);
    expect(rel.startsWith('images/'), isTrue);
    expect(rel.endsWith('.jpg'), isTrue);
    expect(await service.exists(rel), isTrue);
  });

  test('deleteIfExists removes the stored file', () async {
    final source = await _writeSamplePng(tmp);
    final rel = await service.storeFromFile(source);
    expect(await service.exists(rel), isTrue);
    await service.deleteIfExists(rel);
    expect(await service.exists(rel), isFalse);
  });

  test('deleteMany removes every passed path', () async {
    final a = await service.storeFromFile(await _writeSamplePng(tmp, 'a'));
    final b = await service.storeFromFile(await _writeSamplePng(tmp, 'b'));
    await service.deleteMany([a, b]);
    expect(await service.exists(a), isFalse);
    expect(await service.exists(b), isFalse);
  });

  test('storeFromFile downscales an oversized image', () async {
    final big = img.Image(width: 4000, height: 3000);
    img.fill(big, color: img.ColorRgb8(120, 200, 80));
    final encoded = img.encodePng(big);
    final source = File(p.join(tmp.path, 'big.png'))..writeAsBytesSync(encoded);
    final rel = await service.storeFromFile(source);
    final stored = await service.resolve(rel);
    final decoded = img.decodeImage(await stored.readAsBytes())!;
    expect(decoded.width <= ImageStorageService.maxLongEdge, isTrue);
    expect(decoded.height <= ImageStorageService.maxLongEdge, isTrue);
  });
}

Future<File> _writeSamplePng(Directory dir, [String name = 'sample']) async {
  final image = img.Image(width: 64, height: 48);
  img.fill(image, color: img.ColorRgb8(255, 0, 0));
  final bytes = img.encodePng(image);
  final f = File(p.join(dir.path, '$name.png'));
  await f.writeAsBytes(bytes);
  return f;
}
