import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/plugins/base/emoji/emoji_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_emoji_mart/flutter_emoji_mart.dart';
import 'package:google_fonts/google_fonts.dart';
// Only font IO is substituted. Every tested editor/control remains real.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_io;
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_descriptor.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_family_with_variant.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_variant.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'page_icon_widget_test_support.dart';

const fileControlAppearances = ['light', 'dark', 'paper'];

void fileControlTestSetup() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool recents;
  late bool fetching;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    kCachedEmojiData = await EmojiData.builtIn();
    _translations = Map<String, dynamic>.from(
      jsonDecode(await rootBundle.loadString('assets/translations/en-US.json'))
          as Map,
    );
    recents = RecentIcons.enable;
    RecentIcons.enable = false;
    fetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      await font_io.loadFontIfNecessary(
        GoogleFontsDescriptor(
          familyWithVariant: _BundledMono(weight),
          file: GoogleFontsFile('file-controls-local-font-fixture', 0),
        ),
      );
    }
    for (final family in fileControlAppearances
        .map((mode) => fileControlTheme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle.load(
                'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
              ),
            ))
          .load();
    }
  });
  tearDownAll(() {
    RecentIcons.enable = recents;
    GoogleFonts.config.allowRuntimeFetching = fetching;
    font_io.clearCache();
  });
}

ThemeData fileControlTheme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins.firstWhere(
              (theme) => theme.themeName == BuiltInTheme.paper,
            )
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

late Map<String, dynamic> _translations;

class _Translations extends AssetLoader {
  const _Translations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

Future<void> mountFileControls(
  WidgetTester tester,
  Widget child, {
  String mode = 'light',
  double width = 780,
  double height = 720,
  double textScale = 1,
  bool reduced = false,
  bool accessible = false,
  TargetPlatform platform = TargetPlatform.windows,
}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = fileControlTheme(mode).copyWith(platform: platform);
  final defaults = AppFlowyDefaultTheme();
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
      saveLocale: false,
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          builder: (context, body) => AppFlowyTheme(
            data: PremiumTheme.appFlowyTheme(
              base: mode == 'dark' ? defaults.dark() : defaults.light(),
              palette: theme.extension<PremiumThemeExtension>()!,
              brightness: theme.brightness,
            ),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: reduced,
                accessibleNavigation: accessible,
              ),
              child: body!,
            ),
          ),
          home: Scaffold(
            body: Center(
              child: PassivePageIconTestScope(
                child: SizedBox(width: width, height: height, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await settleFileControls(tester);
}

Future<void> settleFileControls(WidgetTester tester) async {
  // Publication and menu selection are deliberately post-frame operations.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 240));
  await tester.pump();
}

Future<void> clickFileControl(WidgetTester tester, Finder finder) async {
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tapAt(
    tester.getCenter(finder.hitTestable()),
    kind: PointerDeviceKind.mouse,
  );
  await settleFileControls(tester);
}

void expectFileControlPainted(WidgetTester tester, Finder control) {
  expect(control, findsOneWidget);
  final fades =
      find.ancestor(of: control, matching: find.byType(AnimatedOpacity));
  expect(fades, findsWidgets);
  for (final fade in tester.widgetList<AnimatedOpacity>(fades)) {
    expect(fade.opacity, 1, reason: 'Every enclosing reveal must agree');
  }
}

Future<void> unmountFileControls(WidgetTester tester) async {
  for (final state
      in tester.stateList<EditableTextState>(find.byType(EditableText))) {
    state.hideToolbar();
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  await tester.runAsync(() async {});
}

ViewPB fileControlView(String id, String name, String path) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: path,
      ).mergeIntoExtra('{"unrelated":"preserve me"}'),
    );

class FileControlBackend extends WorkspaceItemService {
  FileControlBackend(this.stored, this.file) {
    covers = FileControlCoverBackend(this);
  }

  ViewPB stored;
  final File file;
  late final FileControlCoverBackend covers;
  final listeners = <FileControlListener>[];
  final extraWrites = <String>[];
  final iconWrites = <EmojiIconData>[];
  final renames = <String>[];
  final media = FileControlMediaActions();
  int loads = 0;
  Future<FlowyResult<ViewPB, FlowyError>>? readGate;
  Future<void>? writeGate;

  WorkspaceFileView viewer({ViewPB? view, bool editable = true}) =>
      WorkspaceFileView(
        view: view ?? stored,
        editable: editable,
        repository: this,
        resolveStorageUrl: resolve,
        materializeFile: materialize,
        iconListenerFactory: listen,
        coverBackend: covers,
        updateIcon: writeIcon,
        writeExtra: writeExtra,
        mediaActions: media,
      );

  Future<String?> resolve(ViewPB view) async => view.workspaceItem?.storageUrl;

  Future<File> materialize({
    required String source,
    required String name,
  }) async {
    loads++;
    return file;
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String viewId) async {
    final gate = readGate;
    if (gate != null) return gate;
    return FlowyResult.success(ViewPB.fromBuffer(stored.writeToBuffer()));
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    renames.add(name);
    stored = ViewPB.fromBuffer(stored.writeToBuffer())..name = name;
    return FlowyResult.success(ViewPB());
  }

  Future<FlowyResult<void, FlowyError>> writeExtra({
    required String viewId,
    required String extra,
  }) async {
    extraWrites.add(extra);
    await writeGate;
    stored = ViewPB.fromBuffer(stored.writeToBuffer())..extra = extra;
    return FlowyResult.success(null);
  }

  Future<FlowyResult<void, FlowyError>> writeIcon({
    required ViewPB view,
    required EmojiIconData viewIcon,
  }) async {
    iconWrites.add(viewIcon);
    stored = ViewPB.fromBuffer(stored.writeToBuffer())
      ..icon = viewIcon.toViewIcon();
    return FlowyResult.success(null);
  }

  ViewListener listen(String id) {
    final listener = FileControlListener(id);
    listeners.add(listener);
    return listener;
  }

  void publish(ViewPB view) {
    stored = view;
    for (final listener
        in listeners.where((item) => !item.stopped && item.viewId == view.id)) {
      listener.updated?.call(ViewPB.fromBuffer(view.writeToBuffer()));
    }
  }
}

class FileControlCoverBackend extends ViewCoverActionsBackend {
  FileControlCoverBackend(this.owner);
  final FileControlBackend owner;
  final saves = <(ViewPB, PageStyleCover)>[];
  final deleted = <PageStyleCover>[];
  Future<void>? saveGate;
  bool failSave = false;

  @override
  Future<FlowyResult<UserProfilePB, FlowyError>> currentUser() async =>
      FlowyResult.success(UserProfilePB());

  @override
  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required PageStyleCover cover,
  }) async {
    saves.add((ViewPB.fromBuffer(view.writeToBuffer()), cover));
    await saveGate;
    if (failSave) {
      return FlowyResult.failure(FlowyError(msg: 'Fixture refusal'));
    }
    owner.stored = ViewPB.fromBuffer(owner.stored.writeToBuffer())
      ..extra = ViewCoverCodec.mergeCover(view.extra, cover);
    return FlowyResult.success(null);
  }

  @override
  Future<void> delete(PageStyleCover cover) async => deleted.add(cover);
}

class FileControlListener extends ViewListener {
  FileControlListener(String id) : super(viewId: id);
  void Function(UpdateViewNotifiedValue)? updated;
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

class FileControlMediaActions extends MediaActionService {
  final copies = <MediaActionSource>[];
  final shares = <MediaActionSource>[];
  Future<void>? pending;

  @override
  Future<void> copy(MediaActionSource source) async {
    copies.add(source);
    await pending;
  }

  @override
  Future<void> share(
    MediaActionSource source, {
    Rect? sharePositionOrigin,
  }) async {
    shares.add(source);
    await pending;
  }
}

/// No disk IO: a reload or accidental draft flush is observable immediately.
class MemoryCodeFile extends Fake implements File {
  MemoryCodeFile(this.contents, {this.path = '/fixture/source.py'});
  String contents;
  int reads = 0;
  int writes = 0;

  @override
  final String path;
  @override
  Uri get uri => Uri.file(path);
  @override
  Directory get parent => Directory('/fixture');
  @override
  Future<bool> exists() async => true;
  @override
  Future<int> length() async => contents.length;
  @override
  FileStat statSync() => throw const FileSystemException('In-memory fixture');
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    reads++;
    return contents;
  }

  @override
  Future<File> writeAsString(
    String value, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writes++;
    contents = value;
    return this;
  }

  @override
  void writeAsStringSync(
    String value, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    writes++;
    contents = value;
  }
}

class _BundledMono extends GoogleFontsFamilyWithVariant {
  _BundledMono(FontWeight weight)
      : super(
          family: 'JetBrainsMono',
          googleFontsVariant: GoogleFontsVariant(
            fontWeight: weight,
            fontStyle: FontStyle.normal,
          ),
        );
  @override
  String toApiFilenamePrefix() => 'RobotoMono-Regular';
}
