import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../services/seed_baker_service.dart';

/// Modal progress dialog for the macOS-only "Bake seed library" admin action.
/// Drives off a [ValueListenable] so the seed-baker doesn't need a reference
/// to the widget tree.
class BakeDialog extends StatelessWidget {
  const BakeDialog({super.key, required this.progress});

  final ValueListenable<BakeProgress> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Baking seed library'),
      content: ValueListenableBuilder<BakeProgress>(
        valueListenable: progress,
        builder: (_, value, __) {
          final ratio = value.total == 0 ? 0.0 : value.done / value.total;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: ratio),
              const SizedBox(height: 12),
              Text('${value.done} of ${value.total}'),
              const SizedBox(height: 4),
              Text(
                value.currentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          );
        },
      ),
    );
  }
}
