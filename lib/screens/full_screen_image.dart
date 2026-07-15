import 'dart:io';

import 'package:flutter/material.dart';

/// Full-screen pinch-to-zoom view of the current page's illustration.
/// Pushed as a route when the kid taps the image; close button in the
/// top-right (or the system back button) returns to the reader.
class FullScreenImageView extends StatelessWidget {
  const FullScreenImageView({
    super.key,
    required this.file,
    required this.heroTag,
  });

  final File file;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              // Tap outside the image area also dismisses, for the "click
              // again to leave" instinct kids have on tablets.
              onTap: () => Navigator.of(context).maybePop(),
              child: Hero(
                tag: heroTag,
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: Center(
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
