import 'package:flutter/material.dart';

/// Compact "X / N" dot strip. Up to ~30 dots in a horizontal row before we
/// collapse to a single Text() because dots stop being readable. Highlights
/// the current page.
class ReadingProgressDots extends StatelessWidget {
  const ReadingProgressDots({
    super.key,
    required this.pageCount,
    required this.currentIndex,
  });
  final int pageCount;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    if (pageCount > 30) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            '● ${currentIndex + 1} / $pageCount ●',
            style: TextStyle(
              color: scheme.outline,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < pageCount; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == currentIndex ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i <= currentIndex
                      ? scheme.primary
                      : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
