# Seed assets

This directory is intentionally near-empty. On first launch the app generates
three procedural images programmatically via `image` package
(`lib/services/seed_service.dart`) and inserts a "Sample Book" so the reader
is immediately usable.

If you'd like to ship pre-made images instead, drop CC0/original `.jpg` files
here and change `SeedService._writeImage` to read from `rootBundle` rather
than generate.
