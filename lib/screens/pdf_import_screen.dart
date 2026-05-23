import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/word_meaning.dart';
import '../repositories/book_repository.dart';
import '../repositories/page_repository.dart';
import '../repositories/word_repository.dart';
import '../services/dictionary_service.dart';
import '../services/image_storage_service.dart';
import '../services/log_service.dart';
import '../services/pdf_import_service.dart';
import '../services/translation_lookup.dart';
import '../utils/ocr_sanitizer.dart';
import '../utils/tokenizer.dart';

/// Three-step screen:
///   1. Pick PDF (file_picker).
///   2. Show progress while pages render.
///   3. Review screen — title + per-page sentences (editable) + optional
///      auto-translation toggle. Save commits one Book + N pages + word rows
///      in a single transaction.
class PdfImportScreen extends StatefulWidget {
  const PdfImportScreen({super.key});

  @override
  State<PdfImportScreen> createState() => _PdfImportScreenState();
}

enum _Phase { picking, importing, review, saving }

class _PdfImportScreenState extends State<PdfImportScreen> {
  _Phase _phase = _Phase.picking;
  int _progressDone = 0;
  int _progressTotal = 0;
  PdfImportResult? _result;
  final _titleCtrl = TextEditingController();
  final _sentenceCtrls = <TextEditingController>[];
  bool _autoTranslate = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPick());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _sentenceCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _startPick() async {
    final pdfService = context.read<PdfImportService>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final path = await pdfService.pickPdf();
    if (path == null) {
      if (mounted) navigator.pop(false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.importing;
      _progressDone = 0;
      _progressTotal = 0;
    });
    try {
      final result = await pdfService.importPdf(
        path,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progressDone = done;
            _progressTotal = total;
          });
        },
      );
      if (!mounted) return;
      _titleCtrl.text = result.suggestedTitle;
      _sentenceCtrls
        ..clear()
        ..addAll(result.pages.map((p) => TextEditingController(text: p.sentenceText)));
      setState(() {
        _result = result;
        _phase = _Phase.review;
      });
    } catch (e, st) {
      LogService.instance.error('PDF import failed', e, st);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('PDF import failed: $e')));
      navigator.pop(false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty && _phase != _Phase.review) return true;
    final t = AppStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Discard imported PDF?'),
        content: const Text('Your edits to the sentences will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Book title is required.')),
      );
      return;
    }
    setState(() => _phase = _Phase.saving);

    final bookRepo = context.read<BookRepository>();
    final pageRepo = context.read<PageRepository>();
    final wordRepo = context.read<WordRepository>();
    final lookup = context.read<TranslationLookup>();
    final imageStorage = context.read<ImageStorageService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // 1. Pre-flight: every rendered JPEG must actually exist on disk.
      //    Otherwise we'd persist a book with broken images.
      for (final p in result.pages) {
        final ok = await imageStorage.exists(p.imageRelPath);
        if (!ok) {
          throw FileSystemException(
            'Rendered page image disappeared before save',
            p.imageRelPath,
          );
        }
      }

      // 2. Resolve translations up front so the DB transaction is short.
      Map<String, DictionaryEntry> translations = const {};
      final sentenceTranslations = <int, String>{};
      if (_autoTranslate) {
        final allKeys = <String>{};
        for (var i = 0; i < result.pages.length; i++) {
          final sentence = _sentenceCtrls[i].text;
          allKeys.addAll(Tokenizer.uniqueWords(sentence));
        }
        translations = await lookup.resolveMany(allKeys);
        for (var i = 0; i < result.pages.length; i++) {
          final s = _sentenceCtrls[i].text.trim();
          if (s.isEmpty) continue;
          final placeholder = await lookup.concatenateChineseFromWords(s);
          if (placeholder != null && placeholder.isNotEmpty) {
            sentenceTranslations[i] = placeholder;
          }
        }
      }

      // 3. Write the book + pages + words. If any step throws, the catch
      //    below rolls back by deleting the book (cascade) and the JPEGs.
      final book = await bookRepo.create(title);
      for (var i = 0; i < result.pages.length; i++) {
        final source = result.pages[i];
        final sentence = _sentenceCtrls[i].text.trim();
        final pageId = await pageRepo.create(
          bookId: book.id!,
          imagePath: source.imageRelPath,
          sentenceText: sentence,
          pageNumber: i + 1,
          chineseTranslation: sentenceTranslations[i] ?? '',
        );
        if (sentence.isEmpty || !_autoTranslate) continue;
        final words = <WordMeaning>[];
        for (final key in Tokenizer.uniqueWords(sentence)) {
          final entry = translations[key];
          if (entry == null) continue;
          words.add(
            WordMeaning(
              id: null,
              pageId: pageId,
              word: key,
              chineseMeaning: entry.chinese,
              englishDefinition: entry.definition,
              source: WordSource.pdf,
            ),
          );
        }
        if (words.isNotEmpty) {
          await wordRepo.replaceForPage(pageId, words);
        }
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Imported "$title" — ${result.pageCount} pages.')),
      );
      navigator.pop(true);
    } catch (e, st) {
      LogService.instance.error('PDF save failed', e, st);
      // Best-effort cleanup of the orphan images on failure.
      try {
        await imageStorage
            .deleteMany(result.pages.map((p) => p.imageRelPath));
      } catch (_) {}
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
      setState(() => _phase = _Phase.review);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty || _phase == _Phase.picking,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) navigator.pop(false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import PDF'),
          actions: [
            if (_phase == _Phase.review)
              TextButton(
                onPressed: _save,
                child: Text(
                  AppStrings.of(context).save,
                  style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                ),
              ),
          ],
        ),
        body: switch (_phase) {
          _Phase.picking => const Center(child: CircularProgressIndicator()),
          _Phase.importing => _ImportingView(done: _progressDone, total: _progressTotal),
          _Phase.review => _buildReview(),
          _Phase.saving => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _buildReview() {
    final result = _result!;
    final imageStorage = context.read<ImageStorageService>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _titleCtrl,
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Book title',
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Auto-translate all words'),
          subtitle: const Text(
            'Looks up each English word in the bundled dictionary and saves '
            'Chinese + English definitions to each page.',
          ),
          value: _autoTranslate,
          onChanged: (v) => setState(() => _autoTranslate = v),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < result.pages.length; i++)
          _ReviewPageCard(
            page: result.pages[i],
            controller: _sentenceCtrls[i],
            imageStorage: imageStorage,
            onSentenceChanged: () {
              if (!_dirty) setState(() => _dirty = true);
            },
          ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _ImportingView extends StatelessWidget {
  const _ImportingView({required this.done, required this.total});
  final int done;
  final int total;
  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? null : done / total;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(value: pct),
          ),
          const SizedBox(height: 16),
          Text(total == 0 ? 'Opening PDF…' : 'Rendering page $done / $total'),
        ],
      ),
    );
  }
}

class _ReviewPageCard extends StatelessWidget {
  const _ReviewPageCard({
    required this.page,
    required this.controller,
    required this.imageStorage,
    required this.onSentenceChanged,
  });
  final PdfImportedPage page;
  final TextEditingController controller;
  final ImageStorageService imageStorage;
  final VoidCallback onSentenceChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: FutureBuilder<File>(
                    future: imageStorage.resolve(page.imageRelPath),
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox.shrink();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(snap.data!, fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Page ${page.pageNumber}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (!page.textWasExtracted)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'No text found — type the sentence manually.',
                            style: TextStyle(fontSize: 12),
                          ),
                        )
                      else if (page.sentenceFromOcr)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'OCR — verify before saving',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLines: 3,
                    onChanged: (_) => onSentenceChanged(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Sentence (English)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Trim OCR noise (re-runs the sanitiser on this field)',
                  onPressed: () {
                    final cleaned = sanitizeOcrText(controller.text);
                    controller.text = cleaned;
                    onSentenceChanged();
                  },
                  icon: const Icon(Icons.auto_fix_high),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
