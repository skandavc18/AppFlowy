import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart'
    show settleVividIconPictures, vividIconTestTheme;

const _appearances = ['light', 'dark', 'paper'];
const _actions = [
  'find-replace',
  'replace-all',
  'rotate',
  'rotate-ccw',
  'fit',
  'fit-page',
  'actual-size',
  'width',
  'print',
  'zoom-in',
  'zoom-out',
  'crop',
  'flip-horizontal',
  'flip-vertical',
  'share',
  'external-link',
  'duplicate',
  'paste-go',
  'scan-document',
  'tree',
  'archive',
  'eye',
  'eye-off',
];

void main() {
  setUp(() {
    svg.cache.clear();
    resetIconPacksForTesting();
    WorkspaceGlyphs.clearUnknownMappings();
  });

  for (final appearance in _appearances) {
    for (final size in [16.0, 18.0]) {
      testWidgets('$appearance/$size every default decodes in both styles',
          (tester) async {
        final assets = _NoIconAssets();
        final names =
            defaultIconNames.where((name) => name != 'unknown').toList();
        expect(names, hasLength(379));
        for (final style in DefaultIconStyle.values) {
          for (var start = 0; start < names.length; start += 36) {
            final chunk = names.skip(start).take(36).toList();
            await tester.pumpWidget(
              _app(
                appearance,
                assets: assets,
                styles: AlwaysStoppedAnimation(style),
                child: SizedBox(
                  width: 400,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final name in chunk)
                        WorkspaceGlyph.named(
                          name,
                          key: ValueKey(name),
                          size: size,
                          semanticLabel: name,
                        ),
                    ],
                  ),
                ),
              ),
            );
            // Decode the actual SvgPicture loaders. No screenshot, fixture
            // image, golden update, asset pack or synthetic replacement painter.
            await settleVividIconPictures(tester);
            expect(find.byType(SvgPicture), findsNWidgets(chunk.length));
            for (final name in chunk) {
              final finder = find.byKey(ValueKey(name));
              final context = tester.element(finder);
              expect(PaperTheme.isEnabled(context), appearance == 'paper');
              expect(
                Theme.of(context).brightness,
                appearance == 'dark' ? Brightness.dark : Brightness.light,
              );
              expect(MediaQuery.textScalerOf(context).scale(1), 2);
              expect(tester.getSize(finder), Size.square(size));
              final picture = _picture(tester, finder);
              expect(picture.width, size);
              expect(picture.height, size);
              expect(picture.semanticsLabel, name);
              final vivid = style == DefaultIconStyle.vivid;
              final expected = vivid
                  ? vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)!
                  : defaultIconSvg(name)!;
              _expectSource(picture, expected);
              expect(
                picture.colorFilter,
                vivid
                    ? null
                    : ColorFilter.mode(
                        workspaceGlyphInk(context),
                        BlendMode.srcIn,
                      ),
                reason: '$appearance/$style/$name',
              );
              if (vivid) {
                expect(
                  find.descendant(
                    of: finder,
                    matching: find.byType(ColorFiltered),
                  ),
                  findsNothing,
                  reason: '$name must display its real illustration colors',
                );
              }
            }
            expect(tester.takeException(), isNull, reason: chunk.join(', '));
          }
        }
        expect(assets.requests, isEmpty);
        expect(iconPacksVersion.value, 0);
        for (final pack in kIconPacks.where((pack) => pack.asset.isNotEmpty)) {
          expect(isIconPackLoaded(pack), isFalse, reason: pack.id);
        }
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('$appearance mounted actions change artwork, not slot or host',
        (tester) async {
      final assets = _NoIconAssets();
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final semantics = tester.ensureSemantics();
      var builds = 0;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            assets: assets,
            styles: styles,
            child: Builder(
              builder: (_) {
                builds++;
                return SizedBox(
                  width: 400,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in _actions)
                        WorkspaceGlyph.named(
                          name,
                          key: ValueKey(name),
                          semanticLabel: name,
                          // Decorative color cannot flatten a vivid drawing.
                          color: Colors.green,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final hostBuilds = builds;
        final elements = {
          for (final name in _actions)
            name: tester.element(find.byKey(ValueKey(name))),
        };
        final rectangles = {
          for (final name in _actions)
            name: tester.getRect(find.byKey(ValueKey(name))),
        };
        final outlines = {
          for (final name in _actions)
            name: _picture(tester, find.byKey(ValueKey(name))).bytesLoader,
        };
        for (final style in [
          DefaultIconStyle.vivid,
          DefaultIconStyle.monochrome,
        ]) {
          styles.value = style;
          await settleVividIconPictures(tester);
          expect(builds, hostBuilds);
          for (final name in _actions) {
            final finder = find.byKey(ValueKey(name));
            final picture = _picture(tester, finder);
            final vivid = style == DefaultIconStyle.vivid;
            expect(tester.element(finder), same(elements[name]));
            expect(tester.getRect(finder), rectangles[name]);
            expect(find.semantics.byLabel(name), findsOneWidget);
            expect(tester.getSemantics(finder).attached, isTrue);
            _expectSource(
              picture,
              vivid
                  ? vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)!
                  : defaultIconSvg(name)!,
            );
            expect(
              picture.colorFilter,
              vivid
                  ? null
                  : const ColorFilter.mode(Colors.green, BlendMode.srcIn),
            );
            if (vivid) {
              expect(picture.bytesLoader, isNot(outlines[name]), reason: name);
              expect(
                WorkspaceGlyphs.vividNameFor(name),
                isNot(startsWith('utility-')),
              );
            } else {
              expect(picture.bytesLoader, outlines[name], reason: name);
            }
          }
        }
        expect(assets.requests, isEmpty);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
        styles.dispose();
      }
    });

    testWidgets(
        '$appearance disabled, destructive and status ink win over vivid',
        (tester) async {
      final assets = _NoIconAssets();
      const statusInk = Color(0xFF478B78);
      late Color disabledInk;
      late Color dangerInk;
      await tester.pumpWidget(
        _app(
          appearance,
          assets: assets,
          styles: const AlwaysStoppedAnimation(DefaultIconStyle.vivid),
          child: Builder(
            builder: (context) {
              disabledInk = Theme.of(context).disabledColor;
              dangerInk = Theme.of(context).colorScheme.error;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WorkspaceGlyphScope(
                    color: disabledInk,
                    role: WorkspaceGlyphRole.preserveInk,
                    child: const IconButton(
                      onPressed: null,
                      icon: WorkspaceGlyph.named(
                        'print',
                        key: ValueKey('disabled'),
                        style: DefaultIconStyle.vivid,
                        role: WorkspaceGlyphRole.standard,
                        color: Colors.pink,
                      ),
                    ),
                  ),
                  WorkspaceGlyph.named(
                    'trash',
                    key: const ValueKey('destructive'),
                    color: dangerInk,
                    role: WorkspaceGlyphRole.preserveInk,
                  ),
                  const WorkspaceGlyphScope(
                    color: statusInk,
                    role: WorkspaceGlyphRole.preserveInk,
                    child: WorkspaceGlyph.named(
                      'cloud-check',
                      key: ValueKey('status'),
                      style: DefaultIconStyle.vivid,
                      role: WorkspaceGlyphRole.standard,
                      color: Colors.pink,
                    ),
                  ),
                  const WorkspaceGlyph.named('print', key: ValueKey('enabled')),
                ],
              );
            },
          ),
        ),
      );
      await settleVividIconPictures(tester);
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      for (final entry in {
        'disabled': ('print', disabledInk),
        'destructive': ('trash', dangerInk),
        'status': ('cloud-check', statusInk),
      }.entries) {
        final picture = _picture(tester, find.byKey(ValueKey(entry.key)));
        _expectSource(picture, defaultIconSvg(entry.value.$1)!);
        expect(
          picture.colorFilter,
          ColorFilter.mode(entry.value.$2, BlendMode.srcIn),
        );
      }
      final enabled = _picture(tester, find.byKey(const ValueKey('enabled')));
      _expectSource(enabled, vividIconSvg('print')!);
      expect(enabled.colorFilter, isNull);
      expect(assets.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('adapter never rewrites saved choices, inline SVGs or uploaded art', () {
    const source =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        '<path fill="#EA5678" d="M2 2h8v20H2z"/>'
        '<path fill="#4589CA" d="M14 2h8v20h-8z"/></svg>';
    final saved = [
      EmojiIconData.emoji('📚'),
      EmojiIconData.custom('C:\\fixture\\chosen.svg'),
      IconsData('appflowy_default_collections', 'book', '4283665274')
          .toEmojiIconData(),
      IconsData('appflowy_vivid_nature', 'tree', null).toEmojiIconData(),
    ];
    final renderers = <Widget>[
      for (final icon in saved) RawEmojiIconWidget(emoji: icon, emojiSize: 18),
      IconWidget(
        size: 18,
        iconsData: IconsData('appflowy_vivid_essentials', 'archive', null),
      ),
      FlowySvg.string(source),
      SvgPicture.string(source),
      const FlowySvg(FlowySvgData('assets/custom/print.svg')),
      const FlowySvg(
        FlowySvgData('assets/flowy_icons/16x/image.svg'),
        blendMode: null,
      ),
    ];
    for (final renderer in renderers) {
      expect(
        WorkspaceGlyph.adapt(
          renderer,
          color: Colors.red,
          role: WorkspaceGlyphRole.preserveInk,
        ),
        same(renderer),
      );
    }
    expect(iconPacksVersion.value, 0);
  });

  testWidgets(
      'an unknown future Material icon keeps its actual source renderer',
      (tester) async {
    const future = IconData(0xffff, fontFamily: 'FutureAction');
    final assets = _NoIconAssets();
    await tester.pumpWidget(
      _app(
        'paper',
        assets: assets,
        styles: const AlwaysStoppedAnimation(DefaultIconStyle.vivid),
        child: const WorkspaceGlyph(future, semanticLabel: 'Future action'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(future), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    expect(WorkspaceGlyphs.unknownMappings, {'FutureAction/ffff'});
    expect(assets.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _app(
  String appearance, {
  required _NoIconAssets assets,
  required ValueListenable<DefaultIconStyle> styles,
  required Widget child,
}) =>
    MaterialApp(
      theme: vividIconTestTheme(appearance),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: DefaultAssetBundle(
        bundle: assets,
        child: DefaultIconStyleScope(
          styles: styles,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

SvgPicture _picture(WidgetTester tester, Finder glyph) =>
    tester.widget<SvgPicture>(
      find.descendant(of: glyph, matching: find.byType(SvgPicture)),
    );

void _expectSource(SvgPicture picture, String source) {
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(
    loader,
    SvgStringLoader(
      source,
      theme: loader.theme,
      colorMapper: loader.colorMapper,
    ),
  );
}

class _NoIconAssets extends CachingAssetBundle {
  final requests = <String>[];

  @override
  Future<ByteData> load(String key) {
    requests.add(key);
    throw StateError('Compiled default icons must not load $key');
  }
}
