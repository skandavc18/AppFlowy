import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:archive/archive.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/testing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'test_asset_bundle.dart';

const _routeKey = ValueKey('archive-fullscreen');
const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _copied = ValueKey('media-copied');
const _close = ValueKey('archive-fullscreen-close');
const _name = 'Original # 100% 文.zip';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File file;
  late List<int> archiveBytes;
  late bool fontFetching;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in ['light', 'dark', 'paper']
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('archive-fullscreen-actions-');
    // A real empty ZIP avoids every entry renderer/native boundary. Its disk
    // cache name intentionally differs from the original archive's name.
    archiveBytes = ZipEncoder().encode(Archive())!;
    file = await File('${directory.path}/materialized-archive.bin')
        .writeAsBytes(archiveBytes, flush: true);
  });

  tearDown(() async {
    // Strict cleanup of synthetic test data only; never suppress leaked handles.
    await directory.delete(recursive: true);
  });

  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = fontFetching;
  });

  test('ArchiveExplorer keeps the compatible const service default', () {
    expect(
      ArchiveExplorer(file: file, name: _name).mediaActions,
      same(const MediaActionService()),
    );
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final scale in [1.0, 2.0]) {
      for (final editable in [false, true]) {
        testWidgets(
            'archive route $mode/$scale editable=$editable: real file, retained hover, badge clearance',
            (tester) async {
          final actions = _Actions();
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          try {
            await mouse.addPointer(location: const Offset(900, 900));
            await _open(
              tester,
              file: file,
              actions: actions,
              mode: mode,
              scale: scale,
              editable: editable,
              size: const Size(320, 380),
            );
            final explorer = _inRoute(find.byType(ArchiveExplorer));
            final originalWidget = tester.widget(explorer);
            final originalState = tester.state(explorer);
            final originalBounds = tester.getRect(explorer);
            final source = tester
                .widget<MediaActionButtons>(
                  _inRoute(find.byType(MediaActionButtons)),
                )
                .source;
            expect(source.source, file.path);
            expect(source.name, _name);
            expect(source.isImage, isFalse);
            expect(source.shareAsLink, isFalse);
            expect(source.httpHeaders, isEmpty);
            expect(source.requireAuthentication, isFalse);
            expect(
              _inRoute(find.byType(ViewerCard)),
              findsNothing,
              reason: 'Expanded archive adds no nested cards',
            );
            final surface = tester
                .widget<DecoratedBox>(
                  _inRoute(find.byKey(const ValueKey('media-action-surface'))),
                )
                .decoration as BoxDecoration;
            expect(surface.color, isNull);
            expect(surface.border, isNull);
            expect(surface.boxShadow, isNull);
            final routeContext = tester.element(find.byKey(_routeKey));
            expect(
              tester.widget<Scaffold>(find.byKey(_routeKey)).backgroundColor,
              FolderExplorerPalette.of(routeContext).background,
            );
            expect(PaperTheme.isEnabled(routeContext), mode == 'paper');
            expect(_inRoute(find.byKey(_copy)).hitTestable(), findsNothing);
            await tester.tapAt(tester.getCenter(_inRoute(find.byKey(_copy))));
            expect(actions.calls, isEmpty);
            await mouse.moveTo(const Offset(30, 200));
            await _motion(tester);
            expect(_inRoute(find.byKey(_copy)).hitTestable(), findsOneWidget);
            await mouse.moveTo(tester.getCenter(_inRoute(find.byKey(_share))));
            await _motion(tester);
            expect(_reveal(tester).opacity, 1);
            expect(tester.widget(explorer), same(originalWidget));
            expect(tester.state(explorer), same(originalState));
            expect(tester.getRect(explorer), originalBounds);
            await tester.tap(_inRoute(find.byKey(_copy)));
            await tester.pump();
            expect(actions.calls.single.source, source);
            expect(_button(tester, _share).onPressed, isNull);
            expect(_inRoute(find.byKey(_copied)), findsNothing);
            actions.calls.single.succeed();
            await _motion(tester);
            final badge = tester.getRect(_inRoute(find.byKey(_copied)));
            final bounds = tester.getRect(find.byKey(_routeKey));
            expect(badge.top, greaterThanOrEqualTo(bounds.top));
            expect(badge.left, greaterThanOrEqualTo(bounds.left));
            expect(
              badge.right,
              lessThan(tester.getRect(_inRoute(find.byKey(_close))).left),
            );
            expect(
              badge.bottom,
              lessThan(tester.getRect(_inRoute(find.byKey(_copy))).top),
            );
            expect(badge.bottom, lessThan(originalBounds.top));
            expect(tester.getRect(explorer), originalBounds);
            await tester.tap(_inRoute(find.byKey(_share)));
            await tester.pump();
            expect(actions.calls.last.kind, 'share');
            expect(actions.calls.last.source, source);
            expect(
              actions.calls.last.origin,
              tester.getRect(_inRoute(find.byKey(_share))),
            );
            actions.calls.last.succeed();
            await _motion(tester);
            expect(_inRoute(find.byKey(_copied)), findsNothing);
            await tester.tap(_inRoute(find.byKey(_close)));
            await tester.pumpAndSettle();
            expect(find.byKey(_routeKey), findsNothing);
            expect(await tester.runAsync(file.readAsBytes), archiveBytes);
            expect(tester.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await _unmount(tester, actions);
          }
        });
      }
    }
  }

  for (final reduced in [false, true]) {
    testWidgets(
        'archive route: Tab/Enter/Space retain focus and pending state (reduced=$reduced)',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _Actions();
      try {
        await _open(tester, file: file, actions: actions, reduced: reduced);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        expect(find.semantics.byLabel('Share'), findsNothing);
        await _tabTo(tester, _button(tester, _copy).focusNode!);
        expect(find.semantics.byLabel('Copy'), findsOneWidget);
        expect(_reveal(tester).opacity, 1);
        expect(
          _reveal(tester).duration,
          reduced ? Duration.zero : const Duration(milliseconds: 140),
        );
        expect(
          tester
              .getSemantics(_inRoute(find.byKey(_copy)))
              .hasFlag(ui.SemanticsFlag.isButton),
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        expect(actions.calls.single.kind, 'copy');
        expect(_button(tester, _share).onPressed, isNull);
        expect(_reveal(tester).opacity, 1);
        actions.calls.single.succeed();
        await _motion(tester);
        expect(_button(tester, _copy).focusNode!.hasFocus, isTrue);
        await _tabTo(tester, _button(tester, _share).focusNode!);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(actions.calls.last.kind, 'share');
        actions.calls.last.succeed();
        await _motion(tester);
        FocusManager.instance.primaryFocus?.unfocus();
        await _motion(tester);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        expect(find.semantics.byLabel('Share'), findsNothing);
        expect(_inRoute(find.byKey(_copy)).hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _unmount(tester, actions);
      }
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('archive route $platform: touch actions do not require hover',
        (tester) async {
      final actions = _Actions();
      try {
        await _open(tester, file: file, actions: actions, platform: platform);
        expect(_inRoute(find.byKey(_copy)).hitTestable(), findsOneWidget);
        expect(_inRoute(find.byKey(_share)).hitTestable(), findsOneWidget);
        await tester.tap(_inRoute(find.byKey(_share)));
        await tester.pump();
        expect(actions.calls.single.source.source, file.path);
        actions.calls.single.succeed();
        await _motion(tester);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, actions);
      }
    });
  }

  testWidgets(
      'embedded archive forwards the service beyond its parent-only toolbar',
      (tester) async {
    final actions = _Actions();
    try {
      await _mount(
        tester,
        child: ArchiveExplorer(
          file: file,
          name: _name,
          mediaActions: actions,
          toolbarTrailing: const Text('Parent-only toolbar'),
        ),
      );
      await _until(
        tester,
        () => find.byTooltip('Open full window').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Open full window'));
      await _ready(tester);
      expect(_inRoute(find.text('Parent-only toolbar')), findsNothing);
      expect(_inRoute(find.byType(MediaActionButtons)), findsOneWidget);
      expect(
        tester
            .widget<MediaActionButtons>(
              _inRoute(find.byType(MediaActionButtons)),
            )
            .actions,
        same(actions),
      );
      await _tabTo(tester, _button(tester, _share).focusNode!);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(actions.calls.single.source.source, file.path);
      expect(actions.calls.single.source.name, _name);
      actions.calls.single.succeed();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
    }
  });

  testWidgets(
      'workspace archive preserves its injected service and actual materialized file',
      (tester) async {
    final actions = _Actions();
    try {
      await _mount(
        tester,
        child: WorkspaceFileView(
          view: ViewPB(id: 'synthetic-archive', name: _name),
          mediaActions: actions,
          resolveStorageUrl: (_) async => 'https://cloud.example.test/archive',
          materializeFile: ({required source, required name}) async => file,
        ),
      );
      await _until(
        tester,
        () => find.byType(ArchiveGallery).evaluate().isNotEmpty,
      );
      final explorer =
          tester.widget<ArchiveExplorer>(find.byType(ArchiveExplorer));
      expect(explorer.file.path, file.path);
      expect(explorer.name, _name);
      expect(explorer.mediaActions, same(actions));
      expect(explorer.editable, isFalse);
      expect(explorer.embedded, isFalse);
      final source = tester
          .widget<MediaActionButtons>(find.byType(MediaActionButtons))
          .source;
      expect(source.source, file.path);
      expect(source.httpHeaders, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
    }
  });

  for (final action in [_copy, _share]) {
    testWidgets('archive route: closing during $action rejects late feedback',
        (tester) async {
      final actions = _Actions();
      try {
        await _open(tester, file: file, actions: actions, accessible: true);
        final route = ModalRoute.of(tester.element(find.byKey(_routeKey)))!;
        expect(route.transitionDuration, Duration.zero);
        expect(route.reverseTransitionDuration, Duration.zero);
        final retained = _button(tester, action).onPressed!;
        await tester.tap(_inRoute(find.byKey(action)));
        await tester.pump();
        expect(actions.calls, hasLength(1));
        await tester.tap(_inRoute(find.byKey(_close)));
        // Accessible navigation must dismiss without an exit animation,
        // even while the operation owns a busy spinner.
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(find.byKey(_routeKey), findsNothing);
        retained();
        actions.calls.single.fail();
        await _motion(tester);
        expect(actions.calls, hasLength(1));
        expect(find.byKey(_copied), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, actions);
      }
    });
  }

  testWidgets(
      'archive route: real copy/share preparation hands off the archive bytes and original name',
      (tester) async {
    final clipboard = _Clipboard();
    final shared = <XFile>[];
    final names = <List<String>?>[];
    final client = MockClient(
      (_) async =>
          throw StateError('An archive export must not make an HTTP request'),
    );
    final actions = MediaActionService(
      clipboard: () => clipboard,
      shareFiles: (files, {sharePositionOrigin, fileNameOverrides}) async {
        shared.addAll(files);
        names.add(fileNameOverrides);
        return ShareResult.unavailable;
      },
      shareText: (_, {sharePositionOrigin}) async =>
          throw StateError('An archive must not be shared as a link'),
      httpClient: client,
      temporaryDirectory: () async => directory,
    );
    try {
      await _open(tester, file: file, actions: actions, accessible: true);
      await tester.tap(_inRoute(find.byKey(_copy)));
      await _until(tester, () => clipboard.items.isNotEmpty);
      await _motion(tester);
      final copied = await _ClipboardData.read(clipboard.items.single);
      final uri = (await copied.decode(Formats.fileUri))!;
      expect(uri.isScheme('file'), isTrue);
      final copiedFile = File.fromUri(uri);
      expect(copiedFile.path, isNot(file.path));
      expect(copiedFile.uri.pathSegments.last, _name);
      expect(await tester.runAsync(copiedFile.readAsBytes), archiveBytes);
      expect(clipboard.items.single.suggestedName, _name);
      await tester.tap(_inRoute(find.byKey(_share)));
      await _until(tester, () => shared.isNotEmpty);
      await _motion(tester);
      expect(shared.single.path, isNot(file.path));
      expect(shared.single.path, isNot(copiedFile.path));
      expect(names.single, [_name]);
      expect(await tester.runAsync(shared.single.readAsBytes), archiveBytes);
      expect(await tester.runAsync(file.readAsBytes), archiveBytes);
      expect(_inRoute(find.byKey(_copied)), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      client.close();
    }
  });

  testWidgets(
      'archive route: search draft, focus and failures survive chrome changes in a tight window',
      (tester) async {
    final actions = _Actions();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: const Offset(900, 900));
      await _open(
        tester,
        file: file,
        actions: actions,
        size: const Size(320, 380),
        scale: 2,
        editable: true,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _motion(tester);
      final field = _inRoute(find.byType(EditableText));
      final controller = tester.widget<EditableText>(field).controller;
      await tester.enterText(field, 'kept search');
      await tester.pump(const Duration(milliseconds: 250));
      await _motion(tester);
      final explorer = _inRoute(find.byType(ArchiveExplorer));
      final state = tester.state(explorer);
      await mouse.moveTo(const Offset(20, 210));
      await _motion(tester);
      await mouse.moveTo(const Offset(900, 900));
      await _motion(tester);
      expect(controller.text, 'kept search');
      expect(tester.state(explorer), same(state));
      await _tabTo(tester, _button(tester, _share).focusNode!);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      actions.calls.single.fail();
      await _motion(tester);
      expect(
        _button(tester, _share).tooltip,
        LocaleKeys.mediaActions_shareFailed.tr(),
      );
      expect(_inRoute(find.byKey(_copied)), findsNothing);
      expect(controller.text, 'kept search');
      expect(tester.widget<EditableText>(field).controller, same(controller));
      expect(tester.state(explorer), same(state));
      await tester.tap(_inRoute(find.byKey(_share)));
      await tester.pump();
      expect(actions.calls, hasLength(2));
      actions.calls.last.succeed();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _unmount(tester, actions);
    }
  });
}

Finder _inRoute(Finder matching) => find.descendant(
      of: find.byKey(_routeKey),
      matching: matching,
    );

IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(_inRoute(find.byKey(key)));

AnimatedOpacity _reveal(WidgetTester tester) => tester.widget<AnimatedOpacity>(
      _inRoute(find.byKey(const ValueKey('media-action-reveal'))),
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

Future<void> _mount(
  WidgetTester tester, {
  required Widget child,
  String mode = 'light',
  double scale = 1,
  Size size = const Size(760, 540),
  bool reduced = false,
  bool accessible = false,
  TargetPlatform platform = TargetPlatform.windows,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = _theme(mode).copyWith(platform: platform);
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
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: reduced,
                accessibleNavigation: accessible,
              ),
              child: child!,
            ),
          ),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _open(
  WidgetTester tester, {
  required File file,
  required MediaActionService actions,
  String mode = 'light',
  double scale = 1,
  Size size = const Size(760, 540),
  bool editable = false,
  bool reduced = false,
  bool accessible = false,
  TargetPlatform platform = TargetPlatform.windows,
}) async {
  await _mount(
    tester,
    mode: mode,
    scale: scale,
    size: size,
    reduced: reduced,
    accessible: accessible,
    platform: platform,
    child: Builder(
      builder: (context) => TextButton(
        onPressed: () => unawaited(
          showArchiveFullscreen(
            context,
            file: file,
            name: _name,
            editable: editable,
            mediaActions: actions,
          ),
        ),
        child: const Text('Open archive'),
      ),
    ),
  );
  await tester.tap(find.text('Open archive'));
  await _ready(tester);
}

Future<void> _ready(WidgetTester tester) async {
  await _until(
    tester,
    () => _inRoute(find.text('This archive is empty')).evaluate().isNotEmpty,
  );
  await tester.pumpAndSettle();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    ready(),
    isTrue,
    reason: 'The real archive/action boundary must finish',
  );
}

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 141));
}

Future<void> _tabTo(WidgetTester tester, FocusNode node) async {
  for (var attempt = 0; attempt < 30 && !node.hasFocus; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _motion(tester);
  }
  expect(
    node.hasFocus,
    isTrue,
    reason: 'Native action must be reachable by Tab',
  );
}

Future<void> _unmount(WidgetTester tester, [_Actions? actions]) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (final call in actions?.calls ?? const <_Call>[]) {
    if (!call.done.isCompleted) call.succeed();
  }
  for (var turn = 0; turn < 8; turn++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

class _Actions extends Fake implements MediaActionService {
  final calls = <_Call>[];
  @override
  Future<void> copy(MediaActionSource source) => _start('copy', source, null);
  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _start('share', source, sharePositionOrigin);

  Future<void> _start(String kind, MediaActionSource source, Rect? origin) {
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
  void succeed() => done.complete();
  void fail() =>
      done.completeError(StateError('Synthetic archive action failure'));
}

class _Clipboard implements ClipboardWriter {
  final items = <DataWriterItem>[];
  @override
  Future<void> write(Iterable<DataWriterItem> values) async =>
      items.addAll(values);
}

/// Decodes the real eager representations without registering native handles.
class _ClipboardData implements PlatformDataProvider {
  _ClipboardData(this.values);
  final Map<String, Object?> values;

  static Future<_ClipboardData> read(DataWriterItem item) async {
    final values = <String, Object?>{};
    for (final pending in item.data) {
      final encoded = await pending;
      for (final representation in encoded.representations) {
        final serialized = representation.serialize() as Map;
        expectSync(serialized['type'], 'simple');
        values[representation.format] = serialized['data'];
      }
    }
    return _ClipboardData(values);
  }

  Future<T?> decode<T extends Object>(ValueFormat<T> format) =>
      format.codec.decode(
        this,
        format.codec.decodingFormats.firstWhere(values.containsKey),
      );
  @override
  List<String> getAllFormats() => values.keys.toList();
  @override
  Future<Object?> getData(String format) async => values[format];
}
