 You are a senior Flutter engineer extending the existing offline tap-to-read
  picture book app (see prompt.md for the base spec). All base constraints       
  continue to apply — zero network calls, ever. Every new dependency, asset, and
  code path must pass tool/check_offline.dart and flutter test.                  
                                                            
  New Features (scope of this prompt)                                          

  1. PDF import as a book — pick a local PDF, parse it offline, turn each page   
  into a book page with its image + extracted sentence text.
  2. Bundled offline English→Chinese dictionary — when the teacher imports a PDF 
  (or taps "auto-fill from dictionary" in the page editor), each unique English  
  word is auto-populated with its Chinese translation and English definition from
   a shipped dictionary.                                                         
  3. Reader fallback to dictionary — if a tapped word has no curated
  word_meanings entry for the current page, show the bundled-dictionary result   
  inline, clearly labelled as auto-translated (not teacher-verified).
                                                                                 
  Hard Offline Guarantee (still non-negotiable)             
                                                                               
  - No new networking packages. pdfx and any PDF/OCR packages must operate purely
   on local bytes.
  - The dictionary is bundled as a static asset — never fetched. No "download    
  language pack" UX, no ML Kit translation, no Apple Translation framework (those
   require pack downloads or OS prompts that violate the strict-offline policy).
  - tool/check_offline.dart must continue to exit 0.                             
                                                                                 
  Choices, decided up front (no debating in code)                                
                                                                                 
  Decision: PDF rendering                                                        
  Pick: pdfx (latest 2.x)                                                      
  Why: Cross-platform offline (Pdfium on Android/Windows, PDFKit on iOS/macOS).
  No                                                                          
    network.                                                                  
  ────────────────────────────────────────                                       
  Decision: PDF text extraction                                               
  Pick: pdfx's built-in text extraction per page                                 
  Why: Works for the 95% of PDFs that have embedded text.                        
  ────────────────────────────────────────                                     
  Decision: Image-only PDFs                                                      
  Pick: Out of scope for v1. If a page has no embedded text, leave the sentence
    blank and surface a banner: "No text in this PDF page — type the sentence    
    manually." OCR ships in v2.
  Why: Bundling Tesseract trained data adds ~30 MB/language and complicates the  
    cross-platform story. Defer.                            
  ────────────────────────────────────────                                     
  Decision: Dictionary                                                           
  Pick: ECDICT lite (English-Chinese, ~110 k common entries, MIT license, free) —
                                                                                 
    pre-built into a SQLite DB shipped as assets/dict/ecdict.db. Source URL goes
    in README; the .db itself is committed so the build never reaches the      
    network.
  Why: CC-CEDICT is ZH→EN (wrong direction). ECDICT is purpose-built EN→ZH with
    definitions and pinyin.
  ────────────────────────────────────────
  Decision: Auto-translation persistence                                         
  Pick: Insert into word_meanings with a new source column ('manual' | 
    'dictionary' | 'pdf'). Teacher edits in the page editor as before.           
  Why: Single source of truth; reader code unchanged for curated entries.
  ────────────────────────────────────────                                     
  Decision: Reader fallback                                                      
  Pick: If word_meanings has no entry, query the bundled dict at tap time. Show
    with a "(auto-translated)" tag and an "Add to this page" CTA when admin is   
    unlocked.                                               
  Why: Keeps the curated path as the gold standard; never overwrites teacher   
  work.

  Data Layer Changes

  Migrations (db/migrations.dart)                                                
  
  Schema bump to v2:                                                             
                                                            
  ALTER TABLE word_meanings ADD COLUMN source TEXT NOT NULL DEFAULT 'manual';  
  -- valid values: 'manual', 'dictionary', 'pdf'                                 
                                                                                 
  - Migrations.latestVersion = 2.                                                
  - onUpgrade from 1→2 runs the ALTER TABLE and back-fills source='manual'.      
  - BackupService schema version bumps to 2. Imports from v1 backups still load  
  (forward-only migration runs after restore).                                   
                                                                                 
  Models                                                                         
                                                                               
  - WordMeaning gains final WordSource source (enum with manual, dictionary,     
  pdf).
  - toMap / fromMap updated accordingly. Default value manual keeps existing call
   sites compiling.                                                              
                                                                               
  New Services                                                                   
                                                            
  lib/services/dictionary_service.dart                                         

  Opens assets/dict/ecdict.db once on app start (copied to app-support dir on    
  first launch — read-only, never modified).
                                                                                 
  class DictionaryEntry {                                   
    final String word;        // lowercased English headword                     
    final String pinyin;      // optional, may be empty
    final String chinese;     // simplified Chinese translation(s),              
  pipe-separated if multiple                                                     
    final String definition;  // short English definition                        
  }                                                                              
                                                                               
  class DictionaryService {                                                    
    Future<void> init();                           // copies asset → app-support
    Future<DictionaryEntry?> lookup(String word);  // exact match,               
  case-insensitive
    Future<List<DictionaryEntry>> lookupMany(Iterable<String> words);            
  }                                                                              
                                                                               
  - Indexed on word; lookups are O(log n).                                       
  - Provided via Provider like the other services.          
                                                                                 
  lib/services/pdf_import_service.dart                                           
                                                                               
  class PdfImportResult {                                                        
    final int pageCount;                                    
    final List<PdfImportedPage> pages;                                         
  }
  class PdfImportedPage {
    final String imageRelPath;   // produced by ImageStorageService
    final String sentenceText;   // empty if no embedded text                    
    final bool textWasExtracted; // false → image-only page; sentence is empty   
  }                                                                              
                                                                                 
  class PdfImportService {                                                       
    Future<String?> pickPdf();              // file_picker with .pdf filter    
    Future<PdfImportResult> importPdf(                                           
      String pdfPath, {
      required ProgressCallback onProgress, // (current, total)                  
    });                                                                          
  }                                                                            
                                                                                 
  Per page:                                                                      
  1. Render to bitmap at 1.5× target display resolution (cap long edge at 2048 
  px).                                                                           
  2. Encode JPEG q=85 and route through ImageStorageService (so the existing
  orphan-cleanup pipeline applies).                                              
  3. Extract text via pdfx's page-text API; collapse whitespace, strip soft      
  hyphens, trim.                                                               
  4. Return PdfImportedPage for each page.                                       
                                                            
  Memory: stream page-by-page; never hold the whole PDF in memory.               
                                                            
  lib/services/translation_lookup.dart                                           
                                                            
  A thin convenience layer used by both Admin (auto-fill) and Reader (fallback): 
                                                            
  class TranslationLookup {                                                      
    TranslationLookup(this._dict);                          
    final DictionaryService _dict;                                               
  
    /// Looks up [keys] in the bundled dictionary. Returns the entries that hit. 
    Future<Map<String, DictionaryEntry>> resolveMany(Set<String> keys);
  }                                                                              
                                                                                 
  UI Changes                                                                   
                                                                                 
  Admin → page editor (screens/page_editor_screen.dart)                          
                                                                               
  - New button next to "Auto-fill words from sentence": "Auto-fill translations  
  from dictionary".                                         
    - Walks each word row whose Chinese or English field is empty, looks it up,
  fills it. Skips rows the teacher already touched.                              
    - Sets source='dictionary' on those rows when saved.
  - Word row has a small source badge: 🖋 manual / 📚 dictionary / 📄 pdf.        
                                                                                 
  Admin → books list (screens/admin_screen.dart)                               
                                                                                 
  - New FAB option (split FAB or speed-dial) next to "Add page":                 
    - Add page (image) — existing path.                                        
    - Import PDF as new book — opens PdfImportScreen.                            
                                                            
  lib/screens/pdf_import_screen.dart (new)                                       
                                                            
  - Step 1: pick PDF → show parse progress bar.                                  
  - Step 2: review screen.                                  
    - Book title field (auto-suggested from PDF metadata title, else filename).  
    - Scrollable list of imported pages: thumbnail + editable sentence text +    
  word count.                                                                    
    - Pages with textWasExtracted=false show an amber banner: "No embedded text —
   type the sentence manually."                                                  
    - "Auto-translate all words" toggle (default ON) — runs dictionary lookup at
  save time.                                                                     
  - Step 3: save → single SQLite transaction creating Book + pages +
  word_meanings (source='pdf' for auto-translated rows, 'manual' otherwise).     
  - Unsaved-changes guard via PopScope.                     
                                                                                 
  Reader → word tap (screens/reader_screen.dart +                                
  widgets/word_meaning_sheet.dart)                                             
                                                                                 
  - When wordsByKey[token.lookupKey] == null:                                    
    - Query DictionaryService.lookup(token.lookupKey) (cached after first hit per
   page).                                                                        
    - If hit: show the bottom sheet with the entry, plus a chip
  "(auto-translated, not verified)" and, when Teacher Mode is unlocked, a "Save  
  to this page" button that inserts a word_meanings row with source='dictionary'
  and refreshes the reader.                                                      
    - If miss: show the existing "No meaning recorded" state.
                                                                                 
  Tokenizer
                                                                                 
  No changes. The existing punctuation-stripping lookupKey is exactly the format 
  the dictionary expects.                                                      
                                                                                 
  Project structure additions                                                    
                                                                               
  assets/                                                                        
    dict/                                                   
      ecdict.db                 # ~10 MB, committed; built from ECDICT lite CSV
  by tool/build_dict.dart                                                        
      ecdict.LICENSE            # MIT license text + attribution
  lib/                                                                           
    services/                                               
      dictionary_service.dart                                                    
      pdf_import_service.dart                               
      translation_lookup.dart                                                  
    screens/                                                                     
      pdf_import_screen.dart
  tool/                                                                          
    build_dict.dart             # one-time: reads ecdict_lite.csv (NOT committed)
   → emits ecdict.db                                                             
  test/
    dictionary_service_test.dart                                                 
    pdf_import_service_test.dart                                                 
                                                                               
  pubspec.yaml additions                                                         
                                                            
  - pdfx: ^2.6.0 (or current stable)                                             
  - sqlite3: ^2.4.0 already transitive via sqflite_common_ffi — no new direct dep
   needed                                                                        
  - Declare assets/dict/ under flutter.assets.              
                                                                                 
  Banned-list reaffirmed. No http, no ml_kit_*, no apple_translation, no         
  google_*, no analytics. pdfx operates on local bytes only.                   
                                                                                 
  Tests                                                     
                                                                               
  - tokenizer_test.dart — unchanged.                                             
  - book_repository_test.dart — extend to verify the v1→v2 migration adds the
  source column with default 'manual'.                                           
  - dictionary_service_test.dart                            
    - Asserts lookup('cat'), lookup('CAT'), lookup('cat,') all resolve via the   
  lowercase exact match.                                                         
    - Asserts lookup('zzznotaword') returns null.                              
    - Asserts the DB is read-only (write attempt throws).                        
  - pdf_import_service_test.dart                            
    - Builds a tiny in-memory PDF with two pages (one with text, one image-only) 
  via a fixture, runs importPdf, checks counts, the textWasExtracted flag on     
  each, and that JPEGs landed in the images dir.                                 
  - offline_guard_test.dart — extend banned-package list; verify the new files   
  contain no HttpClient/Socket.connect/WebSocket.connect.                        
                                                                               
  Acceptance Criteria                                                            
                                                            
  - flutter analyze: 0 issues. dart format: clean.                               
  - flutter test: all tests pass (existing + new).          
    - Asserts lookup('cat'), lookup('CAT'), lookup('cat,') all resolve via the lowercase exact match.
    - Asserts lookup('zzznotaword') returns null.
    - Asserts the DB is read-only (write attempt throws).
  - pdf_import_service_test.dart
    - Builds a tiny in-memory PDF with two pages (one with text, one image-only) via a fixture, runs importPdf, checks
   counts, the textWasExtracted flag on each, and that JPEGs landed in the images dir.
  - offline_guard_test.dart — extend banned-package list; verify the new files contain no
  HttpClient/Socket.connect/WebSocket.connect.
    - Asserts lookup('zzznotaword') returns null.
    - Asserts the DB is read-only (write attempt throws).
  - pdf_import_service_test.dart
    - Builds a tiny in-memory PDF with two pages (one with text, one image-only) via a fixture, runs importPdf, checks
   counts, the textWasExtracted flag on each, and that JPEGs landed in the images dir.
  - offline_guard_test.dart — extend banned-package list; verify the new files contain no
  HttpClient/Socket.connect/WebSocket.connect.

  Acceptance Criteria

  - flutter analyze: 0 issues. dart format: clean.
  - flutter test: all tests pass (existing + new).
  - dart run tool/check_offline.dart: OK.
  - flutter pub deps shows no banned package added directly or as a direct lockfile entry.
  - In airplane mode: import a 3-page text PDF → 3 pages appear with correct images, correct sentences, and word rows
  pre-populated with Chinese + English definitions from the dictionary.
  - In airplane mode: tap a word in the reader that has no curated entry — sheet shows the dictionary result with the
  "(auto-translated)" chip; saving it inserts a source='dictionary' row visible after relaunch.
  - A v1 backup ZIP restored on top of v2 still loads (migration runs after restore, defaults source='manual').
  - Deleting a book imported from PDF removes all its image files from disk (existing orphan-cleanup test extended).
  - assets/dict/ecdict.db is committed; the README documents how it was produced and links the ECDICT MIT license.

  Output Format (strict)

  Produce, in this order:
  1. Updated pubspec.yaml.
  2. Updated lib/db/migrations.dart (v2).
    - Asserts the DB is read-only (write attempt throws).
  - pdf_import_service_test.dart
    - Builds a tiny in-memory PDF with two pages (one with text, one image-only) via a fixture, runs importPdf,
  checks counts, the textWasExtracted flag on each, and that JPEGs landed in the images dir.
  - offline_guard_test.dart — extend banned-package list; verify the new files contain no
  HttpClient/Socket.connect/WebSocket.connect.

  Acceptance Criteria

  - flutter analyze: 0 issues. dart format: clean.
  - flutter test: all tests pass (existing + new).
  - dart run tool/check_offline.dart: OK.
  - flutter pub deps shows no banned package added directly or as a direct lockfile entry.
  - In airplane mode: import a 3-page text PDF → 3 pages appear with correct images, correct sentences, and word
  rows pre-populated with Chinese + English definitions from the dictionary.
  - In airplane mode: tap a word in the reader that has no curated entry — sheet shows the dictionary result with
  the "(auto-translated)" chip; saving it inserts a source='dictionary' row visible after relaunch.
  - A v1 backup ZIP restored on top of v2 still loads (migration runs after restore, defaults source='manual').
  - Deleting a book imported from PDF removes all its image files from disk (existing orphan-cleanup test extended).
  - assets/dict/ecdict.db is committed; the README documents how it was produced and links the ECDICT MIT license.

  Output Format (strict)

  Produce, in this order:
  1. Updated pubspec.yaml.
  2. Updated lib/db/migrations.dart (v2).
  3. Updated lib/models/word_meaning.dart with source enum + serialization.
  4. New lib/services/dictionary_service.dart.
  5. New lib/services/pdf_import_service.dart.
  6. New lib/services/translation_lookup.dart.
  7. Updated lib/main.dart registering the new services in MultiProvider.
  8. New lib/screens/pdf_import_screen.dart.
  9. Updated lib/screens/admin_screen.dart (Import PDF entry point).
  10. Updated lib/screens/page_editor_screen.dart (dictionary auto-fill button + source badge).
  11. Updated lib/screens/reader_screen.dart + lib/widgets/word_meaning_sheet.dart (dictionary fallback + "Save to
  this page").
  12. New tool/build_dict.dart (the dictionary builder, with comments documenting the ECDICT sourcCSV format).
  - pdf_import_service_test.dart
    - Builds a tiny in-memory PDF with two pages (one with text, one image-only) via afixture, runs
  importPdf, checks counts, the textWasExtracted flag on each, and that JPEGs landed ithe images
  dir.
  - offline_guard_test.dart — extend banned-package list; verify the new files containno
  HttpClient/Socket.connect/WebSocket.connect.

  Acceptance Criteria

  - flutter analyze: 0 issues. dart format: clean.
  - flutter test: all tests pass (existing + new).
  - dart run tool/check_offline.dart: OK.
  - flutter pub deps shows no banned package added directly or as a direct lockfile entry.
  - In airplane mode: import a 3-page text PDF → 3 pages appear with correct images, correct
  sentences, and word rows pre-populated with Chinese + English definitions from the dictionary.
  - In airplane mode: tap a word in the reader that has no curated entry — sheet showsthe dictionary
  result with the "(auto-translated)" chip; saving it inserts a source='dictionary' rovisible after
  relaunch.
  - A v1 backup ZIP restored on top of v2 still loads (migration runs after restore, defaults
  source='manual').
  - Deleting a book imported from PDF removes all its image files from disk (existing orphan-cleanup
  test extended).
  - assets/dict/ecdict.db is committed; the README documents how it was produced and links the ECDICT
  MIT license.

  Output Format (strict)

  Produce, in this order:
  1. Updated pubspec.yaml.
  2. Updated lib/db/migrations.dart (v2).
  3. Updated lib/models/word_meaning.dart with source enum + serialization.
  4. New lib/services/dictionary_service.dart.
  5. New lib/services/pdf_import_service.dart.
  6. New lib/services/translation_lookup.dart.
  7. Updated lib/main.dart registering the new services in MultiProvider.
  8. New lib/screens/pdf_import_screen.dart.
  9. Updated lib/screens/admin_screen.dart (Import PDF entry point).
  10. Updated lib/screens/page_editor_screen.dart (dictionary auto-fill button + sourcbadge).
  11. Updated lib/screens/reader_screen.dart + lib/widgets/word_meaning_sheet.dart (dictionary
  fallback + "Save to this page").
  12. New tool/build_dict.dart (the dictionary builder, with comments documenting the ECDICT source
  CSV format).
  13. New + updated tests.
  14. README addendum documenting:
    - Where to obtain ecdict_lite.csv, how to run dart run tool/build_dict.dart, and that the
  resulting assets/dict/ecdict.db is committed.
    - PDF import limitations (no OCR in v1).
    - The source field semantics in word_meanings.
  - flutter analyze: 0 issues. dart format: clean.
  - flutter test: all tests pass (existing + new).
  - dart run tool/check_offline.dart: OK.
  - flutter pub deps shows no banned package added directly or as a direct lockfile
  entry.
  - In airplane mode: import a 3-page text PDF → 3 pages appear with correct images,
  correct sentences, and word rows pre-populated with Chinese + English definitionfrom
   the dictionary.
  - In airplane mode: tap a word in the reader that has no curated entry — sheet shows
  the dictionary result with the "(auto-translated)" chip; saving it inserts a
  source='dictionary' row visible after relaunch.
  - A v1 backup ZIP restored on top of v2 still loads (migration runs after restore,
  defaults source='manual').
  - Deleting a book imported from PDF removes all its image files from disk (existing
  orphan-cleanup test extended).
  - assets/dict/ecdict.db is committed; the README documents how it was produced and
  links the ECDICT MIT license.

  Output Format (strict)

  Produce, in this order:
  1. Updated pubspec.yaml.
  2. Updated lib/db/migrations.dart (v2).
  3. Updated lib/models/word_meaning.dart with source enum + serialization.
  4. New lib/services/dictionary_service.dart.
  5. New lib/services/pdf_import_service.dart.
  6. New lib/services/translation_lookup.dart.
  7. Updated lib/main.dart registering the new services in MultiProvider.
  8. New lib/screens/pdf_import_screen.dart.
  9. Updated lib/screens/admin_screen.dart (Import PDF entry point).
  10. Updated lib/screens/page_editor_screen.dart (dictionary auto-fill button + source
  badge).
  - dictionary_service_test.dart
    - Asserts lookup('cat'), lookup('CAT'), lookup('cat,') all resolve via the lowercase exact match.
    - Asserts lookup('zzznotaword') returns null.
    - Asserts the DB is read-only (write attempt throws).
  - pdf_import_service_test.dart
    - Builds a tiny in-memory PDF with two pages (one with text, one image-only) via a fixture, runs importPdf, checks
   counts, the textWasExtracted flag on each, and that JPEGs landed in the images dir.
  - offline_guard_test.dart — extend banned-package list; verify the new files contain no
  HttpClient/Socket.connect/WebSocket.connect.

  Acceptance Criteria

  - flutter analyze: 0 issues. dart format: clean.
  - flutter test: all tests pass (existing + new).
  - dart run tool/check_offline.dart: OK.
  - flutter pub deps shows no banned package added directly or as a direct lockfile entry.
  - In airplane mode: import a 3-page text PDF → 3 pages appear with correct images, correct sentences, and word rows
  pre-populated with Chinese + English definitions from the dictionary.
  - In airplane mode: tap a word in the reader that has no curated entry — sheet shows the dictionary result with the
  "(auto-translated)" chip; saving it inserts a source='dictionary' row visible after relaunch.
  - A v1 backup ZIP restored on top of v2 still loads (migration runs after restore, defaults source='manual').
  - Deleting a book imported from PDF removes all its image files from disk (existing orphan-cleanup test extended).
  - assets/dict/ecdict.db is committed; the README documents how it was produced and links the ECDICT MIT license.

  Output Format (strict)

  Produce, in this order:
  1. Updated pubspec.yaml.
  2. Updated lib/db/migrations.dart (v2).
  3. Updated lib/models/word_meaning.dart with source enum + serialization.
  4. New lib/services/dictionary_service.dart.
  5. New lib/services/pdf_import_service.dart.
  6. New lib/services/translation_lookup.dart.
  7. Updated lib/main.dart registering the new services in MultiProvider.
  8. New lib/screens/pdf_import_screen.dart.
  9. Updated lib/screens/admin_screen.dart (Import PDF entry point).
  10. Updated lib/screens/page_editor_screen.dart (dictionary auto-fill button + source badge).
  11. Updated lib/screens/reader_screen.dart + lib/widgets/word_meaning_sheet.dart (dictionary fallback + "Save to
  this page").
  12. New tool/build_dict.dart (the dictionary builder, with comments documenting the ECDICT source CSV format).
  13. New + updated tests.
  14. README addendum documenting:
    - Where to obtain ecdict_lite.csv, how to run dart run tool/build_dict.dart, and that the resulting
  assets/dict/ecdict.db is committed.
    - PDF import limitations (no OCR in v1).
    - The source field semantics in word_meanings.

  Generate the full diff now. Every file must be complete — no // ... rest unchanged ... placeholders. Preserve all
  base-prompt invariants.

  ---
  Notes for you before you ship this prompt:

  - PDF rendering on desktop: pdfx works on macOS/Windows but uses different backends. If you hit binary issues on
  Windows, the prompt allows substituting printing + pdf (pure-Dart) at a 3–5× speed cost.
  - Dictionary licensing: ECDICT is MIT, so safe to bundle. If you want CC-CEDICT instead (more comprehensive,
  CC-BY-SA), the prompt's structure swaps cleanly — just change which CSV build_dict.dart reads.
  - OCR follow-up: when you're ready for image-only PDFs, the cleanest path is Apple Vision on iOS/macOS (free, ships
  with the OS) and Tesseract on Android/Windows. That's a separate prompt — keep this one focused.
