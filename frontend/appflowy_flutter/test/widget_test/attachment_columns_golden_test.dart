import 'dart:io';

import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _modes = ['light', 'dark', 'paper'];
const _widths = [40.0, 80.0, 250.0];
const _sheet = ValueKey('attachment-columns-reference');
const _samples = [
  ('PDF', 'Quarterly report.PDF', Icons.picture_as_pdf_rounded),
  ('Word', 'Proposal.docx', Icons.text_snippet_rounded),
  ('Excel', 'Budget.xlsx', Icons.table_chart_rounded),
  ('PowerPoint', 'Presentation.pptx', Icons.slideshow_rounded),
  ('Archive', 'Backup.zip', Icons.folder_zip_rounded),
  ('Audio', 'Interview.mp3', Icons.audiotrack_rounded),
  ('Video', 'Recording.mp4', Icons.movie_rounded),
  ('Python', 'Analysis.py', Icons.code_rounded),
  ('Text', 'Notes.txt', Icons.description_rounded),
  ('Unknown', 'Unknown.unrecognized', Icons.insert_drive_file_rounded),
];

// Normal comparisons only; generate the three baselines in a separate run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool fontFetching;
  final loadedFamilies = <String>{};

  setUpAll(() async {
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final mode in _modes) {
      final text = _theme(mode).textTheme;
      loadedFamilies.addAll([
        text.bodyMedium!.fontFamily!,
        text.bodySmall!.fontFamily!,
        text.headlineSmall!.fontFamily!,
      ]);
    }
    for (final family in [...loadedFamilies, 'MaterialIcons']) {
      final asset = family == 'MaterialIcons'
          ? 'fonts/MaterialIcons-Regular.otf'
          : 'assets/google_fonts/DM_Sans/DMSans-Variable.ttf';
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });
  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = fontFetching;
  });

  for (final mode in _modes) {
    testWidgets(
      '$mode: attachment filename and type column reference',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final files = [
          for (final (i, sample) in _samples.indexed)
            MediaFilePB(
              id: 'file-$i',
              name: sample.$2,
              url: 'https://example.invalid/attachments/$i',
              fileType: MediaFileTypePB.Other,
              uploadType: FileUploadTypePB.NetworkFile,
            )..freeze(),
        ];
        final originals = files.map((file) => file.writeToBuffer()).toList();
        var taps = 0;
        var networkAttempts = 0;
        try {
          await HttpOverrides.runZoned(
            () async {
              final theme = _theme(mode);
              final palette = theme.extension<PremiumThemeExtension>()!;
              final defaults = AppFlowyDefaultTheme();
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme,
                  themeAnimationDuration: Duration.zero,
                  builder: (_, child) => AppFlowyTheme(
                    data: PremiumTheme.appFlowyTheme(
                      base: mode == 'dark' ? defaults.dark() : defaults.light(),
                      palette: palette,
                      brightness: theme.brightness,
                    ),
                    child: child!,
                  ),
                  home: _referenceSheet(mode, files, () => taps++),
                ),
              );
              await tester.pumpAndSettle();
              final context = tester.element(find.byKey(_sheet));
              expect(PaperTheme.isEnabled(context), mode == 'paper');
              expect(tester.getSize(find.byKey(_sheet)), const Size(1000, 800));
              expect(find.byType(MediaFileLabel), findsNWidgets(30));
              expect(find.byType(MediaFileThumbnail), findsNWidgets(30));
              // Non-images must remain cheap labels, never image fetches/previews.
              expect(find.byType(AFImage), findsNothing);
              expect(find.byType(Image), findsNothing);
              for (final (i, sample) in _samples.indexed) {
                expect(files[i].isFrozen, isTrue);
                expect(files[i].fileType, MediaFileTypePB.Other);
                for (final width in _widths) {
                  final host = find.byKey(ValueKey('${sample.$1}-$width'));
                  final name = _part(host, 'media-attachment-name-file-$i');
                  final surface = _part(host, 'media-attachment-file-$i');
                  final glyph = _part(host, 'media-file-icon-file-$i');
                  final label = tester.widget<Text>(name);
                  final icon = tester.widget<Icon>(glyph);
                  final bounds = tester.getRect(host);
                  expect(bounds.width, width);
                  for (final child in [surface, name, glyph]) {
                    final rect = tester.getRect(child).deflate(0.01);
                    expect(bounds.contains(rect.topLeft), isTrue);
                    expect(bounds.contains(rect.bottomRight), isTrue);
                  }
                  expect(label.data, sample.$2);
                  expect(label.maxLines, 1);
                  expect(label.overflow, TextOverflow.ellipsis);
                  expect(label.style!.fontFamily, isNot('Ahem'));
                  expect(loadedFamilies, contains(label.style!.fontFamily));
                  expect(label.style!.color, palette.textPrimary);
                  expect(icon.icon, sample.$3);
                  expect(icon.icon!.fontFamily, 'MaterialIcons');
                  expect(icon.color, theme.colorScheme.onSurfaceVariant);
                  expect(tester.getSize(glyph).width, greaterThanOrEqualTo(12));
                  expect(
                    tester.widget<Material>(surface).color,
                    EditorSurfaceStyle.previewBackgroundFor(
                      theme.brightness,
                      palette.surface,
                      isPaper: PaperTheme.isEnabled(context),
                    ),
                  );
                  if (width == 250) {
                    final paragraph = tester.renderObject<RenderParagraph>(
                      find.descendant(
                        of: name,
                        matching: find.byType(RichText),
                      ),
                    );
                    expect(
                      paragraph.didExceedMaxLines,
                      isFalse,
                      reason:
                          'The full original filename must be visible at 250px',
                    );
                  }
                }
              }
              final canvas = tester
                  .widget<Material>(find.byKey(const ValueKey('sheet-canvas')))
                  .color!;
              expect(
                canvas,
                mode == 'paper' ? PaperTheme.editorBackground : palette.canvas,
              );
              if (mode == 'paper') expect(canvas.r, greaterThan(canvas.b));
              expect(find.byType(IconButton), findsNothing);
              expect(find.byType(ErrorWidget), findsNothing);
              expect(networkAttempts, 0);
              expect(taps, 0);
              expect(tester.takeException(), isNull);
              await expectLater(
                find.byKey(_sheet),
                matchesGoldenFile('goldens/attachment_columns_$mode.png'),
              );
              // The 40px specimen invokes only our counter, never native actions.
              await tester.tap(find.byType(MediaFileLabel).first);
              expect(taps, 1);
              expect(files.map((file) => file.writeToBuffer()), originals);
              expect(networkAttempts, 0);
              expect(tester.takeException(), isNull);
            },
            createHttpClient: (_) {
              networkAttempts++;
              throw StateError('No network in attachment references');
            },
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

Finder _part(Finder host, String key) => find.descendant(
      of: host,
      matching: find.byKey(ValueKey(key)),
    );

ThemeData _theme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

/// Real production leaves in reference hosts, not a GridMediaCellSkin replica.
/// Photos have existing goldens; these specimens need no attachment file IO.
Widget _referenceSheet(
  String mode,
  List<MediaFilePB> files,
  VoidCallback onTap,
) =>
    Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final palette = PremiumThemeExtension.of(context);
        final caption =
            theme.textTheme.bodySmall?.copyWith(color: palette.textSecondary);
        Widget row(String title, Widget Function(double) child) => SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(width: 140, child: Text(title)),
                  for (final width in _widths)
                    SizedBox(
                      key: ValueKey('$title-$width'),
                      width: width,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: child(width),
                      ),
                    ),
                ],
              ),
            );
        return RepaintBoundary(
          key: _sheet,
          child: Material(
            key: const ValueKey('sheet-canvas'),
            color: EditorSurfaceStyle.canvasBackgroundFor(
              theme.brightness,
              palette.canvas,
              isPaper: PaperTheme.isEnabled(context),
            ),
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Real attachment cells / widths / ${mode.toUpperCase()}',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'MediaFileLabel + MediaFileThumbnail reference hosts, not a full grid.',
                      style: caption,
                    ),
                    const SizedBox(height: 20),
                    row('File type', (width) => Text('${width.toInt()} px')),
                    for (final (i, sample) in _samples.indexed)
                      row(
                        sample.$1,
                        (_) => MediaFileLabel(file: files[i], onTap: onTap),
                      ),
                    const Spacer(),
                    Text(
                      'DM Sans + Material Icons / no network, backend or native actions.',
                      style: caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
