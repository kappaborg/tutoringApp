import 'package:flutter/material.dart';

import '../../models/book.dart';
import '../../models/page.dart';
import '../../services/image_storage_service.dart';

/// Right-pane page listing used by the admin screen. Renders a reorderable
/// list of [BookPage]s with thumbnail + sentence preview, edit/delete
/// actions, and an optional back button (single-pane phone layout).
class PageList extends StatelessWidget {
  const PageList({
    super.key,
    required this.book,
    required this.pages,
    required this.imageStorage,
    required this.onEdit,
    required this.onDelete,
    required this.onReorder,
    this.onBack,
  });

  final Book? book;
  final List<BookPage> pages;
  final ImageStorageService imageStorage;
  final ValueChanged<BookPage> onEdit;
  final ValueChanged<BookPage> onDelete;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    if (book == null) {
      return const Center(child: Text('Select a book to see its pages.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: onBack == null
              ? const Icon(Icons.menu_book_outlined)
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
          title:
              Text(book!.title, style: Theme.of(context).textTheme.titleLarge),
          subtitle:
              Text('${pages.length} page${pages.length == 1 ? '' : 's'}'),
        ),
        const Divider(height: 1),
        Expanded(
          child: pages.isEmpty
              ? const Center(child: Text('No pages yet — tap "Add page".'))
              : ReorderableListView.builder(
                  itemBuilder: (context, i) {
                    final p = pages[i];
                    return ListTile(
                      key: ValueKey(p.id),
                      leading: SizedBox(
                        width: 64,
                        height: 64,
                        child: FutureBuilder(
                          future: imageStorage.resolve(p.imagePath),
                          builder: (context, snap) {
                            if (!snap.hasData) return const SizedBox.shrink();
                            return FutureBuilder<bool>(
                              future: snap.data!.exists(),
                              builder: (context, e) {
                                if (e.data == true) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      snap.data!,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                }
                                return const Icon(Icons.broken_image_outlined);
                              },
                            );
                          },
                        ),
                      ),
                      title: Text('Page ${p.pageNumber}'),
                      subtitle: Text(
                        p.sentenceText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onEdit(p),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => onDelete(p),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle),
                          ),
                        ],
                      ),
                    );
                  },
                  itemCount: pages.length,
                  onReorder: onReorder,
                ),
        ),
      ],
    );
  }
}
