import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/prefs_service.dart';
import '../services/tts_router.dart';
import '../state/settings_notifier.dart';

/// Compact persistent toolbar shown between the sentence area and the page
/// nav. Three quick controls so the kid (or teacher mid-read) doesn't have to
/// detour through Settings:
///   • Speed slider (TTS rate)
///   • Voice button (opens voice picker as a bottom sheet)
///   • Reading-mode chip (Word ↔ Sentence)
class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PrefsService>();
    final tts = context.watch<TtsRouter>();
    final settings = context.watch<SettingsNotifier>();
    final scheme = Theme.of(context).colorScheme;
    final isSentence = settings.readingMode == ReadingMode.sentence;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Speed (snail → rabbit)
          Icon(Icons.directions_walk, size: 18, color: scheme.outline),
          Expanded(
            child: Slider(
              value: prefs.ttsRate,
              min: 0.2,
              max: 0.9,
              divisions: 14,
              onChanged: (v) async {
                await tts.setRate(v);
                if (context.mounted) (context as Element).markNeedsBuild();
              },
            ),
          ),
          Icon(Icons.directions_run, size: 18, color: scheme.outline),
          const SizedBox(width: 8),
          // Voice picker shortcut
          IconButton(
            tooltip: 'Voice',
            icon: const Icon(Icons.record_voice_over_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
          // Mode chip
          ChoiceChip(
            label: Text(isSentence ? 'Sentence' : 'Word'),
            avatar: Icon(
              isSentence ? Icons.format_quote : Icons.text_fields,
              size: 16,
              color: scheme.onPrimary,
            ),
            selected: true,
            selectedColor: scheme.primary,
            labelStyle: TextStyle(color: scheme.onPrimary),
            showCheckmark: false,
            onSelected: (_) => settings.toggleReadingMode(),
          ),
        ],
      ),
    );
  }
}
