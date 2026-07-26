import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: DesktopAppearance().getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  // Resolve type from bundled faces; a unit test never reaches the network.
  GoogleFonts.config.allowRuntimeFetching = false;
  DocumentTypography.debugMonoFamilyOverride = builtInCodeFontFamily;

  group('document metadata formatting', () {
    test('formats byte sizes without trailing noise', () {
      expect(formatDocumentBytes(0), '0 B');
      expect(formatDocumentBytes(512), '512 B');
      expect(formatDocumentBytes(1024), '1 KB');
      expect(formatDocumentBytes(1536), '1.5 KB');
      expect(formatDocumentBytes(1024 * 1024), '1 MB');
      expect(formatDocumentBytes(1024 * 1024 * 1024 * 3), '3 GB');
    });

    test('formats timestamps the way a reader thinks about them', () {
      final now = DateTime(2026, 7, 25, 12);
      expect(
        formatDocumentTimestamp(
          now.subtract(const Duration(seconds: 20)),
          now: now,
        ),
        'Just now',
      );
      expect(
        formatDocumentTimestamp(
          now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        '5 min ago',
      );
      expect(
        formatDocumentTimestamp(
          now.subtract(const Duration(hours: 3)),
          now: now,
        ),
        '3 hr ago',
      );
      expect(
        formatDocumentTimestamp(
          now.subtract(const Duration(days: 2)),
          now: now,
        ),
        '2 d ago',
      );
      expect(
        formatDocumentTimestamp(DateTime(2026, 3, 4), now: now),
        'Mar 4',
      );
      expect(
        formatDocumentTimestamp(DateTime(2021, 3, 4), now: now),
        'Mar 4, 2021',
      );
    });

    test('joins the identity subtitle from what is known', () {
      const bare = DocumentIdentity(title: 'a.md', icon: Icons.article);
      expect(bare.subtitle, isEmpty);

      final full = DocumentIdentity(
        title: 'a.md',
        icon: Icons.article,
        typeLabel: 'Markdown',
        byteSize: 2048,
        modified: DateTime.now(),
      );
      expect(full.subtitle, startsWith('Markdown  ·  2 KB  ·  '));
    });
  });

  group('DocumentHeader', () {
    testWidgets('shows identity and actions, and nothing else', (tester) async {
      await _pump(
        tester,
        DocumentHeader(
          identity: DocumentIdentity(
            title: 'Quarterly report.md',
            icon: Icons.article_outlined,
            typeLabel: 'Markdown',
            byteSize: 4096,
            modified: DateTime.now(),
            breadcrumbs: const ['Workspace', 'Reports'],
          ),
          actions: const [
            DocumentToolbarButton(
              icon: Icons.download_rounded,
              tooltip: 'Download',
              onPressed: null,
            ),
          ],
        ),
      );

      expect(find.text('Quarterly report.md'), findsNothing);
      expect(find.textContaining('Quarterly report.md'), findsOneWidget);
      expect(find.textContaining('Markdown'), findsOneWidget);
      expect(find.textContaining('4 KB'), findsOneWidget);
      expect(find.textContaining('Workspace'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);

      // Compact chrome, never a Material AppBar or ribbon.
      expect(find.byType(AppBar), findsNothing);
      final header = tester.getSize(find.byType(DocumentHeader));
      expect(header.height, DocumentViewerTheme.chromeHeight);
    });

    testWidgets('drops the metadata line when dense', (tester) async {
      await _pump(
        tester,
        DocumentHeader(
          dense: true,
          identity: DocumentIdentity(
            title: 'notes.txt',
            icon: Icons.description_outlined,
            typeLabel: 'Text',
            modified: DateTime.now(),
          ),
        ),
      );

      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.textContaining('Text  ·'), findsNothing);
    });
  });

  group('DocumentToolbar', () {
    testWidgets('renders premium controls without Material chrome',
        (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        Center(
          child: DocumentToolbar(
            children: [
              DocumentToolbarButton(
                icon: Icons.remove_rounded,
                tooltip: 'Zoom out',
                onPressed: () => pressed++,
              ),
              const DocumentToolbarLabel(label: '100%'),
              const DocumentToolbarSeparator(),
              const DocumentToolbarButton(
                icon: Icons.add_rounded,
                tooltip: 'Zoom in',
                onPressed: null,
              ),
            ],
          ),
        ),
      );

      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      expect(find.text('100%'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_rounded));
      expect(pressed, 1);

      // Disabled controls stay inert.
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(pressed, 1);

      final button = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.remove_rounded),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(button.width, DocumentViewerTheme.controlSize);
      expect(button.height, DocumentViewerTheme.controlSize);
    });
  });

  group('DocumentViewerShell', () {
    testWidgets('frames every document identically', (tester) async {
      final controller = DocumentScrollController();
      addTearDown(controller.dispose);

      await _pump(
        tester,
        SizedBox(
          height: 480,
          child: DocumentViewerShell(
            identity: const DocumentIdentity(
              title: 'report.pdf',
              icon: Icons.picture_as_pdf_outlined,
              typeLabel: 'PDF',
            ),
            floatingToolbar: const DocumentToolbar(
              children: [
                DocumentToolbarLabel(label: '1 / 12'),
              ],
            ),
            body: DocumentViewport.child(
              controller: controller,
              child: const SizedBox(height: 900),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DocumentHeader), findsOneWidget);
      expect(find.byType(DocumentViewport), findsOneWidget);
      expect(find.text('1 / 12'), findsOneWidget);
      // The opening animation is a fade with a restrained scale settle.
      expect(find.byType(DocumentReveal), findsOneWidget);
    });

    testWidgets('notices stay calm and offer a way forward', (tester) async {
      var retried = 0;
      await _pump(
        tester,
        SizedBox(
          height: 300,
          child: DocumentNotice(
            icon: Icons.error_outline_rounded,
            title: 'This document could not be opened',
            message: 'The file is unavailable.',
            actionLabel: 'Try again',
            onAction: () => retried++,
          ),
        ),
      );

      expect(find.text('This document could not be opened'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });
  });
}
