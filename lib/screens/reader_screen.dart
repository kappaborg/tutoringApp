import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/page.dart';
import '../models/word_meaning.dart';
import '../repositories/word_repository.dart';
import '../services/dictionary_service.dart';
import '../services/image_storage_service.dart';
import '../services/log_service.dart';
import '../services/prefs_service.dart';
import '../services/translation_lookup.dart';
import '../services/tts_service.dart';
import '../services/word_examples_service.dart';
import '../state/admin_auth.dart';
import '../state/library_notifier.dart';
import '../state/settings_notifier.dart';
import '../utils/sentence_splitter.dart';
import '../utils/tokenizer.dart';
import '../widgets/book_dropdown.dart';
import '../widgets/completion_sheet.dart';
import '../widgets/missing_image_placeholder.dart';
import '../widgets/reader_toolbar.dart';
import '../widgets/reading_progress_dots.dart';
import '../widgets/sentence_translation_sheet.dart';
import '../widgets/word_meaning_sheet.dart';
import '../widgets/word_span.dart';
import 'pin_gate_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  final Map<int, List<String>> _sentencesByPageId = {};

  List<String> _sentencesForPage(BookPage page) {
    final id = page.id;
    if (id == null) return splitIntoSentences(page.sentenceText);
    return _sentencesByPageId.putIfAbsent(
      id,
      () => splitIntoSentences(page.sentenceText),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<LibraryNotifier>().loadAll();
      _maybeShowVoiceTip();
      _precacheAdjacent();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(context.read<TtsService>().stop());
      context.read<AdminAuth>().lock();
    }
  }

  Future<void> _maybeShowVoiceTip() async {
    final prefs = context.read<PrefsService>();
    if (prefs.voiceWarningShown) return;
    final tts = context.read<TtsService>();
    if (tts.availability != TtsAvailability.noVoice) return;
    if (!mounted) return;
    final msg = Platform.isIOS || Platform.isMacOS
        ? 'No offline voice detected. Install one in Settings → Accessibility → Spoken Content.'
        : Platform.isWindows
            ? 'No SAPI voice detected. Install a voice via Windows Settings → Time & language → Speech.'
            : 'No offline TTS voice detected. Install one in your system settings.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
    );
    await prefs.setVoiceWarningShown(true);
  }

  Future<void> _precacheAdjacent() async {
    final lib = context.read<LibraryNotifier>();
    final imageStorage = context.read<ImageStorageService>();
    final pages = lib.pages;
    final idx = lib.pageIndex;
    for (final i in [idx - 1, idx + 1]) {
      if (i < 0 || i >= pages.length) continue;
      final file = await imageStorage.resolve(pages[i].imagePath);
      if (await file.exists() && mounted) {
        unawaited(precacheImage(FileImage(file), context));
      }
    }
  }

  Future<void> _openAdmin() async {
    final auth = context.read<AdminAuth>();
    if (!auth.isUnlocked) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PinGateScreen()),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    await Navigator.of(context).pushNamed('/admin');
    if (!mounted) return;
    await context.read<LibraryNotifier>().reloadCurrentBook();
  }

  // ── Word-mode word tap ─────────────────────────────────────────────────
  Future<void> _onWordTap(Token token) async {
    final lib = context.read<LibraryNotifier>();
    final tts = context.read<TtsService>();
    final settings = context.read<SettingsNotifier>();
    final auth = context.read<AdminAuth>();
    final lookup = context.read<TranslationLookup>();
    final wordRepo = context.read<WordRepository>();
    final examples = context.read<WordExamplesService>();
    final isWide = MediaQuery.of(context).size.width >= 600;
    final meaning = lib.wordsByKey[token.lookupKey];

    if (settings.tapAlsoSpeaks) {
      unawaited(tts.speakWord(token.lookupKey, override: meaning?.ttsOverride));
    }

    DictionaryEntry? dict;
    if (meaning == null) {
      dict = await lookup.resolve(token.lookupKey);
    }

    final pageId = lib.currentPage?.id;
    final examplesFuture = examples.findExamples(
      token.lookupKey,
      excludePageId: pageId,
    );

    Future<void> saveFromDictionary() async {
      final entry = dict;
      if (entry == null || pageId == null) return;
      await wordRepo.insert(
        WordMeaning(
          id: null,
          pageId: pageId,
          word: token.lookupKey,
          chineseMeaning: entry.chinese,
          englishDefinition: entry.definition,
          source: WordSource.dictionary,
        ),
      );
      if (mounted) {
        await context.read<LibraryNotifier>().reloadCurrentBook();
      }
    }

    void openExample(WordExample example) {
      final navigator = Navigator.of(context);
      final library = context.read<LibraryNotifier>();
      navigator.pop();
      if (example.bookId != null && example.pageNumber != null) {
        library.openBookPage(example.bookId!, example.pageNumber!);
      }
    }

    final fontFamily = settings.dyslexiaFont ? 'OpenDyslexic' : null;

    final sheet = WordMeaningSheet(
      word: token.display,
      meaning: meaning,
      dictionaryEntry: dict,
      examplesFuture: examplesFuture,
      onSpeak: () =>
          tts.speakWord(token.lookupKey, override: meaning?.ttsOverride),
      onEdit: auth.isUnlocked
          ? () async {
              Navigator.of(context).pop();
              if (pageId == null) return;
              await Navigator.of(context).pushNamed(
                '/admin/page-editor',
                arguments: <String, Object?>{
                  'pageId': pageId,
                  'bookId': lib.currentBook?.id,
                  'focusWord': token.lookupKey,
                },
              );
              if (mounted) {
                await context.read<LibraryNotifier>().reloadCurrentBook();
              }
            }
          : null,
      onSaveDictionaryEntry: (auth.isUnlocked && dict != null && pageId != null)
          ? () async {
              Navigator.of(context).pop();
              await saveFromDictionary();
            }
          : null,
      onOpenExample: openExample,
      fontFamily: fontFamily,
    );

    if (!mounted) return;
    if (isWide) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: sheet,
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => sheet,
      );
    }
  }

  // ── Sentence-mode tap ──────────────────────────────────────────────────
  Future<void> _onSentenceTap(
    BookPage page,
    String sentence,
    int totalSentencesOnPage,
  ) async {
    final tts = context.read<TtsService>();
    final auth = context.read<AdminAuth>();
    final lookup = context.read<TranslationLookup>();
    final isWide = MediaQuery.of(context).size.width >= 600;

    await tts.stop();
    unawaited(tts.speakSentence(sentence));

    Future<void> openEditor() async {
      Navigator.of(context).pop();
      await Navigator.of(context).pushNamed(
        '/admin/page-editor',
        arguments: <String, Object?>{
          'pageId': page.id,
          'bookId': page.bookId,
        },
      );
      if (mounted) {
        await context.read<LibraryNotifier>().reloadCurrentBook();
      }
    }

    // Prefer the hand-curated whole-page translation only when the page has
    // exactly one sentence — otherwise compute per-sentence on demand.
    final Future<String> chineseFuture;
    if (totalSentencesOnPage == 1 && page.chineseTranslation.trim().isNotEmpty) {
      chineseFuture = Future.value(page.chineseTranslation);
    } else {
      chineseFuture = lookup.chineseForSentence(sentence);
    }

    final sheet = SentenceTranslationSheet(
      english: sentence,
      chineseFuture: chineseFuture,
      teacherUnlocked: auth.isUnlocked,
      onSpeakAgain: () => tts.speakSentence(sentence),
      onEdit: auth.isUnlocked ? openEditor : null,
    );

    if (!mounted) return;
    if (isWide) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: sheet,
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => sheet,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final lib = context.watch<LibraryNotifier>();
    final tts = context.watch<TtsService>();
    final settings = context.watch<SettingsNotifier>();
    final font = settings.dyslexiaFont ? 'OpenDyslexic' : null;

    return Scaffold(
      appBar: AppBar(
        title: lib.books.isEmpty
            ? Text(t.appTitle)
            : BookDropdown(
                books: lib.books,
                current: lib.currentBook,
                onChanged: (b) async {
                  final ttsLocal = context.read<TtsService>();
                  final library = context.read<LibraryNotifier>();
                  await ttsLocal.stop();
                  await library.selectBook(b);
                  _precacheAdjacent();
                },
              ),
        actions: [
          IconButton(
            tooltip: t.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
          IconButton(
            tooltip: t.admin,
            icon: const Icon(Icons.school_outlined),
            onPressed: _openAdmin,
          ),
        ],
      ),
      body: _buildBody(context, lib, tts, settings, font),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryNotifier lib,
    TtsService tts,
    SettingsNotifier settings,
    String? fontFamily,
  ) {
    final t = AppStrings.of(context);
    if (lib.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (lib.books.isEmpty) {
      return _EmptyState(onAdmin: _openAdmin);
    }
    final page = lib.currentPage;
    if (page == null) {
      return _EmptyPagesState(onAdmin: _openAdmin);
    }
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          // Cap the sentence area to ~55% of the available height; the image
          // takes the remainder via Expanded. With this layout the image
          // always gets ≥ 35 % (room for the nav bar + sentence max).
          final sentenceMaxH = (h * 0.55).clamp(160.0, 720.0);
          return Column(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) =>
                      _onPageSwipe(details.primaryVelocity ?? 0),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _PageImage(page: page),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: sentenceMaxH),
                child: Builder(
                  builder: (context) {
                    final sentences = _sentencesForPage(page);
                    return _SentenceArea(
                      page: page,
                      sentences: sentences,
                      wordsByKey: lib.wordsByKey,
                      tts: tts,
                      fontFamily: fontFamily,
                      mode: settings.readingMode,
                      onWordTap: _onWordTap,
                      onSentenceTap: (s) =>
                          _onSentenceTap(page, s, sentences.length),
                    );
                  },
                ),
              ),
              const ReaderToolbar(),
              ReadingProgressDots(
                pageCount: lib.pages.length,
                currentIndex: lib.pageIndex,
              ),
              _NavBar(
                currentLabel: t.pageOf(lib.pageIndex + 1, lib.pages.length),
                canPrev: lib.pageIndex > 0,
                canNext: lib.pageIndex < lib.pages.length - 1,
                onPrev: () => _changePage(delta: -1),
                onNext: () => _changePage(delta: 1),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _changePage({required int delta}) async {
    final tts = context.read<TtsService>();
    final lib = context.read<LibraryNotifier>();
    final prefs = context.read<PrefsService>();
    final atLastPage = lib.pageIndex >= lib.pages.length - 1;
    final book = lib.currentBook;
    await tts.stop();
    if (delta < 0) {
      await lib.previous();
    } else {
      // Forward press on the last page → completion celebration.
      if (atLastPage && book != null && lib.pages.isNotEmpty) {
        unawaited(prefs.bumpStat('books', DateTime.now()));
        await _showCompletion(book.title);
        return;
      }
      await lib.next();
      unawaited(prefs.bumpStat('pages', DateTime.now()));
    }
    _precacheAdjacent();
  }

  Future<void> _showCompletion(String title) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => CompletionSheet(
        bookTitle: title,
        onClose: () => Navigator.of(sheetCtx).pop(),
        onReadAgain: () async {
          Navigator.of(sheetCtx).pop();
          await context.read<LibraryNotifier>().goToPage(0);
          _precacheAdjacent();
        },
      ),
    );
  }

  Future<void> _onPageSwipe(double velocity) async {
    if (velocity.abs() < 250) return;
    await _changePage(delta: velocity < 0 ? 1 : -1);
  }
}

class _PageImage extends StatefulWidget {
  const _PageImage({required this.page});
  final BookPage page;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  late Future<_ImageResolution> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(_PageImage old) {
    super.didUpdateWidget(old);
    if (old.page.imagePath != widget.page.imagePath) {
      final next = _resolve();
      setState(() {
        _future = next;
      });
    }
  }

  Future<_ImageResolution> _resolve() async {
    try {
      final storage = context.read<ImageStorageService>();
      final file = await storage.resolve(widget.page.imagePath);
      final exists = await file.exists();
      return _ImageResolution(file, exists);
    } catch (e, st) {
      LogService.instance.error(
        'Resolve image failed for ${widget.page.imagePath}',
        e,
        st,
      );
      return _ImageResolution(File(widget.page.imagePath), false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ImageResolution>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final r = snap.data!;
        if (!r.exists) {
          return Center(
            child: MissingImagePlaceholder(
              onOpenAdmin: () => Navigator.of(context).pushNamed('/admin'),
            ),
          );
        }
        // ValueKey ensures Flutter rebuilds the Image widget when the path
        // changes (otherwise it can serve a cached image from the same slot).
        return Image.file(
          r.file,
          key: ValueKey(widget.page.imagePath),
          fit: BoxFit.contain,
        );
      },
    );
  }
}

class _ImageResolution {
  const _ImageResolution(this.file, this.exists);
  final File file;
  final bool exists;
}

class _SentenceArea extends StatelessWidget {
  const _SentenceArea({
    required this.page,
    required this.sentences,
    required this.wordsByKey,
    required this.tts,
    required this.fontFamily,
    required this.mode,
    required this.onWordTap,
    required this.onSentenceTap,
  });
  final BookPage page;
  final List<String> sentences;
  final Map<String, WordMeaning> wordsByKey;
  final TtsService tts;
  final String? fontFamily;
  final ReadingMode mode;
  final ValueChanged<Token> onWordTap;
  final void Function(String sentence) onSentenceTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Tokenizer.tokenize(page.sentenceText);
    final base = Theme.of(context).textTheme.headlineSmall ??
        const TextStyle(fontSize: 22);
    final currentlySpeaking = tts.currentSentence == page.sentenceText &&
        tts.currentStart >= 0;
    final scheme = Theme.of(context).colorScheme;

    if (mode == ReadingMode.sentence) {
      return Material(
        color: scheme.surfaceContainerHighest,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in sentences)
                _SentenceCard(
                  sentence: s,
                  fontFamily: fontFamily,
                  baseStyle: base,
                  isSpeaking: tts.currentSentence == s,
                  onTap: () => onSentenceTap(s),
                ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () async {
          try {
            await tts.speakSentence(page.sentenceText);
          } catch (e, st) {
            LogService.instance.error('Speak sentence failed', e, st);
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tok in tokens)
                WordSpan(
                  token: tok,
                  meaning: wordsByKey[tok.lookupKey],
                  isHighlighted: currentlySpeaking &&
                      tts.currentStart >= tok.charStart &&
                      tts.currentStart < tok.charEnd,
                  fontFamily: fontFamily,
                  baseStyle: base,
                  onTap: () => onWordTap(tok),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SentenceCard extends StatelessWidget {
  const _SentenceCard({
    required this.sentence,
    required this.fontFamily,
    required this.baseStyle,
    required this.isSpeaking,
    required this.onTap,
  });
  final String sentence;
  final String? fontFamily;
  final TextStyle baseStyle;
  final bool isSpeaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isSpeaking
            ? scheme.primaryContainer
            : scheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Semantics(
            button: true,
            label: 'Tap to speak: $sentence',
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Text(
                sentence,
                style: baseStyle.copyWith(fontFamily: fontFamily),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.currentLabel,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });
  final String currentLabel;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FilledButton.tonalIcon(
              onPressed: canPrev ? onPrev : null,
              icon: const Icon(Icons.chevron_left),
              label: Text(t.previous),
            ),
            Text(currentLabel, style: Theme.of(context).textTheme.titleMedium),
            FilledButton.tonalIcon(
              onPressed: canNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              label: Text(t.next),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdmin});
  final Future<void> Function() onAdmin;

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 96),
            const SizedBox(height: 16),
            Text(t.noBooks, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onAdmin(),
              icon: const Icon(Icons.school_outlined),
              label: Text(t.admin),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPagesState extends StatelessWidget {
  const _EmptyPagesState({required this.onAdmin});
  final Future<void> Function() onAdmin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_outlined, size: 96),
            const SizedBox(height: 16),
            const Text('This book has no pages yet.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => onAdmin(),
              icon: const Icon(Icons.add),
              label: const Text('Add pages'),
            ),
          ],
        ),
      ),
    );
  }
}
