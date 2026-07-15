import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/book.dart';
import '../models/page.dart';
import '../models/word_meaning.dart';
import '../repositories/book_repository.dart';
import '../repositories/page_repository.dart';
import '../repositories/word_repository.dart';
import '../services/book_share_service.dart';
import '../services/image_storage_service.dart';
import '../services/log_service.dart';
import '../services/pdf_import_service.dart';
import '../services/seed_baker_service.dart';
import '../services/translation_lookup.dart';
import '../utils/tokenizer.dart';
import 'admin/bake_dialog.dart';
import 'admin/book_list.dart';
import 'admin/page_list.dart';

/// Two-pane layout on wide screens, single-pane on phones. Manages books on
/// the left and the selected book's pages on the right.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _bookRepo = BookRepository();
  final _pageRepo = PageRepository();
  final _imageStorage = ImageStorageService();
  List<Book> _books = const [];
  Book? _selected;
  List<BookPage> _pages = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({int? selectBookId}) async {
    setState(() => _loading = true);
    final books = await _bookRepo.listAll();
    Book? selected;
    if (selectBookId != null) {
      selected = books.firstWhere(
        (b) => b.id == selectBookId,
        orElse: () => books.isNotEmpty ? books.first : _placeholder,
      );
      if (selected == _placeholder) selected = null;
    } else if (_selected != null) {
      selected = books.firstWhere(
        (b) => b.id == _selected!.id,
        orElse: () => books.isNotEmpty ? books.first : _placeholder,
      );
      if (selected == _placeholder) selected = null;
    } else if (books.isNotEmpty) {
      selected = books.first;
    }
    final pages = selected?.id == null
        ? <BookPage>[]
        : await _pageRepo.listByBook(selected!.id!);
    if (!mounted) return;
    setState(() {
      _books = books;
      _selected = selected;
      _pages = pages;
      _loading = false;
    });
  }

  static final Book _placeholder = Book(
    id: -1,
    title: '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  Future<void> _createBook() async {
    final title = await _promptText(context, 'New book title');
    if (title == null || title.trim().isEmpty) return;
    final book = await _bookRepo.create(title);
    await _refresh(selectBookId: book.id);
  }

  Future<void> _renameBook(Book book) async {
    final title = await _promptText(context, 'Rename book', initial: book.title);
    if (title == null || title.trim().isEmpty) return;
    await _bookRepo.rename(book.id!, title);
    await _refresh(selectBookId: book.id);
  }

  Future<void> _deleteBook(Book book) async {
    final t = AppStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete book?'),
        content: Text('This will delete "${book.title}" and all its pages and images.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final paths = await _bookRepo.deleteAndCollectImagePaths(book.id!);
      await _imageStorage.deleteMany(paths);
    } catch (e, st) {
      LogService.instance.error('Delete book failed', e, st);
    }
    await _refresh();
  }

  Future<void> _addPage() async {
    final book = _selected;
    if (book?.id == null) return;
    final result = await Navigator.of(context).pushNamed(
      '/admin/page-editor',
      arguments: <String, Object?>{'bookId': book!.id},
    );
    if (result == true) await _refresh(selectBookId: book.id);
  }

  Future<void> _importPdf() async {
    final result = await Navigator.of(context).pushNamed('/admin/pdf-import');
    if (result == true) await _refresh();
  }

  Future<void> _exportBook(Book book) async {
    final share = context.read<BookShareService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save book as…',
        fileName:
            '${book.title.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '_')}.book.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (path == null) return;
      final dest = path.endsWith('.zip') ? path : '$path.zip';
      await share.exportBook(book.id!, dest);
      messenger.showSnackBar(
        SnackBar(content: Text('Exported "${book.title}" to $dest')),
      );
    } catch (e, st) {
      LogService.instance.error('Export book failed', e, st);
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _importBookZip() async {
    final share = context.read<BookShareService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final newBookId = await share.importBook(path);
      messenger.showSnackBar(
        const SnackBar(content: Text('Book imported.')),
      );
      await _refresh(selectBookId: newBookId);
    } catch (e, st) {
      LogService.instance.error('Import book failed', e, st);
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  /// Dev-only batch tool. Walks a source folder of PDFs and writes one
  /// `.book.zip` per PDF into `<project>/assets/seed/oxford/`. The seed
  /// service picks those zips up on a fresh install so the user never has
  /// to import the library on-device.
  ///
  /// Only the user's local Mac dev environment can run this — it touches
  /// the source tree on disk. On iOS / Android this button is hidden.
  Future<void> _bakeSeedLibrary() async {
    final messenger = ScaffoldMessenger.of(context);
    // Capture providers before any async gap.
    final pdfService = context.read<PdfImportService>();
    final lookup = context.read<TranslationLookup>();
    final share = context.read<BookShareService>();
    final wordRepo = context.read<WordRepository>();

    final sourceDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Pick a folder of PDFs to bake',
    );
    if (sourceDir == null) return;

    // The seed zips have to land in the Flutter project's assets/ directory.
    // When the app is launched via `flutter run -d macos` from the repo
    // root, Directory.current is the project root.
    final projectRoot = await _detectProjectRoot();
    if (projectRoot == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not locate the project root (no pubspec.yaml in cwd). '
            'Run via `flutter run -d macos` from the repo root.',
          ),
        ),
      );
      return;
    }
    final destDir =
        Directory(p.join(projectRoot, 'assets', 'seed', 'oxford'));
    if (!await destDir.exists()) await destDir.create(recursive: true);

    final baker = SeedBakerService(
      pdfService: pdfService,
      lookup: lookup,
      share: share,
      bookRepo: _bookRepo,
      pageRepo: _pageRepo,
      wordRepo: wordRepo,
      imageStorage: _imageStorage,
    );

    final progress = ValueNotifier<BakeProgress>(
      const BakeProgress(done: 0, total: 0, currentTitle: ''),
    );
    if (!mounted) return;
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BakeDialog(progress: progress),
    );

    final report = await baker.bakeAll(
      sourceDir: Directory(sourceDir),
      destDirPath: destDir.path,
      onProgress: (snap) => progress.value = snap,
    );
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    await dialog;
    if (report.success + report.failed == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No PDFs found in that folder.')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Baked ${report.success} book(s) to ${destDir.path} '
          '(${report.failed > 0 ? "${report.failed} failed" : "no errors"})',
        ),
      ),
    );
    await _refresh();
  }

  Future<String?> _detectProjectRoot() async {
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      if (await File(p.join(dir.path, 'pubspec.yaml')).exists()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  Future<void> _bulkAutoFill(Book book) async {
    final lookup = context.read<TranslationLookup>();
    final wordRepo = context.read<WordRepository>();
    final pageRepo = context.read<PageRepository>();
    final messenger = ScaffoldMessenger.of(context);

    final pages = await pageRepo.listByBook(book.id!);
    if (pages.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This book has no pages yet.')),
      );
      return;
    }
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Auto-fill all translations?'),
        content: Text(
          'Walks every page of "${book.title}" and fills any missing word '
          'meanings + sentence translations from the bundled dictionary. '
          'Existing teacher-curated entries are NOT changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Auto-fill'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    // Run the walk.
    var pagesUpdated = 0;
    var wordsAdded = 0;
    for (final page in pages) {
      // Word meanings: find missing words.
      final existing = await wordRepo.listByPage(page.id!);
      final knownKeys = existing.map((e) => e.word).toSet();
      final unique = Tokenizer.uniqueWords(page.sentenceText)
          .where((w) => !knownKeys.contains(w))
          .toSet();
      var addedThisPage = false;
      if (unique.isNotEmpty) {
        final entries = await lookup.resolveMany(unique);
        if (entries.isNotEmpty) {
          final merged = <WordMeaning>[
            ...existing,
            for (final e in entries.entries)
              WordMeaning(
                id: null,
                pageId: page.id!,
                word: e.key,
                chineseMeaning: e.value.chinese,
                englishDefinition: e.value.definition,
                source: WordSource.dictionary,
              ),
          ];
          await wordRepo.replaceForPage(page.id!, merged);
          wordsAdded += entries.length;
          addedThisPage = true;
        }
      }
      // Sentence translation: only fill if empty.
      if (page.chineseTranslation.trim().isEmpty &&
          page.sentenceText.trim().isNotEmpty) {
        final cn = await lookup.concatenateChineseFromWords(page.sentenceText);
        if (cn != null && cn.isNotEmpty) {
          await pageRepo.update(
            id: page.id!,
            imagePath: page.imagePath,
            sentenceText: page.sentenceText,
            chineseTranslation: cn,
          );
          addedThisPage = true;
        }
      }
      if (addedThisPage) pagesUpdated++;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Filled $wordsAdded word meaning${wordsAdded == 1 ? '' : 's'} '
          'across $pagesUpdated page${pagesUpdated == 1 ? '' : 's'}.',
        ),
      ),
    );
    await _refresh(selectBookId: book.id);
  }

  Future<void> _editPage(BookPage page) async {
    final result = await Navigator.of(context).pushNamed(
      '/admin/page-editor',
      arguments: <String, Object?>{
        'pageId': page.id,
        'bookId': page.bookId,
      },
    );
    if (result == true) await _refresh(selectBookId: page.bookId);
  }

  Future<void> _deletePage(BookPage page) async {
    final t = AppStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text('Delete page ${page.pageNumber}? Its image will be removed too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final removed = await _pageRepo.delete(page.id!);
    if (removed != null) await _imageStorage.deleteIfExists(removed);
    await _refresh(selectBookId: page.bookId);
  }

  // onReorderItem already adjusts newIndex for the removed item.
  Future<void> _reorder(int oldIndex, int newIndex) async {
    final pages = List<BookPage>.from(_pages);
    final moved = pages.removeAt(oldIndex);
    pages.insert(newIndex, moved);
    setState(() => _pages = pages);
    await _pageRepo.reorder(
      _selected!.id!,
      pages.map((p) => p.id!).toList(),
    );
    await _refresh(selectBookId: _selected!.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final isWide = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.admin),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      floatingActionButton: _selected == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (Platform.isMacOS) ...[
                  FloatingActionButton.small(
                    heroTag: 'bake',
                    tooltip: 'Bake seed library (macOS dev only)',
                    onPressed: _bakeSeedLibrary,
                    child: const Icon(Icons.local_fire_department_outlined),
                  ),
                  const SizedBox(height: 10),
                ],
                FloatingActionButton.small(
                  heroTag: 'importZip',
                  tooltip: 'Import .book.zip',
                  onPressed: _importBookZip,
                  child: const Icon(Icons.file_open_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'pdf',
                  onPressed: _importPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Import PDF'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'addBook',
                  onPressed: _createBook,
                  icon: const Icon(Icons.add),
                  label: Text(t.addBook),
                ),
              ],
            )
          : FloatingActionButton.extended(
              onPressed: _addPage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add page'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 320,
                      child: BookList(
                        books: _books,
                        selected: _selected,
                        onSelect: (b) async {
                          final pages = await _pageRepo.listByBook(b.id!);
                          setState(() {
                            _selected = b;
                            _pages = pages;
                          });
                        },
                        onCreate: _createBook,
                        onRename: _renameBook,
                        onDelete: _deleteBook,
                        onBulkAutoFill: _bulkAutoFill,
                        onExport: _exportBook,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: PageList(
                        book: _selected,
                        pages: _pages,
                        imageStorage: _imageStorage,
                        onEdit: _editPage,
                        onDelete: _deletePage,
                        onReorder: _reorder,
                      ),
                    ),
                  ],
                )
              : _selected == null
                  ? BookList(
                      books: _books,
                      selected: _selected,
                      onSelect: (b) async {
                        final pages = await _pageRepo.listByBook(b.id!);
                        setState(() {
                          _selected = b;
                          _pages = pages;
                        });
                      },
                      onCreate: _createBook,
                      onRename: _renameBook,
                      onDelete: _deleteBook,
                      onBulkAutoFill: _bulkAutoFill,
                      onExport: _exportBook,
                    )
                  : PageList(
                      book: _selected,
                      pages: _pages,
                      imageStorage: _imageStorage,
                      onEdit: _editPage,
                      onDelete: _deletePage,
                      onReorder: _reorder,
                      onBack: () => setState(() => _selected = null),
                    ),
    );
  }
}

Future<String?> _promptText(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final ctrl = TextEditingController(text: initial);
  final t = AppStrings.of(context);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text),
          child: Text(t.save),
        ),
      ],
    ),
  );
}

