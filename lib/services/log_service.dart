import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Rotating local file logger. Strictly offline — never transmits anything.
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const int _maxBytes = 1024 * 1024; // 1 MB
  static const int _keepFiles = 3;

  File? _file;
  IOSink? _sink;
  final _lock = _Lock();

  Future<void> init() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final logsDir = Directory(p.join(supportDir.path, 'logs'));
      if (!await logsDir.exists()) await logsDir.create(recursive: true);
      _file = File(p.join(logsDir.path, 'app.log'));
      await _rotateIfNeeded();
      _sink = _file!.openWrite(mode: FileMode.writeOnlyAppend);
      info('LogService initialized at ${_file!.path}');
    } catch (e) {
      if (kDebugMode) debugPrint('LogService init failed: $e');
    }
  }

  Future<void> info(String message) => _write('INFO', message);
  Future<void> warn(String message) => _write('WARN', message);
  Future<void> error(String message, Object error, StackTrace? stack) =>
      _write('ERROR', '$message :: $error\n${stack ?? ''}');

  Future<void> _write(String level, String message) async {
    final line = '${DateTime.now().toIso8601String()} [$level] $message';
    if (kDebugMode) debugPrint(line);
    final sink = _sink;
    if (sink == null) return;
    await _lock.synchronized(() async {
      sink.writeln(line);
      await _rotateIfNeeded();
    });
  }

  Future<void> _rotateIfNeeded() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    final len = await file.length();
    if (len < _maxBytes) return;
    await _sink?.flush();
    await _sink?.close();
    _sink = null;

    for (var i = _keepFiles - 1; i >= 1; i--) {
      final from = File('${file.path}.$i');
      final to = File('${file.path}.${i + 1}');
      if (await from.exists()) await from.rename(to.path);
    }
    await file.rename('${file.path}.1');
    _file = File(file.path);
    _sink = _file!.openWrite(mode: FileMode.writeOnly);
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}

class _Lock {
  Future<void> _last = Future<void>.value();
  Future<T> synchronized<T>(Future<T> Function() body) {
    final completer = Completer<T>();
    final prev = _last;
    _last = prev.then((_) async {
      try {
        completer.complete(await body());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
