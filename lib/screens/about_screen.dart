import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/license_service.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appName = 'Picture Book';
  static const _version = '1.0.0';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final license = context.watch<LicenseService>().current;
    final t = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 60,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _appName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Center(
              child: Text(
                'Version $_version',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.outline,
                    ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(child: _OfflineBadge()),
            if (license != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  t.licensedTo(license.customer),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                ),
              ),
              if (license.issuedAtIso.isNotEmpty)
                Center(
                  child: Text(
                    '${license.tier} · ${license.issuedAtIso}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                        ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            const _Section(
              title: 'What this app does',
              body:
                  'Picture Book is a bilingual (English / Chinese) tap-to-read '
                  'picture-book reader designed for young learners. Children '
                  'tap a word to see its meaning or a sentence to hear it '
                  'spoken aloud. Teachers and parents add their own books '
                  'from PDFs or page-by-page.',
            ),
            const _Section(
              title: 'Privacy',
              body:
                  'The app makes no network connections at all. Every book, '
                  'every translation, every spoken sentence stays on this '
                  'device. There is no analytics, no cloud sync, no tracking. '
                  'When you uninstall the app, the data goes with it.',
            ),
            const _Section(
              title: 'License',
              body:
                  'Released under the MIT license. The bundled English-to-'
                  'Chinese dictionary is built from ECDICT (MIT). The fonts, '
                  'colours, and code are original.',
            ),
            const _Section(
              title: 'Built with',
              body:
                  'Flutter, sqflite, flutter_tts, pdfrx, Apple Vision OCR. '
                  'Voice quality depends on the system voice the user has '
                  'installed — install a Premium voice for the best result.',
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Made with care for early readers.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 6),
          Text(
            '100% Offline',
            style: TextStyle(
              color: scheme.onTertiaryContainer,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
