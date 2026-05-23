import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/backup_service.dart';
import '../services/log_service.dart';
import '../services/prefs_service.dart';
import '../services/tts_service.dart';
import '../state/admin_auth.dart';
import '../state/library_notifier.dart';
import '../state/locale_notifier.dart';
import '../state/settings_notifier.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backup = BackupService();

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final settings = context.watch<SettingsNotifier>();
    final tts = context.watch<TtsService>();
    final prefs = context.watch<PrefsService>();

    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _ReadingStatsCard(prefs: prefs),
          const _SectionHeader(label: 'Reading mode'),
          RadioGroup<ReadingMode>(
            groupValue: settings.readingMode,
            onChanged: (m) {
              if (m != null) settings.setReadingMode(m);
            },
            child: const Column(
              children: [
                RadioListTile<ReadingMode>(
                  title: Text('Word by word'),
                  subtitle: Text('Tap a word to hear it and see its meaning.'),
                  value: ReadingMode.word,
                ),
                RadioListTile<ReadingMode>(
                  title: Text('Whole sentence'),
                  subtitle: Text(
                    'Tap anywhere on the sentence to hear it and see its translation.',
                  ),
                  value: ReadingMode.sentence,
                ),
              ],
            ),
          ),
          if (settings.readingMode == ReadingMode.word)
            SwitchListTile(
              title: const Text('Speak word when tapped'),
              subtitle: const Text(
                'Tapping a word in the reader also reads it out.',
              ),
              value: settings.tapAlsoSpeaks,
              onChanged: settings.setTapAlsoSpeaks,
            ),
          SwitchListTile(
            title: const Text('Dyslexia-friendly font'),
            subtitle: const Text(
              'Switches the reader sentence to OpenDyslexic if installed in assets/fonts.',
            ),
            value: settings.dyslexiaFont,
            onChanged: settings.setDyslexiaFont,
          ),
          const _SectionHeader(label: 'Language'),
          const _LanguagePicker(),
          const _SectionHeader(label: 'Theme'),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (m) {
              if (m != null) settings.setThemeMode(m);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('System'),
                  value: ThemeMode.system,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Light'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Dark'),
                  value: ThemeMode.dark,
                ),
              ],
            ),
          ),
          const _SectionHeader(label: 'Speech'),
          ListTile(
            title: const Text('Speech rate'),
            subtitle: Slider(
              value: prefs.ttsRate,
              min: 0.2,
              max: 1.0,
              divisions: 16,
              label: prefs.ttsRate.toStringAsFixed(2),
              onChanged: (v) async {
                await tts.setRate(v);
                setState(() {});
              },
            ),
          ),
          ListTile(
            title: const Text('Pitch'),
            subtitle: Slider(
              value: prefs.ttsPitch,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              label: prefs.ttsPitch.toStringAsFixed(2),
              onChanged: (v) async {
                await tts.setPitch(v);
                setState(() {});
              },
            ),
          ),
          _VoicePicker(tts: tts, prefs: prefs),
          const _SectionHeader(label: 'Teacher PIN'),
          ListTile(
            title: Text(prefs.hasPin ? 'Change PIN' : 'Set PIN'),
            leading: const Icon(Icons.lock_outline),
            onTap: () => _changePin(context),
          ),
          ListTile(
            title: const Text('Reset PIN'),
            subtitle: const Text(
              'You must export a backup first. PIN reset cannot be undone.',
            ),
            leading: const Icon(Icons.lock_reset),
            onTap: () => _resetPin(context),
          ),
          const _SectionHeader(label: 'Data'),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(t.exportBackup),
            subtitle: const Text('Saves DB + images to a ZIP you can share.'),
            onTap: _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: Text(t.importBackup),
            subtitle: const Text('Replaces local data with a ZIP backup.'),
            onTap: _importBackup,
          ),
          const _SectionHeader(label: 'About'),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(t.verifiedOffline),
            subtitle: const Text(
              'No outbound network calls. See README → Airplane-mode verification.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Picture Book'),
            subtitle: const Text('Version, license, credits.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/about'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePin(BuildContext context) async {
    final prefs = context.read<PrefsService>();
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(prefs.hasPin ? 'New PIN' : 'Set Teacher PIN'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().length >= 4 && ctrl.text.trim().length <= 6) {
      await prefs.setPin(ctrl.text.trim());
      messenger.showSnackBar(const SnackBar(content: Text('PIN updated.')));
    }
  }

  Future<void> _resetPin(BuildContext context) async {
    final prefs = context.read<PrefsService>();
    final auth = context.read<AdminAuth>();
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final didBackup = await _exportBackup();
    if (!didBackup || !context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reset PIN?'),
        content: const Text(
          'This removes the current Teacher PIN. You can set a new one the next '
          'time you open Admin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await prefs.clearPin();
    auth.lock();
    messenger.showSnackBar(const SnackBar(content: Text('PIN reset.')));
  }

  Future<bool> _exportBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup ZIP',
        fileName: 'picturebook_backup.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (path == null) return false;
      final dest = path.endsWith('.zip') ? path : '$path.zip';
      await _backup.exportToZip(dest);
      messenger.showSnackBar(SnackBar(content: Text('Backup saved to $dest')));
      return true;
    } catch (e, st) {
      LogService.instance.error('Export backup failed', e, st);
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      return false;
    }
  }

  Future<void> _importBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    final library = context.read<LibraryNotifier>();
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final preview = await _backup.previewZip(path);
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Restore backup?'),
          content: Text(
            'This will replace ALL your current books and images.\n\n'
            'Backup contains:\n'
            '• Schema version: ${preview.schemaVersion}\n'
            '• Images: ${preview.imageCount}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: errorColor),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      final summary = await _backup.importFromZip(path);
      await library.loadAll();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Restored: ${summary.bookCount} books, '
            '${summary.pageCount} pages, ${summary.imageCount} images.',
          ),
        ),
      );
    } catch (e, st) {
      LogService.instance.error('Import backup failed', e, st);
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker();

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<LocaleNotifier>();
    final currentCode = notifier.locale?.languageCode;
    return RadioGroup<String?>(
      groupValue: currentCode,
      onChanged: (v) => notifier.setLocaleCode(v),
      child: const Column(
        children: [
          RadioListTile<String?>(
            title: Text('Follow system'),
            value: null,
          ),
          RadioListTile<String?>(
            title: Text('English'),
            value: 'en',
          ),
          RadioListTile<String?>(
            title: Text('中文'),
            value: 'zh',
          ),
        ],
      ),
    );
  }
}

class _ReadingStatsCard extends StatelessWidget {
  const _ReadingStatsCard({required this.prefs});
  final PrefsService prefs;

  @override
  Widget build(BuildContext context) {
    final pages = prefs.statTotal('pages', days: 7);
    final books = prefs.statTotal('books', days: 7);
    if (pages == 0 && books == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.local_fire_department, color: scheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This week',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$pages page${pages == 1 ? '' : 's'} read'
                    '${books > 0 ? '  ·  $books book${books == 1 ? '' : 's'} finished' : ''}',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _VoicePicker extends StatelessWidget {
  const _VoicePicker({required this.tts, required this.prefs});
  final TtsService tts;
  final PrefsService prefs;

  @override
  Widget build(BuildContext context) {
    final voices = tts.voices;
    if (voices.isEmpty) {
      return ListTile(
        leading: const Icon(Icons.record_voice_over_outlined),
        title: const Text('Voice'),
        subtitle: const Text('No offline voices reported by the OS.'),
        trailing: const Icon(Icons.help_outline),
        onTap: () => _showVoiceHelpDialog(context),
      );
    }
    final saved = prefs.ttsVoiceName;
    final currentVoice = voices.firstWhere(
      (v) => v['name'] == saved,
      orElse: () => const <String, String>{},
    );
    final qualityBadge = _qualityOf(currentVoice);
    return ListTile(
      leading: const Icon(Icons.record_voice_over_outlined),
      title: const Text('Voice'),
      subtitle: Text(
        saved == null
            ? 'System default'
            : qualityBadge.isEmpty
                ? saved
                : '$saved · ${qualityBadge.toUpperCase()}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await showDialog<void>(
          context: context,
          builder: (_) => _VoicePickerDialog(tts: tts, prefs: prefs),
        );
      },
    );
  }
}

/// Quality token for a voice (premium / enhanced / default / empty).
String _qualityOf(Map<String, String> voice) {
  // flutter_tts on iOS/macOS surfaces quality as one of "Premium",
  // "Enhanced", "Default". Some versions pack it into the name instead
  // (e.g. "Ava (Premium)"). We accept both.
  final q = (voice['quality'] ?? '').toLowerCase();
  if (q.isNotEmpty) return q;
  final blob = (voice['name'] ?? '').toLowerCase();
  if (blob.contains('premium')) return 'premium';
  if (blob.contains('enhanced')) return 'enhanced';
  return '';
}

int _qualityRank(Map<String, String> voice) {
  switch (_qualityOf(voice)) {
    case 'premium':
      return 0;
    case 'enhanced':
      return 1;
    default:
      return 2;
  }
}

class _VoicePickerDialog extends StatefulWidget {
  const _VoicePickerDialog({required this.tts, required this.prefs});
  final TtsService tts;
  final PrefsService prefs;

  @override
  State<_VoicePickerDialog> createState() => _VoicePickerDialogState();
}

class _VoicePickerDialogState extends State<_VoicePickerDialog> {
  static const _sample =
      'Hello! This is a sample of how the voice will sound when reading a book.';

  Map<String, String>? _previewing;

  @override
  void dispose() {
    // Stop any in-flight preview so it doesn't keep speaking after the
    // dialog closes.
    widget.tts.stop();
    super.dispose();
  }

  Future<void> _previewVoice(Map<String, String>? voice) async {
    setState(() => _previewing = voice);
    await widget.tts.stop();
    if (voice == null) {
      await widget.prefs.setTtsVoice(null, null);
    } else {
      await widget.tts.setVoice(voice);
    }
    await widget.tts.speakSentence(_sample);
  }

  @override
  Widget build(BuildContext context) {
    final voices = List<Map<String, String>>.from(widget.tts.voices);
    voices.sort((a, b) {
      final qa = _qualityRank(a);
      final qb = _qualityRank(b);
      if (qa != qb) return qa - qb;
      final la = (a['locale'] ?? '').compareTo(b['locale'] ?? '');
      if (la != 0) return la;
      return (a['name'] ?? '').compareTo(b['name'] ?? '');
    });
    final saved = widget.prefs.ttsVoiceName;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pick a voice',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline),
                    tooltip: 'How to install Premium voices',
                    onPressed: () => _showVoiceHelpDialog(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  _VoiceRow(
                    title: 'System default',
                    subtitle: null,
                    quality: '',
                    isSelected: saved == null,
                    isPreviewing: _previewing == null,
                    onTap: () => _previewVoice(null),
                  ),
                  for (final v in voices)
                    _VoiceRow(
                      title: v['name'] ?? '',
                      subtitle: v['locale'],
                      quality: _qualityOf(v),
                      isSelected: v['name'] == saved,
                      isPreviewing:
                          _previewing != null && _previewing!['name'] == v['name'],
                      onTap: () => _previewVoice(v),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tap a voice to preview and use it.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.title,
    required this.subtitle,
    required this.quality,
    required this.isSelected,
    required this.isPreviewing,
    required this.onTap,
  });
  final String title;
  final String? subtitle;
  final String quality;
  final bool isSelected;
  final bool isPreviewing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: isSelected
          ? Icon(Icons.check_circle, color: scheme.primary)
          : const Icon(Icons.circle_outlined),
      title: Row(
        children: [
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
          if (quality.isNotEmpty) ...[
            const SizedBox(width: 8),
            _QualityBadge(quality: quality),
          ],
        ],
      ),
      subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!),
      trailing: isPreviewing
          ? Icon(Icons.graphic_eq, color: scheme.primary)
          : const Icon(Icons.play_arrow),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.quality});
  final String quality;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (quality) {
      'premium' => scheme.primary,
      'enhanced' => scheme.tertiary,
      _ => scheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        quality.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

Future<void> _showVoiceHelpDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Get a better-sounding voice'),
      content: const SingleChildScrollView(
        child: Text(
          'The reader uses the system text-to-speech voice. Most operating '
          'systems ship a basic voice by default and let you download a '
          'higher-quality "Premium" or "Natural" voice for free.\n\n'
          'iPhone / iPad:\n'
          '  Settings → Accessibility → Spoken Content → Voices → English\n'
          '  Tap a voice tagged Premium or Enhanced, then tap the cloud icon\n'
          '  to download (~100–400 MB once).\n\n'
          'Mac:\n'
          '  System Settings → Accessibility → Spoken Content →\n'
          '  System Voice → Manage Voices → English → pick Premium → download.\n\n'
          'Windows 11:\n'
          '  Settings → Time & language → Speech → Manage voices →\n'
          '  Add voices → pick one labeled "Natural" (e.g. Aria Natural).\n\n'
          'Android:\n'
          '  Settings → System → Languages & input → Text-to-speech\n'
          '  → Google → Install voice data → English → high quality.\n\n'
          'After downloading, come back here and tap the new voice in the\n'
          'picker — it will show a PREMIUM or ENHANCED badge.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
