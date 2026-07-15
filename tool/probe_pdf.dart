// One-off diagnostic: open a single PDF via the same pipeline the bake uses,
// rendering page-by-page so we can see exactly where pdfrx/pdfium dies.
//
// Usage:
//   ./build/macos/Build/Products/Debug/picture_book.app/Contents/MacOS/picture_book \
//     --probe-pdf=/path/to/file.pdf
//
// Wired into main.dart; this file documents the intent.
import 'dart:io';

void main() {
  stderr.writeln('Run via the macOS app binary with --probe-pdf=PATH');
  exit(2);
}
