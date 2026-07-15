// Generates a fresh Ed25519 keypair for the license-code system.
//
// Run ONCE per project setup. The private key is written outside the repo
// (default: ~/.picturebook/private_key.bin); the public key bytes are
// printed to stdout so you can paste them into
// lib/services/license_service.dart's `_kPublicKey` constant.
//
// SECURITY: the private key signs every license you issue. Treat it like a
// money-printing press — back it up offline, never commit it, never share.
// If it leaks, anyone can issue licenses indistinguishable from yours and
// you'd have to rotate the key (which invalidates every existing customer's
// activation). Storage outside the repo is non-negotiable.

import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

Future<int> main(List<String> args) async {
  // Default location: ~/.picturebook/private_key.bin
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home == null) {
    stderr.writeln('Cannot resolve home directory.');
    return 2;
  }
  final outDir = Directory(p.join(home, '.picturebook'));
  if (!await outDir.exists()) await outDir.create(recursive: true);
  final privFile = File(p.join(outDir.path, 'private_key.bin'));

  if (await privFile.exists()) {
    stderr.writeln(
      'Refusing to overwrite existing private key at ${privFile.path}.\n'
      'If you really want to rotate, delete the old file first — but be\n'
      'aware that every license already issued will stop working.',
    );
    return 1;
  }

  final algo = Ed25519();
  final pair = await algo.newKeyPair();
  final priv = await pair.extractPrivateKeyBytes();
  final pub = await pair.extractPublicKey();

  await privFile.writeAsBytes(priv, flush: true);
  // Restrict the file (rw owner only). Best effort on Unix.
  if (!Platform.isWindows) {
    await Process.run('chmod', ['600', privFile.path]);
  }

  stdout.writeln('Wrote private key: ${privFile.path} (keep secret!)');
  stdout.writeln();
  stdout.writeln('Paste the line below into lib/services/license_service.dart');
  stdout.writeln('as the body of _kPublicKey:');
  stdout.writeln();
  stdout.write('static const List<int> _kPublicKey = <int>[');
  for (var i = 0; i < pub.bytes.length; i++) {
    if (i > 0) stdout.write(', ');
    stdout.write('0x${pub.bytes[i].toRadixString(16).padLeft(2, '0')}');
  }
  stdout.writeln('];');
  stdout.writeln();
  return 0;
}
