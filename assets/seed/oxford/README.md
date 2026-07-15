# Bundled Oxford reading-tree library

This directory holds `.book.zip` files produced by the macOS-only
**"Bake seed library"** admin action. On first install the app imports
every zip in here into the user's library, then never touches it again
(tracked via the `oxford_seeded` pref).

The zips are large (~100–200 MB total for the full set) so they are
gitignored — only this README is tracked. Rebake whenever the source
PDFs change:

1. `flutter run -d macos` from the repo root
2. Admin → Bake seed library → pick the source PDF folder
3. Wait for the progress dialog to finish
4. `flutter build ios|apk` to ship the new library
