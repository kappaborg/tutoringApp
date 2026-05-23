import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class MissingImagePlaceholder extends StatelessWidget {
  const MissingImagePlaceholder({super.key, this.onOpenAdmin});
  final VoidCallback? onOpenAdmin;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(t.imageMissing, textAlign: TextAlign.center),
            if (onOpenAdmin != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onOpenAdmin,
                child: Text(t.admin),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
