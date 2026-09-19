import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_toolbar.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _modes = ['light', 'dark', 'paper'];
const _host = ValueKey('photo-viewer-host');
const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _copied = ValueKey('media-copied');
const _reveal = ValueKey('media-action-reveal');
const _settledFade = Duration(milliseconds: 141);
final _overlay = Colors.black.withValues(alpha: 0.6);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool originalFontFetching;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    originalFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = originalFontFetching;
  });

  for (final mode in _modes) {
    testWidgets(
      '$mode: photo actions match the black groups, hover and visible focus',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final fixture = _Fixture();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await _mount(tester, fixture, mode);
          final viewer = tester.widget<InteractiveImageViewer>(
            find.byType(InteractiveImageViewer),
          );
          expect(viewer.imageProvider, same(fixture.photos));
          expect(viewer.imageProvider, isA<MediaFileImageProvider>());
          expect(find.byType(InteractiveImageToolbar), findsOneWidget);
          expect(_buttons(tester).onDarkSurface, isTrue);
          expect(_buttons(tester).decorated, isFalse);
          expect(_buttons(tester).buttonSize, 32);
          final defaults = MediaActionButtons(source: _buttons(tester).source);
          expect(defaults.onDarkSurface, isFalse);
          expect(defaults.decorated, isTrue);
          expect(defaults.buttonSize, 28);
          final context = tester.element(find.byType(MediaActionButtons));
          expect(PaperTheme.isEnabled(context), mode == 'paper');
          expect(
            Theme.of(context).brightness,
            mode == 'dark' ? Brightness.dark : Brightness.light,
          );

          final groups = find.descendant(
            of: find.byType(InteractiveImageToolbar),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color == _overlay,
            ),
          );
          expect(groups, findsNWidgets(5));
          for (final element in groups.evaluate()) {
            final group = find.byWidget(element.widget);
            final box = tester.widget<DecoratedBox>(group);
            final decoration = box.decoration as BoxDecoration;
            expect(decoration.color, _overlay);
            expect(decoration.borderRadius, BorderRadius.circular(6));
            expect(decoration.border, isNull);
            expect(decoration.boxShadow, isNull);
            expect((box.child! as Padding).padding, const EdgeInsets.all(4));
            expect(tester.getSize(group).height, 40);
          }
          expect(tester.getSize(_group()), const Size(76, 40));
          expect(
            tester.getSize(find.byType(MediaActionButtons)),
            const Size(68, 32),
          );
          expect(
            tester.getTopLeft(find.byType(MediaActionButtons)),
            tester.getTopLeft(_group()) + const Offset(4, 4),
          );
          _expectUnframed(tester);
          for (final key in [_copy, _share]) {
            final style = _button(tester, key).style!;
            expect(tester.getSize(find.byKey(key)), const Size.square(32));
            expect(style.padding!.resolve({}), EdgeInsets.zero);
            expect(style.foregroundColor!.resolve({}), Colors.white);
            expect(_buttonMaterial(tester, key).color!.a, 0);
            expect(
              style.shape!.resolve({}),
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            );
          }
          expect(_iconColor(tester, Icons.copy_rounded), Colors.white);
          expect(_iconColor(tester, Icons.ios_share_rounded), Colors.white);
          expect(_opacity(tester), 0);
          expect(find.byKey(_copy).hitTestable(), findsNothing);
          expect(find.semantics.byLabel('Copy'), findsNothing);
          expect(find.semantics.byLabel('Share'), findsNothing);
          final state = tester.state(find.byType(MediaActionButtons));

          await mouse.moveTo(tester.getCenter(find.byKey(_host)));
          await _motion(tester);
          _expectSemantics(tester, _copy, 'Copy');
          _expectSemantics(tester, _share, 'Share');
          final copyNode = tester.getSemantics(find.byKey(_copy));
          expect(_opacity(tester), 1);
          for (final element in groups.evaluate()) {
            expect(
              tester.getCenter(find.byWidget(element.widget)).dy,
              closeTo(tester.getCenter(_group()).dy, 0.01),
            );
          }
          await mouse.moveTo(tester.getCenter(find.byKey(_copy)));
          await _motion(tester);
          final hover = _buttonMaterial(tester, _copy).color!;
          expect(hover, Colors.white.withValues(alpha: 0.1));
          _expectContrast(
            _iconColor(tester, Icons.copy_rounded),
            background: Color.alphaBlend(
              hover,
              Color.alphaBlend(_overlay, Colors.white),
            ),
          );
          expect(fixture.actions.calls, isEmpty);

          await mouse.moveTo(Offset.zero);
          await tester.pump();
          expect(find.byKey(_copy).hitTestable(), findsNothing);
          expect(find.byKey(_share).hitTestable(), findsNothing);
          expect(find.semantics.byLabel('Copy'), findsNothing);
          expect(find.semantics.byLabel('Share'), findsNothing);
          expect(copyNode.attached, isFalse);
          await tester.pump(_settledFade);
          expect(_opacity(tester), 0);

          for (final key in [_copy, _share]) {
            await _tabTo(tester, _button(tester, key).focusNode!);
            expect(_opacity(tester), 1);
            expect(find.byKey(key).hitTestable(), findsOneWidget);
            final node = tester.getSemantics(find.byKey(key));
            expect(node.hasFlag(ui.SemanticsFlag.isFocused), isTrue);
            final shape = _buttonMaterial(tester, key).shape! as OutlinedBorder;
            expect(shape.side.width, greaterThanOrEqualTo(1));
            expect(shape.side.color, Colors.white);
            _expectContrast(shape.side.color);
          }
          expect(tester.state(find.byType(MediaActionButtons)), same(state));
          expect(fixture.actions.calls, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      '$mode: pending, copied and error feedback keep overlay contrast',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final fixture = _Fixture();
        try {
          await _mount(tester, fixture, mode);
          await _tabTo(tester, _button(tester, _copy).focusNode!);
          final bounds = _bounds(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _motion(tester);
          final copy = fixture.actions.calls.single;
          expect(copy.kind, 'copy');
          expect(copy.source.source, fixture.photos.files.first.url);
          expect(copy.source.name, fixture.photos.files.first.name);
          expect(copy.source.isImage, isTrue);
          expect(copy.source.httpHeaders, isEmpty);
          for (final key in [_copy, _share]) {
            expect(_button(tester, key).onPressed, isNull);
            expect(
              _button(tester, key)
                  .style!
                  .foregroundColor!
                  .resolve({WidgetState.disabled}),
              Colors.white.withValues(alpha: 0.4),
            );
            expect(_buttonMaterial(tester, key).color!.a, 0);
          }
          _expectSemantics(tester, _copy, 'Copy', enabled: false);
          _expectSemantics(tester, _share, 'Share', enabled: false);
          expect(
            _iconColor(tester, Icons.ios_share_rounded),
            Colors.white.withValues(alpha: 0.4),
          );
          _expectProgress(tester);
          expect(_opacity(tester), 1);
          expect(find.byKey(_copied), findsNothing);
          expect(_bounds(tester), bounds);

          final deadline = tester.binding.clock.now().add(
                const Duration(milliseconds: 1600),
              );
          copy.done.complete();
          await _motion(tester);
          expect(_button(tester, _copy).focusNode!.hasFocus, isTrue);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(_iconColor(tester, Icons.check_rounded), Colors.white);
          _expectBadge(tester);
          _expectSemantics(tester, _copy, 'Copied', liveRegion: true);
          _expectSemantics(tester, _share, 'Share');
          expect(find.semantics.byLabel('Copied'), findsOneWidget);
          expect(_bounds(tester), bounds);
          await tester.pump(
            deadline.difference(tester.binding.clock.now()) -
                const Duration(milliseconds: 1),
          );
          expect(find.byKey(_copied), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 1));
          _expectSemantics(tester, _copy, 'Copy');
          await tester.pump(_settledFade);
          expect(find.byKey(_copied), findsNothing);

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          fixture.actions.calls.last.done.completeError(
            StateError('synthetic-private-detail'),
          );
          await _motion(tester);
          _expectError(tester, _copy, LocaleKeys.message_copy_fail.tr());

          await _tabTo(tester, _button(tester, _share).focusNode!);
          final anchor = tester.getRect(find.byKey(_share));
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await _motion(tester);
          final share = fixture.actions.calls.last;
          expect(share.kind, 'share');
          expect(share.source, copy.source);
          expect(share.origin, anchor);
          _expectProgress(tester);
          share.done.completeError(StateError('synthetic-private-detail'));
          await _motion(tester);
          _expectError(
            tester,
            _share,
            LocaleKeys.mediaActions_shareFailed.tr(),
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          fixture.actions.calls.last.done.complete();
          await _motion(tester);
          _expectSemantics(tester, _share, 'Share');
          expect(find.byKey(_copied), findsNothing);
          expect(find.byIcon(Icons.check_rounded), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
          expect(fixture.actions.calls, hasLength(4));
          expect(_bounds(tester), bounds);
          _expectUnframed(tester);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final fail in [false, true]) {
    testWidgets(
      'navigation preserves the dark controls and rejects stale '
      '${fail ? 'failure' : 'success'}',
      (tester) async {
        final fixture = _Fixture();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await _mount(tester, fixture, 'paper');
          await mouse.moveTo(tester.getCenter(find.byKey(_host)));
          await _motion(tester);
          final state = tester.state(find.byType(MediaActionButtons));
          final staleShare = _button(tester, _share).onPressed!;
          await tester.tap(find.byKey(_copy));
          await tester.pump();
          final pending = fixture.actions.calls.single;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await _motion(tester);
          expect(find.byKey(const ValueKey('photo-second')), findsOneWidget);
          expect(_buttons(tester).source.source, fixture.photos.files.last.url);
          expect(_buttons(tester).onDarkSurface, isTrue);
          expect(_button(tester, _copy).onPressed, isNull);
          expect(_button(tester, _share).onPressed, isNull);
          staleShare();
          expect(fixture.actions.calls, hasLength(1));
          if (fail) {
            pending.done.completeError(StateError('obsolete operation'));
          } else {
            pending.done.complete();
          }
          await _motion(tester);
          expect(find.byKey(_copied), findsNothing);
          expect(find.byIcon(Icons.check_rounded), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
          expect(_button(tester, _copy).tooltip, 'Copy');
          expect(tester.state(find.byType(MediaActionButtons)), same(state));

          await tester.tap(find.byKey(_copy));
          await tester.pump();
          expect(
            fixture.actions.calls.last.source.name,
            fixture.photos.files.last.name,
          );
          fixture.actions.calls.last.done.complete();
          await _motion(tester);
          _expectBadge(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          expect(find.byKey(_copied), findsNothing);
          expect(find.byIcon(Icons.check_rounded), findsNothing);
          expect(
            _buttons(tester).source.source,
            fixture.photos.files.first.url,
          );
          staleShare();
          expect(fixture.actions.calls, hasLength(2));
          await tester.tap(find.byKey(_share));
          await tester.pump();
          expect(fixture.actions.calls.last.kind, 'share');
          expect(
            fixture.actions.calls.last.source.name,
            fixture.photos.files.first.name,
          );
          fixture.actions.calls.last.done.complete();
          await _motion(tester);
          expect(find.byKey(_copied), findsNothing);
          expect(tester.state(find.byType(MediaActionButtons)), same(state));
          _expectUnframed(tester);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

class _Fixture {
  final photos = _Photos();
  final actions = _Actions();

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final call in actions.calls) {
      if (!call.done.isCompleted) call.done.complete();
    }
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  }
}

// Only decoding is replaced; file filtering, names and source selection are real.
class _Photos extends MediaFileImageProvider {
  _Photos()
      : super(
          initialFileId: 'first',
          files: [
            for (final id in ['first', 'second'])
              MediaFilePB(
                id: id,
                name: '$id original.png',
                url: 'synthetic/$id.png',
                fileType: MediaFileTypePB.Image,
                uploadType: FileUploadTypePB.LocalFile,
              ),
          ],
        );

  @override
  Widget renderImage(
    BuildContext context,
    int index, [
    UserProfilePB? userProfile,
  ]) =>
      ColoredBox(
        key: ValueKey('photo-${files[index].id}'),
        color: Colors.white,
      );
}

class _Actions extends Fake implements MediaActionService {
  final calls = <_Call>[];

  @override
  Future<void> copy(MediaActionSource source) => _begin('copy', source, null);

  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _begin('share', source, sharePositionOrigin);

  Future<void> _begin(String kind, MediaActionSource source, Rect? origin) {
    final call = _Call(kind, source, origin);
    calls.add(call);
    return call.done.future;
  }
}

class _Call {
  _Call(this.kind, this.source, this.origin);
  final String kind;
  final MediaActionSource source;
  final Rect? origin;
  final done = Completer<void>();
}

MediaActionButtons _buttons(WidgetTester tester) =>
    tester.widget<MediaActionButtons>(find.byType(MediaActionButtons));

IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

Finder _group() => find
    .ancestor(
      of: find.byType(MediaActionButtons),
      matching: find.byType(DecoratedBox),
    )
    .first;

Material _buttonMaterial(WidgetTester tester, Key key) =>
    tester.widget<Material>(
      find.descendant(of: find.byKey(key), matching: find.byType(Material)),
    );

Color _iconColor(WidgetTester tester, IconData data) {
  final finder = find.byIcon(data);
  final icon = tester.widget<Icon>(finder);
  expect(icon.size, 16);
  return icon.color ?? IconTheme.of(tester.element(finder)).color!;
}

void _expectUnframed(WidgetTester tester) {
  final surface = tester.widget<DecoratedBox>(
    find.byKey(const ValueKey('media-action-surface')),
  );
  final decoration = surface.decoration as BoxDecoration;
  expect(decoration.color, isNull);
  expect(decoration.border, isNull);
  expect(decoration.boxShadow, isNull);
  expect((surface.child! as Material).type, MaterialType.transparency);
}

void _expectSemantics(
  WidgetTester tester,
  Key key,
  String label, {
  bool enabled = true,
  bool liveRegion = false,
}) {
  final node = tester.getSemantics(find.byKey(key));
  expect(node.attached, isTrue);
  expect(find.semantics.byLabel(label).evaluate(), contains(same(node)));
  expect(node.label, label);
  expect(node.tooltip, isEmpty);
  expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(node.hasFlag(ui.SemanticsFlag.hasEnabledState), isTrue);
  expect(node.hasFlag(ui.SemanticsFlag.isEnabled), enabled);
  expect(node.hasFlag(ui.SemanticsFlag.isLiveRegion), liveRegion);
  expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), enabled);
}

void _expectProgress(WidgetTester tester) {
  final progress = tester.widget<CircularProgressIndicator>(
    find.byType(CircularProgressIndicator),
  );
  expect(progress.color, Colors.white.withValues(alpha: 0.65));
  expect(progress.value, isNull);
  _expectContrast(progress.color!);
}

void _expectBadge(WidgetTester tester) {
  final badge = find.byKey(_copied);
  final text = tester.widget<Text>(badge);
  expect(text.data, 'Copied');
  expect(text.style!.fontSize, 10);
  expect(text.style!.color, Colors.white);
  final decoration = tester
      .widget<DecoratedBox>(
        find.ancestor(of: badge, matching: find.byType(DecoratedBox)).first,
      )
      .decoration as BoxDecoration;
  expect(decoration.color, _overlay);
  expect(decoration.borderRadius, BorderRadius.circular(6));
  _expectContrast(text.style!.color!, minimum: 4.5);
  expect(
    tester.getRect(badge).bottom,
    lessThan(tester.getRect(find.byType(MediaActionButtons)).top),
  );
  final host = tester.getRect(find.byKey(_host));
  expect(host.contains(tester.getTopLeft(badge)), isTrue);
  expect(host.contains(tester.getBottomRight(badge)), isTrue);
  expect(
    tester
        .widget<IgnorePointer>(
          find.ancestor(of: badge, matching: find.byType(IgnorePointer)).first,
        )
        .ignoring,
    isTrue,
  );
  expect(
    tester
        .widget<ExcludeSemantics>(
          find
              .ancestor(of: badge, matching: find.byType(ExcludeSemantics))
              .first,
        )
        .excluding,
    isTrue,
  );
}

void _expectError(WidgetTester tester, Key key, String label) {
  expect(_button(tester, key).tooltip, label);
  _expectSemantics(tester, key, label, liveRegion: true);
  final ink = _iconColor(tester, Icons.error_outline_rounded);
  expect(ink, Colors.white);
  _expectContrast(ink);
  expect(find.byKey(_copied), findsNothing);
  expect(find.byIcon(Icons.check_rounded), findsNothing);
  expect(find.textContaining('synthetic-private-detail'), findsNothing);
  _expectUnframed(tester);
}

void _expectContrast(Color ink, {Color? background, double minimum = 3}) {
  // White photo pixels are the least favorable backdrop for this black overlay.
  final backdrop = background ?? Color.alphaBlend(_overlay, Colors.white);
  final foreground = Color.alphaBlend(ink, backdrop);
  expect(
    (foreground.computeLuminance() + 0.05) /
        (backdrop.computeLuminance() + 0.05),
    greaterThanOrEqualTo(minimum),
  );
}

List<Rect> _bounds(WidgetTester tester) => [
      tester.getRect(find.byKey(_host)),
      tester.getRect(_group()),
      tester.getRect(find.byType(MediaActionButtons)),
      tester.getRect(find.byKey(_copy)),
      tester.getRect(find.byKey(_share)),
    ];

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(_reveal),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_settledFade);
}

Future<void> _tabTo(WidgetTester tester, FocusNode target) async {
  for (var step = 0; step < 10 && !target.hasFocus; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _motion(tester);
  }
  expect(target.hasFocus, isTrue);
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  String mode,
) async {
  final theme = DesktopAppearance()
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
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: theme,
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => AppFlowyTheme(
            data: appTheme,
            child: TooltipVisibility(visible: false, child: child!),
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                key: _host,
                width: 640,
                height: 420,
                child: LayoutBuilder(
                  builder: (context, constraints) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: constraints.biggest,
                    ),
                    child: InteractiveImageViewer(
                      imageProvider: fixture.photos,
                      actions: fixture.actions,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
