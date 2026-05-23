import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/word_meaning.dart';
import '../repositories/page_repository.dart';
import '../repositories/word_repository.dart';
import '../services/image_storage_service.dart';
import '../services/log_service.dart';
import '../services/translation_lookup.dart';
import '../utils/tokenizer.dart';

class PageEditorArgs {
  PageEditorArgs({required this.bookId, this.pageId, this.focusWord});
  final int bookId;
  final int? pageId;
  final String? focusWord;

  factory PageEditorArgs.fromMap(Map<String, Object?> map) {
    final bookId = map['bookId'] as int?;
    if (bookId == null) throw ArgumentError('bookId is required');
    return PageEditorArgs(
      bookId: bookId,
      pageId: map['pageId'] as int?,
      focusWord: map['focusWord'] as String?,
    );
  }
}

class PageEditorScreen extends StatefulWidget {
  const PageEditorScreen({super.key, required this.args});
  final PageEditorArgs args;

  @override
  State<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends State<PageEditorScreen> {
  final _pageRepo = PageRepository();
  final _wordRepo = WordRepository();
  final _sentenceCtrl = TextEditingController();
  final _translationCtrl = TextEditingController();
  final _imageStorage = ImageStorageService();
  final _wordRowKeys = <String, GlobalKey>{};

  String? _imageRelPath;
  final List<_WordRow> _rows = [];
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.args.pageId != null) {
      final page = await _pageRepo.findById(widget.args.pageId!);
      if (page != null) {
        _imageRelPath = page.imagePath;
        _sentenceCtrl.text = page.sentenceText;
        _translationCtrl.text = page.chineseTranslation;
        final words = await _wordRepo.listByPage(page.id!);
        _rows.addAll(words.map(_WordRow.fromMeaning));
      }
    }
    if (mounted) setState(() => _loading = false);
    if (widget.args.focusWord != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureRowForFocus(widget.args.focusWord!);
      });
    }
  }

  void _ensureRowForFocus(String word) {
    final key = word.toLowerCase();
    final exists = _rows.any((r) => r.word.text.trim().toLowerCase() == key);
    if (!exists) {
      setState(() {
        _rows.add(_WordRow.empty()..word.text = key);
        _dirty = true;
      });
    }
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      final ctxKey = _wordRowKeys[key];
      if (ctxKey?.currentContext != null) {
        Scrollable.ensureVisible(
          ctxKey!.currentContext!,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  @override
  void dispose() {
    _sentenceCtrl.dispose();
    _translationCtrl.dispose();
    for (final r in _rows) {
      r.word.dispose();
      r.chinese.dispose();
      r.english.dispose();
      r.tts.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final path = await _imageStorage.pickAndStore();
      if (path != null) {
        setState(() {
          _imageRelPath = path;
          _dirty = true;
        });
      }
    } catch (e, st) {
      LogService.instance.error('Pick image failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import image: $e')),
        );
      }
    }
  }

  void _addRow() {
    setState(() {
      _rows.add(_WordRow.empty());
      _dirty = true;
    });
  }

  void _removeRow(int index) {
    setState(() {
      final row = _rows.removeAt(index);
      row.word.dispose();
      row.chinese.dispose();
      row.english.dispose();
      row.tts.dispose();
      _dirty = true;
    });
  }

  void _autoFillWords() {
    final words = Tokenizer.uniqueWords(_sentenceCtrl.text);
    final existing = _rows
        .map((r) => r.word.text.trim().toLowerCase())
        .where((w) => w.isNotEmpty)
        .toSet();
    setState(() {
      for (final w in words) {
        if (!existing.contains(w)) {
          _rows.add(_WordRow.empty()..word.text = w);
        }
      }
      _dirty = true;
    });
  }

  Future<void> _autoFillTranslations() async {
    final lookup = context.read<TranslationLookup>();
    final messenger = ScaffoldMessenger.of(context);
    final keysNeeded = <String>{};
    for (final r in _rows) {
      final key = r.word.text.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (r.chinese.text.trim().isEmpty || r.english.text.trim().isEmpty) {
        keysNeeded.add(key);
      }
    }
    if (keysNeeded.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Every row already has translations.')),
      );
      return;
    }
    final results = await lookup.resolveMany(keysNeeded);
    if (!mounted) return;
    setState(() {
      for (final r in _rows) {
        final key = r.word.text.trim().toLowerCase();
        final entry = results[key];
        if (entry == null) continue;
        if (r.chinese.text.trim().isEmpty) r.chinese.text = entry.chinese;
        if (r.english.text.trim().isEmpty) r.english.text = entry.definition;
        r.source = WordSource.dictionary;
      }
      _dirty = true;
    });
    final hits = results.length;
    messenger.showSnackBar(
      SnackBar(content: Text('Filled $hits / ${keysNeeded.length} rows from dictionary.')),
    );
  }

  String? _validate() {
    if (_imageRelPath == null) return 'Please pick an image.';
    if (_sentenceCtrl.text.trim().isEmpty) return 'Please enter a sentence.';
    final keys = <String>{};
    for (final row in _rows) {
      final w = row.word.text.trim().toLowerCase();
      if (w.isEmpty) return 'Each word row must have a word.';
      if (!keys.add(w)) return 'Duplicate word "$w". Words must be unique per page.';
      if (row.chinese.text.trim().isEmpty) {
        return 'Missing Chinese meaning for "$w".';
      }
      if (row.english.text.trim().isEmpty) {
        return 'Missing English definition for "$w".';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _saving = true);
    try {
      final words = _rows
          .map(
            (r) => WordMeaning(
              id: r.id,
              pageId: widget.args.pageId ?? -1,
              word: r.word.text.trim().toLowerCase(),
              chineseMeaning: r.chinese.text.trim(),
              englishDefinition: r.english.text.trim(),
              ttsOverride:
                  r.tts.text.trim().isEmpty ? null : r.tts.text.trim(),
              source: r.source,
            ),
          )
          .toList();

      if (widget.args.pageId == null) {
        final pageId = await _pageRepo.create(
          bookId: widget.args.bookId,
          imagePath: _imageRelPath!,
          sentenceText: _sentenceCtrl.text.trim(),
          chineseTranslation: _translationCtrl.text.trim(),
        );
        await _wordRepo.replaceForPage(
          pageId,
          words.map((w) => w.copyWith(pageId: pageId)).toList(),
        );
      } else {
        final orphan = await _pageRepo.update(
          id: widget.args.pageId!,
          imagePath: _imageRelPath!,
          sentenceText: _sentenceCtrl.text.trim(),
          chineseTranslation: _translationCtrl.text.trim(),
        );
        if (orphan != null) {
          await _imageStorage.deleteIfExists(orphan);
        }
        await _wordRepo.replaceForPage(widget.args.pageId!, words);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e, st) {
      LogService.instance.error('Save page failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final t = AppStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Leave anyway?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return yes == true;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) navigator.pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.args.pageId == null ? 'New page' : 'Edit page'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(
                t.save,
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ],
        ),
        body: Form(
          onChanged: () {
            if (!_dirty) setState(() => _dirty = true);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ImagePickerCard(
                relativePath: _imageRelPath,
                imageStorage: _imageStorage,
                onPick: _pickImage,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _sentenceCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Sentence (English)',
                  hintText: 'e.g. The cat sleeps on the mat.',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _translationCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Chinese translation (whole sentence)',
                  hintText: '可选 — 用于"整句模式"。',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _autoFillWords,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Auto-fill words from sentence'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _autoFillTranslations,
                    icon: const Icon(Icons.translate),
                    label: const Text('Auto-fill translations from dictionary'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                    label: const Text('Add word'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WordRowCard(
                    key: _keyFor(_rows[i].word.text.trim().toLowerCase()),
                    row: _rows[i],
                    onRemove: () => _removeRow(i),
                  ),
                ),
              if (_rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Tap "Auto-fill words from sentence" to start, '
                    'or add rows manually.',
                  ),
                ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  GlobalKey _keyFor(String word) =>
      _wordRowKeys.putIfAbsent(word, () => GlobalKey());
}

class _ImagePickerCard extends StatelessWidget {
  const _ImagePickerCard({
    required this.relativePath,
    required this.imageStorage,
    required this.onPick,
  });
  final String? relativePath;
  final ImageStorageService imageStorage;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: relativePath == null
                  ? const _PickPlaceholder()
                  : FutureBuilder<File>(
                      future: imageStorage.resolve(relativePath!),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(snap.data!, fit: BoxFit.cover),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(relativePath == null ? 'Pick image' : 'Replace image'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickPlaceholder extends StatelessWidget {
  const _PickPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 56),
            SizedBox(height: 8),
            Text('Tap "Pick image" to choose one.'),
          ],
        ),
      ),
    );
  }
}

class _WordRowCard extends StatelessWidget {
  const _WordRowCard({super.key, required this.row, required this.onRemove});
  final _WordRow row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: row.word,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Word (English, lowercase)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SourceBadge(source: row.source),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove row',
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.chinese,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Chinese meaning',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.english,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'English definition',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: row.tts,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Pronunciation override (optional)',
                helperText: 'Phonetic respelling for TTS, e.g. "kə-RAJ" for "courage".',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordRow {
  _WordRow({this.id, this.source = WordSource.manual});
  final int? id;
  WordSource source;
  final TextEditingController word = TextEditingController();
  final TextEditingController chinese = TextEditingController();
  final TextEditingController english = TextEditingController();
  final TextEditingController tts = TextEditingController();

  factory _WordRow.empty() => _WordRow();

  factory _WordRow.fromMeaning(WordMeaning m) {
    final r = _WordRow(id: m.id, source: m.source);
    r.word.text = m.word;
    r.chinese.text = m.chineseMeaning;
    r.english.text = m.englishDefinition;
    if (m.ttsOverride != null) r.tts.text = m.ttsOverride!;
    return r;
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final WordSource source;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      WordSource.manual => ('manual', Theme.of(context).colorScheme.outline),
      WordSource.dictionary =>
        ('dict', Theme.of(context).colorScheme.tertiary),
      WordSource.pdf => ('pdf', Theme.of(context).colorScheme.secondary),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
