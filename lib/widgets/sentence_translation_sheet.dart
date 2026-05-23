import 'package:flutter/material.dart';

/// Bottom sheet (mobile) / dialog (wide) shown when the user taps a sentence
/// in Sentence Mode. The English text is selectable; the Chinese text is
/// loaded asynchronously and rendered as soon as it resolves.
class SentenceTranslationSheet extends StatelessWidget {
  const SentenceTranslationSheet({
    super.key,
    required this.english,
    required this.chineseFuture,
    required this.onSpeakAgain,
    this.onEdit,
    this.teacherUnlocked = false,
  });

  final String english;
  final Future<String> chineseFuture;
  final VoidCallback onSpeakAgain;
  final VoidCallback? onEdit;
  final bool teacherUnlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sentence translation', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            SelectableText(
              english,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: chineseFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final chinese = (snap.data ?? '').trim();
                if (chinese.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No translation recorded for this sentence.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (teacherUnlocked && onEdit != null) ...[
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: onEdit,
                            icon: const Icon(Icons.add),
                            label: const Text('Add translation'),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    chinese,
                    style: theme.textTheme.titleMedium,
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onSpeakAgain,
              icon: const Icon(Icons.volume_up),
              label: const Text('Speak again'),
            ),
          ],
        ),
      ),
    );
  }
}
