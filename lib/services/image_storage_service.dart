import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Handles image picking, EXIF-bake, downscale, JPEG re-encode, and orphan
/// cleanup. Images live in `<docs>/images/<uuid>.jpg`; the DB stores the
/// relative path "images/<uuid>.jpg".
class ImageStorageService {
  ImageStorageService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final Uuid _uuid;

  static const int maxLongEdge = 2048;
  static const int jpegQuality = 85;

  /// Lets the user pick an image and stores a processed copy. Returns the
  /// relative DB path, or null if the user cancelled.
  Future<String?> pickAndStore() async {
    final sourcePath = await _pick();
    if (sourcePath == null) return null;
    return storeFromFile(File(sourcePath));
  }

  Future<String?> _pick() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      return picked?.path;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    );
    return result?.files.single.path;
  }

  /// Reads, orients, downscales, and re-encodes [source] into the images
  /// directory. Returns the relative path stored in the DB.
  Future<String> storeFromFile(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or corrupt image file.');
    }
    final oriented = img.bakeOrientation(decoded);
    final longest = oriented.width > oriented.height ? oriented.width : oriented.height;
    final img.Image resized = longest > maxLongEdge
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height
                ? maxLongEdge
                : (oriented.width * maxLongEdge / oriented.height).round(),
            height: oriented.height >= oriented.width
                ? maxLongEdge
                : (oriented.height * maxLongEdge / oriented.width).round(),
            interpolation: img.Interpolation.linear,
          )
        : oriented;

    final encoded = img.encodeJpg(resized, quality: jpegQuality);
    final imagesDir = await _imagesDir();
    final filename = '${_uuid.v4()}.jpg';
    final dest = File(p.join(imagesDir.path, filename));
    await dest.writeAsBytes(encoded, flush: true);
    return 'images/$filename';
  }

  Future<Directory> _imagesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'images'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> resolve(String relativePath) async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, relativePath));
  }

  Future<bool> exists(String relativePath) async {
    final f = await resolve(relativePath);
    return f.exists();
  }

  Future<void> deleteIfExists(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    final f = await resolve(relativePath);
    if (await f.exists()) {
      await f.delete();
    }
  }

  Future<void> deleteMany(Iterable<String> relativePaths) async {
    for (final r in relativePaths) {
      await deleteIfExists(r);
    }
  }
}
