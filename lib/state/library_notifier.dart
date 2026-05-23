import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/page.dart';
import '../models/word_meaning.dart';
import '../repositories/book_repository.dart';
import '../repositories/page_repository.dart';
import '../repositories/word_repository.dart';
import '../services/image_storage_service.dart';
import '../services/prefs_service.dart';

/// The reader/admin shared state: which books exist, which book is selected,
/// which page index is open, and the meanings on the current page.
class LibraryNotifier extends ChangeNotifier {
  LibraryNotifier({
    required this.bookRepo,
    required this.pageRepo,
    required this.wordRepo,
    required this.imageStorage,
    required this.prefs,
  });

  final BookRepository bookRepo;
  final PageRepository pageRepo;
  final WordRepository wordRepo;
  final ImageStorageService imageStorage;
  final PrefsService prefs;

  bool _loading = true;
  List<Book> _books = const [];
  Book? _book;
  List<BookPage> _pages = const [];
  int _pageIndex = 0;
  Map<String, WordMeaning> _wordsByKey = const {};

  bool get loading => _loading;
  List<Book> get books => _books;
  Book? get currentBook => _book;
  List<BookPage> get pages => _pages;
  int get pageIndex => _pageIndex;
  BookPage? get currentPage =>
      (_pages.isEmpty || _pageIndex < 0 || _pageIndex >= _pages.length)
          ? null
          : _pages[_pageIndex];
  Map<String, WordMeaning> get wordsByKey => _wordsByKey;

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    _books = await bookRepo.listAll();
    final resumeBookId = prefs.lastBookId;
    Book? toOpen;
    if (resumeBookId != null) {
      toOpen = _books.firstWhere(
        (b) => b.id == resumeBookId,
        orElse: () => _books.isEmpty ? _emptyBook : _books.first,
      );
      if (toOpen == _emptyBook) toOpen = null;
    } else if (_books.isNotEmpty) {
      toOpen = _books.first;
    }
    if (toOpen != null) {
      await selectBook(toOpen, resumeToLastPage: true, persist: false);
    }
    _loading = false;
    notifyListeners();
  }

  static final Book _emptyBook = Book(
    id: -1,
    title: '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  Future<void> selectBook(
    Book book, {
    bool resumeToLastPage = false,
    bool persist = true,
  }) async {
    _book = book;
    _pages = book.id == null ? const [] : await pageRepo.listByBook(book.id!);
    if (_pages.isEmpty) {
      _pageIndex = 0;
      _wordsByKey = const {};
      notifyListeners();
      return;
    }
    var idx = 0;
    if (resumeToLastPage) {
      final n = prefs.lastPageNumber;
      if (n != null) {
        idx = _pages.indexWhere((p) => p.pageNumber == n);
        if (idx < 0) idx = 0;
      }
    }
    _pageIndex = idx;
    await _loadWordsForCurrent();
    if (persist && book.id != null && _pages.isNotEmpty) {
      await prefs.setLastPosition(book.id!, _pages[_pageIndex].pageNumber);
    }
    notifyListeners();
  }

  Future<void> _loadWordsForCurrent() async {
    final page = currentPage;
    if (page?.id == null) {
      _wordsByKey = const {};
      return;
    }
    _wordsByKey = await wordRepo.mapByPage(page!.id!);
  }

  Future<void> goToPage(int index) async {
    if (index < 0 || index >= _pages.length) return;
    _pageIndex = index;
    await _loadWordsForCurrent();
    final book = _book;
    if (book?.id != null) {
      await prefs.setLastPosition(book!.id!, _pages[_pageIndex].pageNumber);
    }
    notifyListeners();
  }

  Future<void> next() async => goToPage(_pageIndex + 1);
  Future<void> previous() async => goToPage(_pageIndex - 1);

  /// Switches to a specific book + page (used by cross-book word examples).
  /// If [bookId] is the current book, just navigates to the page.
  Future<void> openBookPage(int bookId, int pageNumber) async {
    if (_book?.id != bookId) {
      final target = await bookRepo.findById(bookId);
      if (target == null) return;
      _books = await bookRepo.listAll();
      await selectBook(target, persist: false);
    }
    final idx = _pages.indexWhere((p) => p.pageNumber == pageNumber);
    if (idx >= 0) await goToPage(idx);
  }

  /// Reloads the currently selected book (e.g. after Admin edits).
  Future<void> reloadCurrentBook() async {
    final book = _book;
    if (book == null) {
      await loadAll();
      return;
    }
    final refreshed = await bookRepo.findById(book.id!);
    if (refreshed == null) {
      await loadAll();
      return;
    }
    _books = await bookRepo.listAll();
    await selectBook(refreshed, resumeToLastPage: false, persist: false);
  }
}
