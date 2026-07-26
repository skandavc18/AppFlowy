import 'dart:convert';
import 'dart:io' show HttpException;
import 'dart:typed_data';

import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'document_viewer_fixtures.dart';

/// A 1x1 transparent GIF.
const _gif = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///'
    'yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

final _gifBytes = base64Decode(_gif.split(',').last);

const _badgeSvg = '<svg xmlns="http://www.w3.org/2000/svg" '
    'width="88" height="20" role="img"><rect width="88" height="20"/></svg>';

/// A sign-in page that answers an image request — note the inline logo.
const _htmlPage = '<!DOCTYPE html><html><head><title>Sign in</title></head>'
    '<body><svg viewBox="0 0 16 16"><path d="M8 0"/></svg></body></html>';

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
      home: Scaffold(body: SizedBox(width: 720, child: child)),
    ),
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  DocumentTypography.debugMonoFamilyOverride = builtInCodeFontFamily;

  setUp(DocumentImageLoader.clearCache);
  tearDown(() {
    DocumentImageLoader.clearCache();
    DocumentImageLoader.clientFactory = http.Client.new;
  });

  group('image length parsing', () {
    test('accepts authored units and rejects relative widths', () {
      expect(parseCssLength('1040'), 1040);
      expect(parseCssLength('1040px'), 1040);
      expect(parseCssLength(' 12.5pt '), 12.5);
      expect(parseCssLength('80%'), isNull);
      expect(parseCssLength('auto'), isNull);
      expect(parseCssLength(null), isNull);
    });

    test('markdown and HTML carry px dimensions through', () {
      final blocks = DocumentNormalizer.fromHtml(
        '<p><img src="https://e.com/a.png" width="1040px" height="520px"></p>',
      );
      final image = blocks.single as DocumentImageBlock;
      expect(image.width, 1040);
      expect(image.height, 520);
    });
  });

  group('SVG detection', () {
    test('trusts the declared content type first', () {
      final raster = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      expect(
        DocumentImageLoader.looksLikeSvg(raster, 'image/svg+xml'),
        isTrue,
      );
      expect(
        DocumentImageLoader.looksLikeSvg(
          Uint8List.fromList(utf8.encode(_badgeSvg)),
          'image/png',
        ),
        isFalse,
      );
    });

    test('sniffs the document root when no type is declared', () {
      expect(
        DocumentImageLoader.looksLikeSvg(
          Uint8List.fromList(utf8.encode(_badgeSvg)),
          null,
        ),
        isTrue,
      );
      expect(
        DocumentImageLoader.looksLikeSvg(
          Uint8List.fromList(
            utf8.encode('<?xml version="1.0"?><svg width="4"></svg>'),
          ),
          null,
        ),
        isTrue,
      );
      expect(
        DocumentImageLoader.looksLikeSvg(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D]),
          null,
        ),
        isFalse,
      );
    });

    test('a web page containing an inline logo is not an SVG image', () {
      final bytes = Uint8List.fromList(utf8.encode(_htmlPage));
      expect(DocumentImageLoader.looksLikeHtml(bytes, null), isTrue);
      expect(DocumentImageLoader.looksLikeSvg(bytes, null), isFalse);
      expect(
        DocumentImageLoader.looksLikeHtml(
          Uint8List.fromList(utf8.encode(_badgeSvg)),
          'text/html; charset=utf-8',
        ),
        isTrue,
      );
    });

    test('reads the intrinsic size from width, height or the view box', () {
      expect(
        DocumentImageLoader.readSvgSize(
          Uint8List.fromList(utf8.encode(_badgeSvg)),
        ),
        const Size(88, 20),
      );
      expect(
        DocumentImageLoader.readSvgSize(
          Uint8List.fromList(
            utf8.encode('<svg viewBox="0 0 24 12"></svg>'),
          ),
        ),
        const Size(24, 12),
      );
      expect(
        DocumentImageLoader.readSvgSize(
          Uint8List.fromList(utf8.encode('<svg></svg>')),
        ),
        isNull,
      );
    });
  });

  group('DocumentImageLoader', () {
    test('returns a vector image for an extension-less badge', () async {
      DocumentImageLoader.clientFactory = () => MockClient(
            (_) async => http.Response(
              _badgeSvg,
              200,
              headers: {'content-type': 'image/svg+xml;charset=utf-8'},
            ),
          );

      final data = await DocumentImageLoader.load(
        'https://img.shields.io/badge/AppFlowy.IO-discord-orange',
      );

      expect(data, isA<DocumentVectorImage>());
      expect(data.intrinsicSize, const Size(88, 20));
    });

    test('returns a measured raster image for a bitmap response', () async {
      DocumentImageLoader.clientFactory = () => MockClient(
            (_) async => http.Response.bytes(
              _gifBytes,
              200,
              headers: {'content-type': 'image/gif'},
            ),
          );

      final data = await DocumentImageLoader.load('https://e.com/a.gif');
      expect(data, isA<DocumentRasterImage>());
      // Measured up front so the layout never shifts once it arrives.
      expect(data.intrinsicSize, const Size(1, 1));
    });

    test('rejects a web page answering an image request', () async {
      DocumentImageLoader.clientFactory = () => MockClient(
            (_) async => http.Response(
              _htmlPage,
              200,
              headers: {'content-type': 'text/html'},
            ),
          );

      await expectLater(
        DocumentImageLoader.load('https://e.com/private.png'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects payloads that cannot be decoded', () async {
      DocumentImageLoader.clientFactory = () => MockClient(
            (_) async => http.Response.bytes(
              Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
              200,
              headers: {'content-type': 'image/png'},
            ),
          );

      await expectLater(
        DocumentImageLoader.load('https://e.com/truncated.png'),
        throwsA(isNotNull),
      );
    });

    test('surfaces transport failures instead of hanging', () async {
      DocumentImageLoader.clientFactory =
          () => MockClient((_) async => http.Response('nope', 404));

      await expectLater(
        DocumentImageLoader.load('https://e.com/missing.png'),
        throwsA(isA<HttpException>()),
      );
    });

    test('loads each source once', () async {
      var requests = 0;
      DocumentImageLoader.clientFactory = () => MockClient((_) async {
            requests++;
            return http.Response(
              _badgeSvg,
              200,
              headers: {'content-type': 'image/svg+xml'},
            );
          });

      const url = 'https://img.shields.io/badge/a-b-c';
      await DocumentImageLoader.load(url);
      await DocumentImageLoader.load(url);
      expect(requests, 1);
    });

    test('decodes data images without a client', () async {
      expect(await DocumentImageLoader.load(_gif), isA<DocumentRasterImage>());
    });

    test('refuses sources the document viewer cannot show', () async {
      await expectLater(
        DocumentImageLoader.load('mailto:a@b.c'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('image layout', () {
    testWidgets('a badge keeps its own size instead of filling the measure',
        (tester) async {
      DocumentImageLoader.clientFactory = () => MockClient(
            (_) async => http.Response(
              _badgeSvg,
              200,
              headers: {'content-type': 'image/svg+xml'},
            ),
          );

      await _pump(
        tester,
        DocumentImageView(
          block: const DocumentImageBlock(
            source: 'https://img.shields.io/badge/a-b-c',
          ),
          typography: DocumentTypography.resolve(sampleDocumentViewerTheme),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SvgPicture));
      expect(size.width, 88);
      expect(size.height, 20);
    });

    testWidgets('a wide image scales down to the reading measure',
        (tester) async {
      DocumentImageLoader.clientFactory = () => MockClient(
            (_) async => http.Response(
              '<svg width="2080" height="1040"></svg>',
              200,
              headers: {'content-type': 'image/svg+xml'},
            ),
          );

      await _pump(
        tester,
        DocumentImageView(
          block: const DocumentImageBlock(
            source: 'https://e.com/hero.svg',
            width: 1040,
            height: 520,
          ),
          typography: DocumentTypography.resolve(sampleDocumentViewerTheme),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SvgPicture));
      expect(size.width, 720);
      expect(size.height, 360);
    });

    testWidgets('a failed image stays a quiet marker', (tester) async {
      DocumentImageLoader.clientFactory =
          () => MockClient((_) async => http.Response('nope', 500));

      await _pump(
        tester,
        DocumentImageView(
          block: const DocumentImageBlock(
            source: 'https://e.com/broken.png',
            alt: 'Kanban board',
          ),
          typography: DocumentTypography.resolve(sampleDocumentViewerTheme),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kanban board'), findsOneWidget);
      // Never a full-width panel dominating the page.
      expect(
        tester.getSize(find.byType(DocumentImageView)).height,
        lessThan(48),
      );
    });

    testWidgets('badge rows stay on one line', (tester) async {
      DocumentImageLoader.clientFactory = () => MockClient(
            (_) async => http.Response(
              _badgeSvg,
              200,
              headers: {'content-type': 'image/svg+xml'},
            ),
          );

      final blocks = DocumentNormalizer.fromHtml('''
        <p align="center">
          <a href="https://discord.gg/x"><img src="https://s.io/a"></a>
          <a href="https://github.com/y"><img src="https://s.io/b"></a>
          <a href="https://github.com/z"><img src="https://s.io/c"></a>
        </p>
      ''');

      final row = blocks.single as DocumentImageRowBlock;
      expect(row.images, hasLength(3));
      expect(row.alignment, TextAlign.center);

      await _pump(
        tester,
        DocumentImageRowView(
          block: row,
          typography: DocumentTypography.resolve(sampleDocumentViewerTheme),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DocumentImageView), findsNWidgets(3));
      // Three 20px badges on one line, not three stacked panels.
      expect(tester.getSize(find.byType(Wrap)).height, lessThan(40));
    });

    testWidgets('prose beside an image keeps both', (tester) async {
      final blocks = DocumentNormalizer.fromHtml(
        '<p>Built with <img src="https://e.com/logo.png"></p>',
      );

      expect(blocks, hasLength(2));
      expect(blocks.first, isA<DocumentParagraphBlock>());
      expect(blocks[1], isA<DocumentImageBlock>());
    });
  });
}
