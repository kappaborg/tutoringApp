import 'package:flutter/material.dart';

import '../services/seed_service.dart';

/// Shown on first launch while the bundled Oxford library is being unpacked
/// from the app bundle into the local SQLite + image cache. Once
/// [SeedService.progress] flips to `inProgress: false`, the router swaps in
/// the real reader.
class SeedLoadingScreen extends StatelessWidget {
  const SeedLoadingScreen({super.key, required this.progress});

  final SeedProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = progress.total == 0 ? null : progress.done / progress.total;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 64,
                  color: scheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Setting up your library',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'One-time import. This usually takes under a minute.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: LinearProgressIndicator(value: ratio),
                ),
                const SizedBox(height: 12),
                Text(
                  '${progress.done} of ${progress.total}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (progress.currentTitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      progress.currentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
