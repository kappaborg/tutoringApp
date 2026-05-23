import 'package:flutter/material.dart';

import '../models/book.dart';

class BookDropdown extends StatelessWidget {
  const BookDropdown({
    super.key,
    required this.books,
    required this.current,
    required this.onChanged,
  });

  final List<Book> books;
  final Book? current;
  final ValueChanged<Book> onChanged;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const SizedBox.shrink();
    }
    // Pick the colour that actually contrasts with the AppBar, regardless of
    // theme. In light mode this is the AppBar's foregroundColor (white-ish
    // on the dark-blue bar). In dark mode the AppBar uses surface colours,
    // so we fall back to onSurface.
    final scheme = Theme.of(context).colorScheme;
    final fg = AppBarTheme.of(context).foregroundColor ?? scheme.onSurface;
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: current?.id,
        iconEnabledColor: fg,
        dropdownColor: scheme.surfaceContainerHighest,
        items: [
          for (final b in books)
            DropdownMenuItem<int>(
              value: b.id,
              child: Text(
                b.title,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
        ],
        selectedItemBuilder: (context) => [
          for (final b in books)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                b.title,
                style: TextStyle(color: fg),
              ),
            ),
        ],
        onChanged: (id) {
          if (id == null) return;
          final selected = books.firstWhere((b) => b.id == id);
          onChanged(selected);
        },
      ),
    );
  }
}
