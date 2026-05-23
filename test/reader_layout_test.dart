import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure widget-shape test that mirrors `ReaderScreen._buildBody`'s layout:
///
///   Column(
///     Expanded(image),
///     ConstrainedBox(maxHeight: viewport * 0.55, SingleChildScrollView(text)),
///     NavBar,
///   )
///
/// We feed it a 600-character sentence and assert:
///   * No `RenderFlex overflowed` exception was raised.
///   * The image region is non-zero height.
///   * The nav bar is positioned below the sentence area.
void main() {
  testWidgets('long sentence cannot starve the image or overflow', (tester) async {
    final imageKey = GlobalKey();
    final sentenceKey = GlobalKey();
    final navKey = GlobalKey();
    final longSentence = List.filled(60, 'lorem ipsum').join(' ');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Test')),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final sentenceMaxH = (c.maxHeight * 0.55).clamp(160.0, 720.0);
                return Column(
                  children: [
                    Expanded(
                      child: Container(
                        key: imageKey,
                        color: Colors.transparent,
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: sentenceMaxH),
                      child: SingleChildScrollView(
                        key: sentenceKey,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          longSentence,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        key: navKey,
                        height: 48,
                        child: const Placeholder(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'long sentence must not cause overflow',
    );

    final imageBox = tester.getRect(find.byKey(imageKey));
    final sentenceBox = tester.getRect(find.byKey(sentenceKey));
    final navBox = tester.getRect(find.byKey(navKey));

    expect(imageBox.height > 0, isTrue, reason: 'image height must be > 0');
    expect(
      sentenceBox.top > imageBox.top,
      isTrue,
      reason: 'sentence must sit below the image area',
    );
    expect(
      navBox.top >= sentenceBox.bottom,
      isTrue,
      reason: 'nav must sit below the sentence area',
    );
  });
}
