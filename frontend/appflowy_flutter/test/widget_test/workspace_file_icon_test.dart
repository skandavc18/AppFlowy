import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// Only the font IO boundary is substituted; the source editor remains real.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_io;
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_descriptor.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_family_with_variant.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_variant.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart';

const _identity = ValueKey('workspace-file-identity-icon');
const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late _ReadTrackedFile text;
  late File binary;
  late bool fontFetching;
  late bool recentsEnabled;
  final originalText =
      List.generate(160, (line) => 'Fixture line $line: retained text.')
          .join('\n');

  setUpAll(() async {
    recentsEnabled = RecentIcons.enable;
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    await font_io.loadFontIfNecessary(
      GoogleFontsDescriptor(
        familyWithVariant: const _BundledMono(),
        file: GoogleFontsFile('unused-local-icon-fixture', 0),
      ),
    );
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  setUp(() async {
    await resetVividIconTestPacks();
    temporary = await Directory.systemTemp.createTemp('workspace-file-icon-');
    text = _ReadTrackedFile(
      await File('${temporary.path}/notes.txt').writeAsString(originalText),);
    binary = await File('${temporary.path}/attachment.bin')
        .writeAsString('fixture binary contents');
  });

  tearDown(() async => temporary.delete(recursive: true));
  tearDownAll(() {
    RecentIcons.enable = recentsEnabled;
    GoogleFonts.config.allowRuntimeFetching = fontFetching;
    font_io.clearCache();
  });

  for (final appearance in vividIconTestAppearances) {
    _test(
        '$appearance: full picker, Vivid callback and live updates retain the text editor',
        (tester) async {
      final backend = _IdentityBackend(_view('file-a', 'notes.txt', text.path));
      final io = _Files(text);
      final actions = _Actions();
      try {
        await _mount(
          tester,
          WorkspaceFileView(
            view: backend.stored,
            resolveStorageUrl: io.resolve,
            materializeFile: io.load,
            iconListenerFactory: backend.listen,
            mediaActions: actions,
          ),
          appearance: appearance,
        );
        await _waitFor(
            tester, () => find.byType(TextField).evaluate().isNotEmpty,);
        final renderer = tester.widget<FilePreview>(find.byType(FilePreview));
        final rendererState = tester.state(find.byType(FilePreview));
        final input = tester.widget<TextField>(find.byType(TextField));
        final inputState = tester.state(find.byType(EditableText));
        final draft = 'Unsaved fixture buffer\n$originalText';
        // Changing only the controller creates a draft without scheduling a
        // file write. Any write caused by icon chrome fails this test boundary.
        input.controller!.value = TextEditingValue(
          text: draft,
          selection: const TextSelection(baseOffset: 3, extentOffset: 21),
        );
        input.scrollController!.jumpTo(80);
        await tester.pump();
        final metadata = renderer.metadata;
        final viewExtra = backend.stored.extra;
        final controls = tester.state(find.byType(MediaActionButtons));
        final target = tester
            .widget<MediaActionButtons>(find.byType(MediaActionButtons))
            .source;
        expect(_glyph(tester).icon.isEmpty, isTrue);
        expect(find.byType(ViewIconPicker), findsOneWidget);

        await tester.tap(find.byType(ViewIconPicker));
        await tester.pumpAndSettle();
        final picker = tester
            .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker));
        expect(picker.documentId, 'file-a');
        expect(picker.effectiveTabs, [
          PickerTabType.emoji,
          PickerTabType.defaultIcons,
          PickerTabType.icon,
          PickerTabType.custom,
        ]);
        await tester.tap(find.widgetWithText(Tab, 'Icons'));
        await tester.pumpAndSettle();
        expect(vividIconStyleButton('Vivid').hitTestable(), findsOneWidget);
        await tester.tap(vividIconStyleButton('Vivid'));
        await settleVividIconPictures(tester);
        expect(vividIconOption('rocket').hitTestable(), findsOneWidget);
        // The modal barrier intentionally blocks underlying actions, but the
        // originating chrome should remain painted while the picker is open.
        expect(find.byKey(_copy), findsOneWidget);
        expect(find.byKey(_share), findsOneWidget);
        final reveal = find.ancestor(
          of: find.byKey(_copy),
          matching: find.byType(MediaActionReveal),
        );
        expect(
            tester
                .widget<AnimatedOpacity>(find
                    .descendant(
                      of: reveal,
                      matching: find.byType(AnimatedOpacity),
                    )
                      .first,)
                .opacity,
                  1,);
        // ViewIconPicker's static native save is outside this scope. Exercise
        // its real callback with a serialized fake-backend result instead.
        final changed = tester
            .widget<ViewIconPicker>(find.byType(ViewIconPicker))
            .onViewChanged!;
        _closePicker(tester);
        await tester.pumpAndSettle();
        changed(backend.persist(_vivid('rocket')));
        await tester.pumpAndSettle();
        _expectIcon(_glyph(tester).icon, _vivid('rocket'));
        expect(backend.stored.icon, _vivid('rocket').toViewIcon());
        expect(backend.stored.extra, viewExtra);
        expect(backend.writes, 1);
        expect(tester.widget<FilePreview>(find.byType(FilePreview)),
          same(renderer),);
        expect(tester.state(find.byType(FilePreview)), same(rendererState));
        expect(tester.state(find.byType(EditableText)), same(inputState));
        expect(input.controller!.text, draft);
        expect(input.controller!.selection,
          const TextSelection(baseOffset: 3, extentOffset: 21),);
        expect(input.scrollController!.offset, 80);
        expect(renderer.metadata, same(metadata));
        expect(tester.state(find.byType(MediaActionButtons)), same(controls));
        expect(
            tester
                .widget<MediaActionButtons>(find.byType(MediaActionButtons))
                .source,
            target,);
        expect(io.loads, 1);
        expect(text.reads, 1);
        expect(text.writes, 0);

        backend.publish(backend.persist(_vivid('coffee')));
        await tester.pumpAndSettle();
        _expectIcon(_glyph(tester).icon, _vivid('coffee'));
        changed(backend.persist(EmojiIconData.none()));
        await tester.pumpAndSettle();
        expect(_glyph(tester).icon.isEmpty, isTrue);
        expect(
          find.descendant(
              of: find.byKey(_identity),
              matching: find.byIcon(fileIconForName('notes.txt')),),
          findsOneWidget,
        );
        expect(tester.widget<FilePreview>(find.byType(FilePreview)),
            same(renderer),);
        expect(input.controller!.text, draft);
        expect(io.loads, 1);
        expect(text.reads, 1);
        expect(text.writes, 0);
        expect(await tester.runAsync(text.file.readAsString), originalText);
        expect(actions.calls, isEmpty);
        expect(PaperTheme.isEnabled(tester.element(find.byKey(_identity))),
            appearance == 'paper',);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        expect(backend.listeners.every((listener) => listener.stopped), isTrue);
      }
    });
  }

  _test('persisted Vivid file identity is read back in a new standalone host',
      (tester) async {
    final backend =
        _IdentityBackend(_view('saved-file', 'attachment.bin', binary.path));
    final saved = backend.persist(_vivid('coffee'));
    final io = _Files(binary);
    try {
      await _mount(
          tester,
          WorkspaceFileView(
            view: ViewPB.fromBuffer(saved.writeToBuffer()),
            resolveStorageUrl: io.resolve,
            materializeFile: io.load,
            iconListenerFactory: backend.listen,
            ),);
      await _waitFor(
          tester,
          () => find
              .text('AppFlowy has no viewer for this file type yet.')
              .evaluate()
              .isNotEmpty,);
      _expectIcon(_glyph(tester).icon, _vivid('coffee'));
      await _unmount(tester);
      await _mount(
          tester,
          WorkspaceFileView(
            view: ViewPB.fromBuffer(backend.stored.writeToBuffer()),
            resolveStorageUrl: io.resolve,
            materializeFile: io.load,
            iconListenerFactory: backend.listen,
            ),);
      await _waitFor(
          tester,
          () => find
              .text('AppFlowy has no viewer for this file type yet.')
              .evaluate()
              .isNotEmpty,);
      _expectIcon(_glyph(tester).icon, _vivid('coffee'));
      expect(io.loads, 2);
      expect(backend.writes, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
    }
  });

  _test('read-only standalone identity stays live without mounting a picker',
      (tester) async {
    final backend = _IdentityBackend(_view(
        'read-only', 'attachment.bin', binary.path,
        icon: _vivid('rocket'),),);
    final io = _Files(binary);
    try {
      await _mount(
          tester,
          WorkspaceFileView(
            view: backend.stored,
            editable: false,
            resolveStorageUrl: io.resolve,
            materializeFile: io.load,
            iconListenerFactory: backend.listen,
            ),);
      await _waitFor(
          tester,
          () => find
              .text('AppFlowy has no viewer for this file type yet.')
              .evaluate()
              .isNotEmpty,);
      expect(find.byType(ViewIconPicker), findsNothing);
      await tester.tap(find.byKey(_identity));
      await tester.pumpAndSettle();
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      backend.publish(_view('read-only', 'attachment.bin', binary.path,
            icon: _vivid('coffee'),),);
      await tester.pumpAndSettle();
      _expectIcon(_glyph(tester).icon, _vivid('coffee'));
      expect(io.loads, 1);
      expect(backend.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
    }
  });

  _test('revoked editability rejects a retained picker callback',
      (tester) async {
    final backend =
        _IdentityBackend(_view('revoked', 'attachment.bin', binary.path));
    final io = _Files(binary);
    final editable = ValueNotifier(true);
    try {
      await _mount(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: editable,
            builder: (_, value, __) => WorkspaceFileView(
              view: backend.stored,
              editable: value,
              resolveStorageUrl: io.resolve,
              materializeFile: io.load,
              iconListenerFactory: backend.listen,
            ),
              ),);
      await _waitFor(
              tester, () => find.byType(ViewIconPicker).evaluate().isNotEmpty,);
      final oldCallback = tester
          .widget<ViewIconPicker>(find.byType(ViewIconPicker))
          .onViewChanged!;
      editable.value = false;
      await tester.pumpAndSettle();
      oldCallback(_view('revoked', 'attachment.bin', binary.path,
              icon: _vivid('rocket'),),);
      await tester.pumpAndSettle();
      expect(find.byType(ViewIconPicker), findsNothing);
      expect(_glyph(tester).icon.isEmpty, isTrue);
      expect(backend.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      editable.dispose();
    }
  });

  _test('rebound hosts ignore old callbacks and stopped view notifications',
      (tester) async {
    final backend = _IdentityBackend(
      _view('file-a', 'attachment.bin', binary.path, icon: _vivid('rocket')),);
    final view = ValueNotifier(backend.stored);
    final io = _Files(binary);
    try {
      await _mount(
          tester,
          ValueListenableBuilder<ViewPB>(
            valueListenable: view,
            builder: (_, value, __) => WorkspaceFileView(
              view: value,
              resolveStorageUrl: io.resolve,
              materializeFile: io.load,
              iconListenerFactory: backend.listen,
            ),
              ),);
      await _waitFor(
          tester,
          () => find
              .text('AppFlowy has no viewer for this file type yet.')
              .evaluate()
                .isNotEmpty,);
      final first = backend.listeners.single;
      final oldCallback = tester
          .widget<ViewIconPicker>(find.byType(ViewIconPicker))
          .onViewChanged!;
      view.value = _view('file-b', 'attachment.bin', binary.path,
              icon: _vivid('coffee'),);
      await tester.pumpAndSettle();
      _expectIcon(_glyph(tester).icon, _vivid('coffee'));
      expect(first.stopped, isTrue);
      first.updated!(
              _view('file-a', 'attachment.bin', binary.path, icon: _vivid('home')),);
      oldCallback(
              _view('file-a', 'attachment.bin', binary.path, icon: _vivid('home')),);
      // Even a malformed listener delivery claiming another identity is ignored.
      backend.listeners.last.updated!(_view(
          'unrelated', 'attachment.bin', binary.path,
              icon: _vivid('home'),),);
      await tester.pumpAndSettle();
      _expectIcon(_glyph(tester).icon, _vivid('coffee'));
      expect(tester.widget<ViewIconPicker>(find.byType(ViewIconPicker)).view.id,
              'file-b',);
      expect(io.loads, 2);
      expect(backend.writes, 0);
      await _unmount(tester);
      first.updated!(backend.stored);
      oldCallback(backend.stored);
      await tester.pump();
      expect(backend.listeners.every((listener) => listener.stopped), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      view.dispose();
    }
  });

  _test(
      'deleted workspace identity closes its picker without losing the file renderer',
      (tester) async {
    final backend =
        _IdentityBackend(_view('removed', 'attachment.bin', binary.path));
    final io = _Files(binary);
    try {
      await _mount(
          tester,
          WorkspaceFileView(
            view: backend.stored,
            resolveStorageUrl: io.resolve,
            materializeFile: io.load,
            iconListenerFactory: backend.listen,
        ),);
      await _waitFor(
          tester,
          () => find
              .text('AppFlowy has no viewer for this file type yet.')
              .evaluate()
          .isNotEmpty,);
      final renderer = tester
          .element(find.text('AppFlowy has no viewer for this file type yet.'));
      final changed = tester
          .widget<ViewIconPicker>(find.byType(ViewIconPicker))
          .onViewChanged!;
      await tester.tap(find.byType(ViewIconPicker));
      await tester.pumpAndSettle();
      backend.listeners.single.deleted!(FlowyResult.success(backend.stored));
      await tester.pumpAndSettle();
      expect(find.byType(ViewIconPicker), findsNothing);
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      changed(_view('removed', 'attachment.bin', binary.path,
          icon: _vivid('rocket'),),);
      await tester.pumpAndSettle();
      expect(_glyph(tester).icon.isEmpty, isTrue);
      expect(
          tester.element(
            find.text('AppFlowy has no viewer for this file type yet.'),),
          same(renderer),);
      expect(io.loads, 1);
      expect(backend.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
    }
  });
}

void _test(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(description, body,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),);

EmojiIconData _vivid(String name) =>
    IconsData(vividIconTestGroup, name, null).toEmojiIconData();
void _expectIcon(EmojiIconData actual, EmojiIconData expected) {
  expect(actual.type, expected.type);
  expect(actual.emoji, expected.emoji);
}

FileIdentityGlyph _glyph(WidgetTester tester) =>
    tester.widget<FileIdentityGlyph>(
      find.descendant(
      of: find.byKey(_identity), matching: find.byType(FileIdentityGlyph),),
    );

void _closePicker(WidgetTester tester) => tester
    .widget<AppFlowyPopover>(
      find.descendant(
          of: find.byType(ViewIconPicker),
      matching: find.byType(AppFlowyPopover),),
    )
    .controller!
    .close();

ViewPB _view(String id, String name, String path, {EmojiIconData? icon}) =>
    ViewPB(
      id: id,
      name: name,
      icon: icon?.toViewIcon(),
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: path,
      ).mergeIntoExtra('{"fixture":"must survive icon updates"}'),
    );

class _IdentityBackend {
  _IdentityBackend(this.stored);
  ViewPB stored;
  final listeners = <_Listener>[];
  int writes = 0;

  ViewPB persist(EmojiIconData icon) {
    writes++;
    final updated = ViewPB.fromBuffer(stored.writeToBuffer())
      ..icon = icon.toViewIcon();
    stored = ViewPB.fromBuffer(updated.writeToBuffer());
    return stored;
  }

  void publish(ViewPB view) {
    for (final listener in listeners
        .where((listener) => listener.viewId == view.id && !listener.stopped)) {
      listener.updated?.call(ViewPB.fromBuffer(view.writeToBuffer()));
    }
  }

  ViewListener listen(String viewId) {
    final listener = _Listener(viewId);
    listeners.add(listener);
    return listener;
  }
}

class _Listener extends ViewListener {
  _Listener(String id) : super(viewId: id);
  void Function(ViewPB)? updated;
  void Function(DeleteViewNotifyValue)? deleted;
  bool stopped = false;
  @override
  void start({
    void Function(UpdateViewNotifiedValue)? onViewUpdated,
    void Function(ChildViewUpdatePB)? onViewChildViewsUpdated,
    void Function(DeleteViewNotifyValue)? onViewDeleted,
    void Function(RestoreViewNotifiedValue)? onViewRestored,
    void Function(MoveToTrashNotifiedValue)? onViewMoveToTrash,
  }) {
    updated = onViewUpdated;
    deleted = onViewDeleted;
  }

  @override
  Future<void> stop() async => stopped = true;
}

class _Files {
  _Files(this.file);
  final File file;
  int loads = 0;
  Future<String?> resolve(ViewPB view) async => view.workspaceItem?.storageUrl;
  Future<File> load({required String source, required String name}) async {
    loads++;
    return file;
  }
}

class _ReadTrackedFile extends Fake implements File {
  _ReadTrackedFile(this.file);
  final File file;
  int reads = 0;
  int writes = 0;
  @override
  String get path => file.path;
  @override
  Uri get uri => file.uri;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<int> length() => file.length();
  @override
  FileStat statSync() => file.statSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    reads++;
    return file.readAsString(encoding: encoding);
  }

  @override
  Future<File> writeAsString(String contents,
      {FileMode mode = FileMode.write,
      Encoding encoding = utf8,
      bool flush = false,}) async {
    writes++;
    throw StateError('Icon changes must never write file bytes');
  }

  @override
  void writeAsStringSync(String contents,
      {FileMode mode = FileMode.write,
      Encoding encoding = utf8,
      bool flush = false,}) {
    writes++;
    throw StateError('Icon changes must never flush an editor draft');
  }
}

class _Actions extends Fake implements MediaActionService {
  final calls = <String>[];
  @override
  Future<void> copy(MediaActionSource source) async => calls.add('copy');
  @override
  Future<void> share(MediaActionSource source,
      {Rect? sharePositionOrigin,}) async =>
      calls.add('share');
}

class _BundledMono extends GoogleFontsFamilyWithVariant {
  const _BundledMono()
      : super(
          family: 'JetBrainsMono',
          googleFontsVariant: const GoogleFontsVariant(
              fontWeight: FontWeight.w500, fontStyle: FontStyle.normal,),
        );
  @override
  String toApiFilenamePrefix() => 'RobotoMono-Regular';
}

Future<void> _mount(WidgetTester tester, Widget child,
    {String appearance = 'light',}) async {
  final theme = vividIconTestTheme(appearance);
  final defaults = AppFlowyDefaultTheme();
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(EasyLocalization(
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
                data: PremiumTheme.appFlowyTheme(
                  base:
                      appearance == 'dark' ? defaults.dark() : defaults.light(),
                  palette: theme.extension<PremiumThemeExtension>()!,
                  brightness: theme.brightness,
                ),
                child: child!,
              ),
              home: Scaffold(
                  body: Center(
                      child: SizedBox(width: 760, height: 660, child: child),),),
            ),),
  ),);
  await tester.pump();
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: 'The temporary file renderer must load');
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  for (final state
      in tester.stateList<EditableTextState>(find.byType(EditableText))) {
    state.hideToolbar();
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() async {});
  await tester.pumpAndSettle();
}
