// Generates a 1024×1024 source icon at assets/icon/app_icon.png plus a
// transparent foreground variant at assets/icon/app_icon_foreground.png.
//
// After running this, propagate to platform icon slots via:
//   dart run flutter_launcher_icons
//
// (See pubspec.yaml's flutter_launcher_icons section for the mapping.)

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

Future<int> main(List<String> args) async {
  const size = 1024;
  await _renderSquare(size);
  await _renderForeground(size);
  return 0;
}

Future<void> _renderSquare(int size) async {
  // Full-bleed brand-coloured square with a book glyph on top.
  final canvas = img.Image(width: size, height: size);
  final scheme = _kPrimary;
  img.fill(canvas, color: scheme);
  _drawBookGlyph(canvas, size);

  final out = File(p.absolute('assets/icon/app_icon.png'));
  await out.parent.create(recursive: true);
  await out.writeAsBytes(img.encodePng(canvas));
  stdout.writeln('Wrote ${out.path}');
}

Future<void> _renderForeground(int size) async {
  // Transparent canvas with just the glyph, for adaptive icons (Android).
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  _drawBookGlyph(canvas, size, inset: size ~/ 6);

  final out = File(p.absolute('assets/icon/app_icon_foreground.png'));
  await out.writeAsBytes(img.encodePng(canvas));
  stdout.writeln('Wrote ${out.path}');
}

final _kPrimary = img.ColorRgb8(79, 109, 222);
final _kBookCover = img.ColorRgb8(255, 255, 255);
final _kBookPage = img.ColorRgb8(245, 247, 255);
final _kAccent = img.ColorRgb8(255, 196, 87);

void _drawBookGlyph(img.Image canvas, int size, {int inset = 0}) {
  final cx = size / 2;
  final cy = size / 2;
  // Book dimensions
  final w = (size * (0.62 - inset / size)).round();
  final h = (size * (0.42 - inset / size)).round();
  final left = (cx - w / 2).round();
  final top = (cy - h / 2).round();

  // Outer book cover (white) with a touch of border radius (we fake it via
  // rounded corners by drawing a slightly-smaller filled rect and then
  // overlaying corner circles).
  _fillRoundedRect(canvas, left, top, w, h, 48, _kBookCover);

  // Page split (vertical line down the middle of the book).
  final midX = (cx).round();
  img.drawLine(
    canvas,
    x1: midX,
    y1: top + 24,
    x2: midX,
    y2: top + h - 24,
    color: _kBookPage,
    thickness: 6,
  );

  // Two pages of "text" (a few horizontal lines per page).
  final lineColour = _kPrimary;
  const pageMargin = 38;
  final leftPageX = left + pageMargin;
  final leftPageEnd = midX - 20;
  final rightPageX = midX + 20;
  final rightPageEnd = left + w - pageMargin;
  for (var i = 0; i < 5; i++) {
    final y = top + 80 + i * 36;
    final width = (i == 4) ? 0.7 : 1.0; // last line shorter
    final lpe = (leftPageEnd - (1 - width) * (leftPageEnd - leftPageX)).round();
    final rpe =
        (rightPageEnd - (1 - width) * (rightPageEnd - rightPageX)).round();
    img.drawLine(
      canvas,
      x1: leftPageX,
      y1: y,
      x2: lpe,
      y2: y,
      color: lineColour,
      thickness: 10,
    );
    img.drawLine(
      canvas,
      x1: rightPageX,
      y1: y,
      x2: rpe,
      y2: y,
      color: lineColour,
      thickness: 10,
    );
  }

  // A small star above the book — playful brand mark.
  _drawStar(canvas, cx.round(), top - 60, 28, _kAccent);
}

void _fillRoundedRect(
  img.Image canvas,
  int x,
  int y,
  int w,
  int h,
  int radius,
  img.Color colour,
) {
  img.fillRect(canvas, x1: x, y1: y, x2: x + w, y2: y + h, color: colour);
  // No native rounded rect; cheap approximation by painting corner circles
  // in the background colour. For now we just leave sharp corners — the
  // platform tooling rounds them automatically for iOS / Android.
}

void _drawStar(img.Image canvas, int cx, int cy, int r, img.Color colour) {
  // Cheap 5-point star polygon.
  final points = <List<int>>[];
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? r : (r * 0.45).round();
    final angle = -math.pi / 2 + i * math.pi / 5;
    points.add([
      (cx + radius * math.cos(angle)).round(),
      (cy + radius * math.sin(angle)).round(),
    ]);
  }
  for (var i = 0; i < points.length; i++) {
    final a = points[i];
    final b = points[(i + 1) % points.length];
    img.drawLine(
      canvas,
      x1: a[0],
      y1: a[1],
      x2: b[0],
      y2: b[1],
      color: colour,
      thickness: 6,
    );
  }
  // Fill the star by flooding from its centre. fillCircle approximates fine.
  img.fillCircle(canvas, x: cx, y: cy, radius: (r * 0.45).round(), color: colour);
}
