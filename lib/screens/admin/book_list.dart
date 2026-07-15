import 'package:flutter/material.dart';

import '../../models/book.dart';

/// Left-pane book listing used by the admin screen. Each tile exposes a
/// popup menu of per-book actions (rename / auto-fill / export / delete).
class BookList extends StatelessWidget {
  const BookList({
    super.key,
    required this.books,
    required this.selected,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    required this.onBulkAutoFill,
    required this.onExport,
  });

  final List<Book> books;
  final Book? selected;
  final ValueChanged<Book> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<Book> onRename;
  final ValueChanged<Book> onDelete;
  final ValueChanged<Book> onBulkAutoFill;
  final ValueChanged<Book> onExport;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.library_books_outlined, size: 72),
              const SizedBox(height: 12),
              const Text('No books yet.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create book'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      itemBuilder: (context, i) {
        final b = books[i];
        final isSelected = b.id == selected?.id;
        return ListTile(
          selected: isSelected,
          title: Text(b.title),
          subtitle: Text('Updated ${_relative(b.updatedAt)}'),
          onTap: () => onSelect(b),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  onRename(b);
                case 'autofill':
                  onBulkAutoFill(b);
                case 'export':
                  onExport(b);
                case 'delete':
                  onDelete(b);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                value: 'autofill',
                child: Text('Auto-fill translations'),
              ),
              PopupMenuItem(
                value: 'export',
                child: Text('Export as .book.zip'),
              ),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: books.length,
    );
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
