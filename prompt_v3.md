# v3 — reader layout fix, reading-mode switch, sentence translation, word examples
(Stored verbatim for traceability; see prompt.md and prompt_v2.md for base + v2 specs.)

# Role
You are a **senior Flutter engineer (11+ years)** extending the existing offline tap-to-read picture-book app (`prompt.md` base, `prompt_v2.md` PDF/dictionary/OCR layer). All previous constraints continue to apply — **zero network calls, ever**. Every change must pass `flutter analyze`, `flutter test`, and `dart run tool/check_offline.dart`.

# Scope of this prompt
1. **Reader layout regression** — long OCR sentences collapsed the image to zero height and overflowed the bottom by 754 px.
2. **Reading-mode switch** — Word vs Sentence; persisted; togglable from Settings and Reader app-bar.
3. **Sentence translation field** — first-class per-page Chinese translation, editable in the page editor, surfaced in Sentence mode.
4. **Word details with examples** — meaning sheet upgraded with in-book corpus examples + ECDICT detail-column examples.

(See chat history for the full per-feature breakdown and acceptance criteria.)
