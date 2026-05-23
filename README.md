# Picture Book — offline tap-to-read

A single Flutter codebase that runs on **iOS, iPad, Android, macOS, Windows**.
Kids tap a sentence to hear it, or a word to hear it and see its Chinese
translation + English definition. Teachers manage books behind a PIN gate.
Every byte of TTS, every image, and every dictionary entry stays on-device.

## Setup

This repository contains the application source (`lib/`, `test/`, `tool/`,
`l10n/`, `assets/`) but **not** the auto-generated platform folders.
Generate them with `flutter create`, then graft this source in.

```sh
flutter create --org com.example --project-name picture_book \
  --platforms=ios,android,macos,windows .
flutter pub get
```

Then apply the platform configuration snippets from `platform_config/`:

| Platform | Action |
|---|---|
| iOS | Merge `platform_config/ios/Info.plist.snippet.xml` into `ios/Runner/Info.plist`. |
| Android | Merge `platform_config/android/AndroidManifest.snippet.xml` into `android/app/src/main/AndroidManifest.xml`. Remember the `xmlns:tools` declaration on the root `<manifest>` element. |
| macOS | Copy `platform_config/macos/DebugProfile.entitlements` and `Release.entitlements` into `macos/Runner/`. |
| Windows | See `platform_config/windows/notes.md` (no manifest changes needed). |

## Run

```sh
dart run tool/check_offline.dart           # offline-guard CI check
flutter pub get
flutter test                                # unit tests
flutter run -d <device_id>                  # iOS / Android / macOS / Windows
```

`flutter devices` lists available targets.

First launch seeds **one sample book with three procedural pages** so the
reader is never blank.

## Airplane-mode verification protocol

1. Turn off Wi-Fi, cellular, Bluetooth (all radios off).
2. Cold-launch the app: the sample book renders.
3. Tap the sentence: TTS speaks it (assumes the OS has an on-device English voice).
4. Tap a word: meaning popup appears and the word is spoken.
5. Set up a Teacher PIN, create a new book with a new image, save.
6. Export a backup ZIP, import it back — counts match.

If anything reaches for the network it is a regression — re-run
`dart run tool/check_offline.dart`.

## Project layout

```
picture_book/
├── README.md
├── CHANGELOG.md
├── LICENSE
├── pubspec.yaml
├── analysis_options.yaml
├── l10n.yaml
├── l10n/                # ARB scaffolding (en, zh) for future codegen
├── assets/seed/         # placeholder; images are procedurally generated
├── tool/
│   └── check_offline.dart
├── platform_config/     # snippets to graft into iOS/Android/macOS folders
├── lib/
│   ├── main.dart          # entry: ffi init, error handlers, providers
│   ├── app.dart           # MaterialApp, theme, routes
│   ├── l10n/app_strings.dart
│   ├── db/                # SQLite + migrations
│   ├── models/            # Book, BookPage, WordMeaning
│   ├── repositories/      # Typed CRUD over sqflite
│   ├── services/          # tts, image_storage, prefs, backup, log, seed,
│   │                      # debug_network_probe
│   ├── state/             # ChangeNotifiers wired into Provider
│   ├── screens/           # reader, admin, page_editor, settings, pin_gate
│   ├── widgets/           # word_span, word_meaning_sheet, book_dropdown,
│   │                      # missing_image_placeholder
│   └── utils/             # tokenizer, result
└── test/
    ├── tokenizer_test.dart
    ├── book_repository_test.dart   # in-memory sqflite_common_ffi
    ├── image_storage_test.dart     # MockPlatformInterfaceMixin for path_provider
    └── offline_guard_test.dart     # scans lib/ for banned tokens
```

## Storage locations

| Data | Directory |
|---|---|
| SQLite DB | `getApplicationSupportDirectory()/picturebook.db` |
| Page images | `getApplicationDocumentsDirectory()/images/` |
| Logs (rotated 1 MB × 3) | `getApplicationSupportDirectory()/logs/` |

## Changing the bundle ID

Default is `com.example.picturebook`. Override per platform:

| Platform | Where |
|---|---|
| iOS | `ios/Runner.xcodeproj/project.pbxproj` → `PRODUCT_BUNDLE_IDENTIFIER` |
| Android | `android/app/build.gradle` → `applicationId` |
| macOS | `macos/Runner.xcodeproj/project.pbxproj` → `PRODUCT_BUNDLE_IDENTIFIER` |
| Windows | `windows/runner/Runner.rc` → `VALUE "InternalName"` |

## Known platform caveats

| Platform | Caveat |
|---|---|
| iOS Simulator | No TTS voices by default — install a voice in **Settings → Accessibility → Spoken Content → Voices**, or test on a real device. |
| Windows | TTS uses SAPI. Install voices in **Settings → Time & language → Speech**. `flutter_tts` does not provide a progress handler on Windows, so word-by-word highlighting falls back to whole-sentence playback. |
| macOS | App is sandboxed. The file picker re-prompts after every launch; that's a sandbox behavior, not a bug. |
| Android < 13 | Uses `READ_EXTERNAL_STORAGE`; on 13+ uses `READ_MEDIA_IMAGES`. The manifest handles both. |

## Offline guarantees

1. **No banned dependencies** in `pubspec.yaml`. The guard list lives in `tool/check_offline.dart`.
2. **No banned APIs** in `lib/` (no `HttpClient`, `Socket.connect`, `WebSocket.connect`, `dart:html`). The one allowlisted file — `lib/services/debug_network_probe.dart` — contains the `offline-guard:allow` marker and is debug-only.
3. **Android** manifest neutralises any transitive `INTERNET` permission with `tools:node="remove"`.
4. **macOS** entitlements set `network.client` and `network.server` to `false`.
5. **iOS** disables arbitrary loads via `NSAppTransportSecurity`.
6. **CI script** and **unit test** enforce all of the above.

## License

MIT — see [LICENSE](LICENSE).

---

## v2 features (added)

### PDF import as a book
- Admin → **Import PDF** (the second FAB on the books list).
- Picks a local `.pdf`, renders each page to a JPEG, extracts any embedded
  text, and saves a Book with one page per PDF page.
- Pages whose source PDF has no embedded text show an amber banner —
  teacher types the sentence manually. (OCR is a v2 follow-up.)
- Uses `pdfrx` (substituted for `pdfx` because `pdfx` is rendering-only and
  has no text-extraction API — `pdfrx` does both, MIT licensed, fully
  offline).

### Bundled offline English→Chinese dictionary
- `assets/dict/ecdict.db` ships with the app and is committed.
- A ~88-word *starter* version is included by default. To upgrade to the
  full ECDICT lite (~110 k entries):
  1. Download `ecdict.csv` from
     <https://github.com/skywind3000/ECDICT> (MIT licensed).
  2. `dart run tool/build_dict.dart path/to/ecdict.csv`
  3. Commit the regenerated `assets/dict/ecdict.db`.
- The DB is copied to `getApplicationSupportDirectory()/dict/ecdict.db` on
  first launch and opened **read-only** — never modified, never re-fetched.

### Dictionary fallback in the reader
- When a tapped word has no curated `word_meanings` entry for that page,
  the reader queries the bundled dictionary and shows the result with an
  "auto-translated, not verified" chip.
- When Teacher Mode is unlocked, a **Save to this page** button appears
  that inserts a `word_meanings` row with `source='dictionary'`.

### Page editor: auto-fill from dictionary
- New button next to "Auto-fill words from sentence":
  **Auto-fill translations from dictionary**. Fills only rows whose
  Chinese or English field is empty; rows it touches are marked with the
  `dict` source badge.

### `word_meanings.source` semantics
Each row now records where its data came from:
| value | meaning |
|---|---|
| `manual` | typed by a teacher (default) |
| `dictionary` | auto-filled from the bundled ECDICT |
| `pdf` | auto-filled during a PDF import |

The reader does not distinguish between sources at read time — the
`source` field is purely audit metadata. Backups (ZIP) round-trip the
field across v2 ↔ v2 restores; restoring a v1 backup runs the v1→v2
migration automatically and back-fills every row to `source='manual'`.

### Apple Vision OCR (iOS + macOS)
PDFs whose pages have no embedded text fall through to **Apple Vision**
(`VNRecognizeText`) — fully on-device, no network, ships with the OS.
- The PDF importer first asks `pdfrx.loadText()`; if that's empty it runs
  the rendered JPEG through Vision via a method channel
  (`com.kappasutra.picturebook/ocr`).
- Pages whose sentence came from OCR get an **"OCR — verify before saving"**
  chip in the review screen so the teacher knows to double-check.
- On Android / Windows / Linux, OCR is not implemented yet; image-only
  pages still show the manual-entry banner. (Tesseract / ML-Kit-offline can
  be wired into `OcrService` later behind the same Dart API.)

---

## v3 features

### Reading-mode switch
The reader has two modes; toggle from the app bar icon (between settings and admin) or from **Settings → Reading mode**.

- **Word by word** *(default)* — tap a word to hear it and open the meaning sheet (translation, pinyin, cross-book examples, dictionary examples).
- **Whole sentence** — tap anywhere on the sentence area to TTS-speak the whole sentence and open the **Sentence translation** sheet showing the saved Chinese translation of the page.

The "tap-also-speaks-word" preference only applies in Word mode and is hidden otherwise.

### Per-page Chinese translation
The page editor has a new **Chinese translation (whole sentence)** field. It's optional but powers Sentence mode. During PDF import, when "Auto-translate all words" is on, the app *also* generates a literal word-by-word Chinese placeholder for each page (skipped when fewer than 50 % of the words exist in the dictionary). Teachers are expected to refine these.

### Word details with examples
When a word is tapped in Word mode, the meaning sheet now scrolls and has three sections:

1. **Translation card** — Chinese + pinyin + English definition. Curated entries show plainly; dictionary fallbacks show the "auto-translated" chip and a "Save to this page" CTA when Teacher Mode is unlocked.
2. **From your books** — up to 3 sentences from other pages across all your books that contain this word, with the word **bold + underlined**. Tap a card to jump the reader straight to that page.
3. **More examples** — up to 3 ECDICT example sentences when the dictionary's `detail` column has them. (The starter dictionary ships with empty `detail`; build with `dart run tool/build_dict.dart ecdict.csv` to populate.)

Sections with no data are hidden completely — no awkward "no examples" placeholders.

### Reader layout safety
The reader image is now guaranteed to retain at least ~35 % of the viewport, and the sentence area is internally scrollable up to ~55 %. Long OCR sentences (e.g. front-matter pages of a real book) no longer collapse the image or push the bottom nav off-screen.

### Migration notes
- Schema bumped to v3 (`pages.chinese_translation`).
- v1 and v2 backups still restore — the onUpgrade migration runs after restore.
- Dictionary asset schema also gained a `detail` column; the ship asset (`assets/dict/ecdict.db`) was rebuilt.

---

## Building the dictionary (v4)

`assets/dict/ecdict.db` is committed and used by the running app — it never
fetches anything at run time. The build tool has two modes:

```sh
# Starter set (88 hand-picked picture-book words, ~16 KB) — what ships
# by default and what CI relies on.
dart run tool/build_dict.dart --starter

# Full ECDICT lite (~110 k entries, ~10–15 MB).
# 1. Obtain ecdict.csv from https://github.com/skywind3000/ECDICT
#    (MIT licensed; download a "lite" release or the latest snapshot).
# 2. DO NOT commit the CSV — only the resulting .db is committed.
# 3. Build:
dart run tool/build_dict.dart --full /path/to/ecdict.csv
# 4. Verify size with `ls -la assets/dict/ecdict.db` (should be a few MB).
# 5. Commit `assets/dict/ecdict.db`.
```

The full dictionary unlocks Chinese + English definitions for nearly every
word a picture book uses. Without it the suffix-stripping stemmer
(`lib/utils/word_stemmer.dart`) still resolves inflected forms against
whatever vocabulary is bundled, so "days" finds "day" even with the
starter set — but only if the headword is present.

---

## One-command full dictionary (recommended for picture-book use)

The bundled `assets/dict/ecdict.db` ships as an ~800-word starter set. To
upgrade to the full ECDICT lite (~70 000 entries — covers virtually every
word a kids' book contains) in **one command**:

```sh
dart run tool/fetch_ecdict.dart
```

The tool:
1. Downloads the ECDICT CSV from GitHub once (build-time, on your Mac).
2. Hands it to `tool/build_dict.dart --full` to produce a new `ecdict.db`.
3. Cleans up the CSV.

After it finishes, commit the regenerated asset:

```sh
git add assets/dict/ecdict.db
```

The shipped app is **still 100 % offline at runtime** — `fetch_ecdict.dart`
is a build-time-only helper that lives in `tool/`, not in `lib/`. Once the
.db is committed, end users never trigger a download.

If you already have a CSV locally (e.g. downloaded by hand), skip the
network step:

```sh
dart run tool/fetch_ecdict.dart --local /path/to/ecdict.csv
```

### What this changes in the running app
- After re-import, every English word found in a PDF gets a Chinese +
  English entry auto-written into `word_meanings` (`source = 'pdf'`).
- Words previously imported with the starter dictionary keep their
  existing rows. Re-import the PDF (or hit "Auto-fill translations from
  dictionary" in the page editor) to backfill them.
- Sentence-mode literal-join translations now cover essentially every
  sentence — the 50 %-coverage gate trips far less often.
- Tap-to-translate in the reader resolves nearly every word at the first
  dictionary hop without even needing the suffix stemmer.
