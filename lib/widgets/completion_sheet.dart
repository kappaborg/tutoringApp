import 'package:flutter/material.dart';

/// Celebration shown when a kid finishes the last page of a book.
class CompletionSheet extends StatelessWidget {
  const CompletionSheet({
    super.key,
    required this.bookTitle,
    required this.onClose,
    this.onReadAgain,
  });
  final String bookTitle;
  final VoidCallback onClose;
  final VoidCallback? onReadAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.celebration_outlined,
                size: 48,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '🎉 You finished it!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              bookTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.outline,
                  ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onReadAgain != null)
                  OutlinedButton.icon(
                    onPressed: onReadAgain,
                    icon: const Icon(Icons.replay),
                    label: const Text('Read again'),
                  ),
                FilledButton(
                  onPressed: onClose,
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
