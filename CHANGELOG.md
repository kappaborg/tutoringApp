# Changelog

## Unreleased (v5) - 2026-07-15
- **Offline license activation**: Ed25519-signed license codes issued by
  `tool/issue_license.dart` (keypair via `tool/generate_keypair.dart`, private
  key stored outside the repo) and verified in-app against an embedded public
  key on the new activation screen. No activation server.
- **Neural TTS**: bundled Kokoro English voice via `sherpa_onnx`
  (`dart run tool/fetch_kokoro.dart` downloads the model at build time).
  `TtsRouter` switches between system and neural voice per speak call based on
  a new Settings toggle.
- **Seed library baking**: macOS-only Admin → "Bake seed library" turns a
  folder of source PDFs into `.book.zip` files under `assets/seed/oxford/`;
  first launch imports them (new seed-loading screen).
- **Admin restructure**: split into book list, page list, and bake dialog.
- Full-screen image viewer, headless bootstrap modes, `tool/probe_pdf.dart`.

## v4
- Dictionary build tool gained two modes: `--starter` (88 hand-picked words,
  ~16 KB, ships by default) and `--full /path/to/ecdict.csv` (~70k entries).
- One-command full dictionary: `dart run tool/fetch_ecdict.dart` downloads the
  ECDICT CSV (build-time only), rebuilds `assets/dict/ecdict.db`, cleans up.
  With the full dictionary, PDF import auto-fills a Chinese + English entry
  for nearly every word (`source = 'pdf'`), and the sentence-mode 50%-coverage
  gate rarely trips.

## v3
- **Reading-mode switch**: *Word by word* (default) vs *Whole sentence*
  (tap anywhere → speak sentence + show its saved Chinese translation).
  Toggle in the app bar or Settings. "Tap-also-speaks-word" applies only in
  Word mode.
- **Per-page Chinese translation** field in the page editor; PDF import can
  generate a literal word-by-word placeholder (skipped when <50% of words are
  in the dictionary).
- **Word details with examples**: the meaning sheet gained three sections —
  translation card (Chinese + pinyin + definition), "From your books" (up to 3
  cross-book sentences containing the word, tap to jump), and "More examples"
  (up to 3 ECDICT example sentences). Empty sections are hidden.
- **Reader layout safety**: image keeps ≥ ~35% of the viewport; sentence area
  scrolls internally up to ~55%, so long OCR sentences can't crush the layout.
- Schema v3 (`pages.chinese_translation`); v1/v2 backups still restore.
  Dictionary asset schema gained a `detail` column.

## v2
- **PDF import as a book** (Admin → Import PDF): renders each page to JPEG,
  extracts embedded text via `pdfrx`, saves one page per PDF page. Pages with
  no embedded text show an amber manual-entry banner.
- **Apple Vision OCR** (iOS + macOS): pages without embedded text fall through
  to on-device `VNRecognizeText` via a method channel
  (`com.kappasutra.picturebook/ocr`); OCR'd sentences get a "verify before
  saving" chip. Not yet implemented on Android/Windows.
- **Bundled offline English→Chinese dictionary** (`assets/dict/ecdict.db`,
  ECDICT-based, MIT): copied to app support on first launch, opened read-only.
- **Dictionary fallback in the reader** with an "auto-translated, not
  verified" chip and a teacher-mode "Save to this page" button.
- **Page editor**: "Auto-fill translations from dictionary" button.
- `word_meanings.source` audit field: `manual` | `dictionary` | `pdf`.
  Restoring a v1 backup back-fills `source='manual'`.

## 1.0.0 - 2026-05-20
- Initial release.
- Offline reader with TTS sentence and word playback.
- Word-meaning popups (Chinese + English definition).
- Teacher admin with PIN gate, image picker, dynamic word fields.
- Settings: TTS rate/pitch/voice, theme, dyslexia font toggle, tap-also-speaks.
- Backup / restore via ZIP (DB + images).
- Offline guarantee enforced by `tool/check_offline.dart` and `test/offline_guard_test.dart`.
