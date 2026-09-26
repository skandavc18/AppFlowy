import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/plugins/collection/views/database/database_schema_panel.dart';
import 'package:appflowy/plugins/collection/views/database/database_workbench_view.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart' as db;
import 'package:appflowy/plugins/database/calendar/presentation/views/month_agenda_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_add_button.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_header.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/database/database_collection_controller.dart';
import 'package:appflowy/workspace/application/collections/database/database_schema.dart';
import 'package:appflowy/workspace/application/collections/database/database_summary_cache.dart';
import 'package:appflowy/workspace/application/maps/map_metadata.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:appflowy/workspace/presentation/settings/pages/default_icon_style_setting.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAnimatedOpacity;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// TEST-ONLY substitution: register bundled Roboto Mono for the renderer's
// JetBrains Mono aliases. FontLoader alone does not suppress GoogleFonts IO.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_io;
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_descriptor.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_family_with_variant.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_variant.dart';
import 'package:path/path.dart' as p;
// Test-only platform boundary; no application-support/user directory is read.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

/// Component review, NOT a replica of HomeStack or evidence of live-app parity.
/// Three sheets use identical production widgets/data, with both icon styles.
/// Only labels, constraint boxes and backend-facing data boundaries are fixtures.
enum WorkspaceConsistencyAppearance { light, dark, paper }

const workspaceConsistencyCaptureKey = ValueKey('consistency-capture');
// 48px outer padding + two 1120px columns + one 24px gap. The five
// specimen rows leave room for labels and the font-scope notice at 1x text.
const workspaceConsistencySheetSize = Size(2312, 2580);
const _columnWidth = 1120.0;
const _specimenBodyKey = ValueKey('review-specimen-body');
const _fixtureIoTimeout = Duration(seconds: 10);
const _monoAsset = 'assets/google_fonts/Roboto_Mono/RobotoMono-Regular.ttf';
const _codeFontNotice =
    'Code uses bundled Roboto Mono instead of JetBrains Mono: '
    'geometry/color review, not JetBrains Mono typography verification.';
const _locale = Locale('en', 'US');
final _fixedNow = DateTime(2026, 8, 14, 12);
const _code = '# Component review: displayed, never executed.\n'
    'def summarize(values):\n'
    '    total = sum(values)\n'
    '    return {"count": len(values), "total": total}\n'
    '\n'
    'sample = [12, 18, 24]\n'
    'result = summarize(sample)\n';

String workspaceConsistencyCaseId(WorkspaceConsistencyAppearance appearance) =>
    'components_${appearance.name}';

ThemeData workspaceConsistencyTheme(
  WorkspaceConsistencyAppearance appearance,
) =>
    DesktopAppearance()
        .getThemeData(
          appearance == WorkspaceConsistencyAppearance.paper
              ? AppTheme.builtins.firstWhere(
                  (theme) => theme.themeName == BuiltInTheme.paper,
                )
              : AppTheme.fallback,
          appearance == WorkspaceConsistencyAppearance.dark
              ? Brightness.dark
              : Brightness.light,
          preferredFontFamily,
          builtInCodeFontFamily,
        )
        .copyWith(platform: TargetPlatform.windows);

/// Initialize in setUpAll, after selecting the widget/native test binding.
/// JetBrains Mono is NOT bundled and the real file editor has no style seam.
/// Its GoogleFonts cache aliases deliberately use the bundled Roboto Mono.
/// The visible notice and manifest disclose that substitution, including weights.
/// No external font path, download, app startup or native backend is used.
class WorkspaceConsistencyEnvironment {
  final _previousFetching = GoogleFonts.config.allowRuntimeFetching;
  final _previousRecents = RecentIcons.enable;
  final _previousPaths = PathProviderPlatform.instance;
  final _previousHttp = HttpOverrides.current;
  final _network = _NoNetwork();
  final _translations = _FixtureTranslations();
  final fonts = <Map<String, Object>>[];
  final loadedFamilies = <String>{};
  final resolvedThemeFamilies = <String, String>{};
  final codeFontAliases = <String>{};
  Directory? _fontCache;
  CollectionTypeDefinition? _databaseDefinition;

  int get httpClientAttempts => _network.attempts;

  Map<String, Object> get codeFontSubstitution => {
        'requestedFamily': 'JetBrains Mono',
        'renderedFamily': 'Roboto Mono',
        'source': _monoAsset,
        'registeredAliases': codeFontAliases.toList(),
        'requestedWeights': [400, 500, 600],
        'weightScope': 'Regular (400) bytes used for all three aliases; '
            'not native 500/600 font faces.',
        'isSubstitution': true,
        'jetBrainsMonoVerified': false,
        'scope': _codeFontNotice,
      };

  Future<T> offline<T>(Future<T> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, _network);

  Future<void> initialize() async {
    if (!Platform.isWindows) {
      throw StateError(
        'Pin these component goldens to Windows and its Segoe UI.',
      );
    }
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    RecentIcons.enable = false;
    // The global guard also covers native engine frame callbacks. The scoped
    // guard below supersedes the widget binding's zone-local HTTP stub.
    HttpOverrides.global = _network;
    await offline(() async {
      await EasyLocalization.ensureInitialized();
      await _translations.prepare();
      for (final appearance in WorkspaceConsistencyAppearance.values) {
        final family = workspaceConsistencyTheme(appearance)
            .textTheme
            .bodyMedium!
            .fontFamily;
        // A theme can normalize "DM Sans" to "DMSans" (or a GoogleFonts
        // variant alias). Load the resolved name, not just the requested name.
        if (family == null ||
            family.split('_').first.replaceAll(' ', '') != 'DMSans') {
          throw StateError(
            'No bundled DM Sans mapping for theme face $family.',
          );
        }
        resolvedThemeFamilies[appearance.name] = family;
      }
      for (final family in {
        preferredFontFamily,
        ...resolvedThemeFamilies.values,
      }) {
        await _assetFont(
          family,
          const [
            'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
            'assets/google_fonts/DM_Sans/DMSans-VariableItalic.ttf',
          ],
          actualFamily: preferredFontFamily,
        );
      }
      await _assetFont(bundledFontFamily, const [
        'assets/google_fonts/Inter/Inter-Variable.ttf',
        'assets/google_fonts/Inter/Inter-VariableItalic.ttf',
      ]);
      await _assetFont(
        builtInCodeFontFamily,
        const [_monoAsset],
        actualFamily: 'Roboto Mono',
      );
      await _assetFont(
        'MaterialIcons',
        const ['fonts/MaterialIcons-Regular.otf'],
      );

      final sidebar =
          SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows);
      expect(sidebar, 'Segoe UI');
      final systemFonts =
          p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows', 'Fonts');
      final loader = FontLoader(sidebar);
      for (final name in [
        'segoeui.ttf',
        'seguisb.ttf',
        'segoeuib.ttf',
        'segoeuii.ttf',
      ]) {
        final bytes = await File(p.join(systemFonts, name)).readAsBytes();
        _recordFont(sidebar, name, bytes);
        loader.addFont(SynchronousFuture(ByteData.sublistView(bytes)));
      }
      await loader.load();
      loadedFamilies.add(sidebar);

      final monoData = await rootBundle.load(_monoAsset);
      final mono = monoData.buffer.asUint8List(
        monoData.offsetInBytes,
        monoData.lengthInBytes,
      );
      // Seed the package's real loaded-variant cache, not a fake renderer.
      // Temporary copies never enter the app's assets or the user's font cache.
      _fontCache = await Directory.systemTemp.createTemp('consistency-fonts-');
      PathProviderPlatform.instance = _FixturePaths(_fontCache!.path);
      font_io.clearCache();
      for (final weight in [
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w600,
      ]) {
        final variant = GoogleFontsFamilyWithVariant(
          family: 'JetBrainsMono',
          googleFontsVariant: GoogleFontsVariant(
            fontWeight: weight,
            fontStyle: FontStyle.normal,
          ),
        );
        final hash = sha256.convert(mono).toString();
        await File(p.join(_fontCache!.path, '${variant}_$hash.ttf'))
            .writeAsBytes(mono);
        await font_io.loadFontIfNecessary(
          GoogleFontsDescriptor(
            familyWithVariant: variant,
            file: GoogleFontsFile(hash, mono.length),
          ),
        );
        loadedFamilies.add(variant.toString());
        codeFontAliases.add(variant.toString());
        _recordFont(
          variant.toString(),
          _monoAsset,
          mono,
          actualFamily: 'Roboto Mono',
        );
      }

      // Override ONE data-loading builder, never the header or catalogue.
      // Both columns still mount CollectionPage and its real workbench/schema.
      final definition = CollectionRegistry.typeFor(CollectionKind.database);
      _databaseDefinition = definition;
      CollectionRegistry.register(
        definition.withViews([
          for (final view in definition.views)
            if (view.id == definition.defaultView.id)
              CollectionViewDefinition(
                id: view.id,
                labelKey: view.labelKey,
                icon: view.icon,
                isAvailable: view.isAvailable,
                builder: (context, collection) => DatabaseWorkbenchBody(
                  collection: collection,
                  controller: _ReviewDataScope.of(context).database,
                  theme: databaseThemeOf(context),
                  // The schema is real. A regression opening a native table must
                  // fail before reaching FFI, not render a made-up table instead.
                  tableBuilder: (_, __) =>
                      throw StateError('Native grid opened in schema review'),
                ),
              )
            else
              view,
        ]),
      );
    });
  }

  Future<void> _assetFont(
    String family,
    List<String> assets, {
    String? actualFamily,
  }) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      _recordFont(
        family,
        asset,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        actualFamily: actualFamily,
      );
      loader.addFont(SynchronousFuture(data));
    }
    await loader.load();
    loadedFamilies.add(family);
  }

  void _recordFont(
    String family,
    String source,
    List<int> bytes, {
    String? actualFamily,
  }) {
    expect(
      bytes.length,
      greaterThan(1000),
      reason: 'A font must contain real bytes.',
    );
    fonts.add({
      'registeredFamily': family,
      'actualFamily': actualFamily ?? family,
      'source': source,
      'sha256': sha256.convert(bytes).toString(),
    });
  }

  void expectOffline() => expect(
        httpClientAttempts,
        0,
        reason:
            'Even an attempted HTTP request invalidates this component review.',
      );

  Future<void> dispose() async {
    final definition = _databaseDefinition;
    if (definition != null) CollectionRegistry.register(definition);
    _databaseDefinition = null;
    PathProviderPlatform.instance = _previousPaths;
    HttpOverrides.global = _previousHttp;
    GoogleFonts.config.allowRuntimeFetching = _previousFetching;
    RecentIcons.enable = _previousRecents;
    font_io.clearCache();
    final cache = _fontCache;
    _fontCache = null;
    if (cache != null) await cache.delete(recursive: true);
  }
}

class _FixturePaths extends PathProviderPlatform {
  _FixturePaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Network access is forbidden in component review.');
  }
}

/// Keep localization IO outside FakeAsync too. Complete in a microtask: the
/// localization loader aggregates futures and must not receive SynchronousFuture.
class _FixtureTranslations extends AssetLoader {
  final _values = <String, Map<String, dynamic>>{};

  Future<void> prepare() async {
    final translations = await const TestBundleAssetLoader()
        .load('assets/translations', _locale)
        .timeout(_fixtureIoTimeout);
    _values[_locale.toString()] = translations;
    // There is no en.json asset; EasyLocalization's base-language fallback
    // must use the same real en-US content, not request a nonexistent file.
    _values[_locale.languageCode] = translations;
  }

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) {
    final translations = _values[locale.toString()];
    if (translations == null) {
      throw StateError('Fixture translations were not prepared for $locale.');
    }
    return Future.value(translations);
  }
}

/// Real asset/temp-file IO belongs in setUp, not the widget test's fake clock.
/// Close all controllers in the test body AFTER unmounting, including on failure.
class WorkspaceConsistencyData {
  WorkspaceConsistencyData._(this.directory, this._python, this._photo);
  final Directory directory;
  final _ReadOnlyFile _python;
  final _ReadOnlyFile _photo;
  ImageInfo? _decodedPhoto;
  final _columns = <_ColumnData>[];
  bool _closed = false;

  static Future<WorkspaceConsistencyData> create() async {
    final directory =
        await Directory.systemTemp.createTemp('consistency-files-');
    WorkspaceConsistencyData? partial;
    try {
      final codeFile =
          await File(p.join(directory.path, 'summary.py')).writeAsString(_code);
      final jpeg = await rootBundle.load('assets/test/images/sample.jpeg');
      final imageFile =
          await File(p.join(directory.path, 'Field study.jpg')).writeAsBytes(
        jpeg.buffer.asUint8List(jpeg.offsetInBytes, jpeg.lengthInBytes),
      );
      final data = WorkspaceConsistencyData._(
        directory,
        await _ReadOnlyFile.prepare(codeFile),
        await _ReadOnlyFile.prepare(imageFile),
      );
      partial = data;
      for (final style in DefaultIconStyle.values) {
        final column = _ColumnData(style, data);
        data._columns.add(column);
        expect(await column.store.ensureLoaded(), isTrue);
        await column.explorer.initialize();
        column.database.setViews(column.tables);
      }
      return data;
    } catch (_) {
      await partial?.close();
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _decodedPhoto?.dispose();
    _decodedPhoto = null;
    for (final column in _columns) {
      column.store.dispose();
      column.database.dispose();
      column.explorer.dispose();
      column.clipboard.dispose();
      for (final tab in column.tabs) {
        tab.dispose();
      }
      await column.viewTabs.close();
    }
  }

  Future<void> deleteFiles() async {
    await FileImage(_photo).evict();
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  void finishCapture() {
    expectReadOnly(unmounted: true);
    for (final column in _columns) {
      column.listeners.clear();
    }
  }

  void expectReadOnly({bool unmounted = false}) {
    expect(_python.writes + _photo.writes, 0);
    for (final column in _columns) {
      expect(column.storage.writes, 0);
      expect(column.storage.reads, 1);
      expect(column.store.value, column.style);
      expect(column.repository.childrenReads, 1);
      expect(column.repository.unexpectedCalls, 0);
      expect(column.clipboard.calls, 0);
      expect(column.viewTabs.events, isEmpty);
      expect(column.mediaActions.calls, 0);
      if (unmounted) {
        expect(column.listeners.every((listener) => listener.stopped), isTrue);
      }
    }
  }
}

class _ColumnData {
  _ColumnData(this.style, this.files) {
    storage = _MemoryKV(style);
    store = DefaultIconStyleStore(resolveStorage: () => storage);
    root = ViewPB(
      id: 'review-collection-${style.name}',
      name: 'Research library',
      layout: ViewLayoutPB.Document,
      extra: const CollectionMetadata(kind: CollectionKind.database)
          .mergeIntoExtra(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      ),
    );
    tables = [
      ViewPB(
        id: '${root.id}-notes',
        parentViewId: root.id,
        name: 'Research notes',
        layout: ViewLayoutPB.Grid,
      ),
      ViewPB(
        id: '${root.id}-projects',
        parentViewId: root.id,
        name: 'Projects',
        layout: ViewLayoutPB.Grid,
      ),
      ViewPB(
        id: '${root.id}-sources',
        parentViewId: root.id,
        name: 'Sources',
        layout: ViewLayoutPB.Grid,
      ),
    ];
    repository = _ReviewRepository(root.id, tables);
    explorer = WorkspaceExplorerController(
      root: root,
      repository: repository,
      clipboard: clipboard,
      listenForUpdates: false,
      canWrite: () => false,
    );
    database = DatabaseCollectionController(
      initialState: const {'show_schema': true},
      summaries: _Summaries(),
    );
    pythonView = _fileView('code', 'summary.py', files._python);
    photoView = _fileView('photo', 'Field study.jpg', files._photo);
    folder = ViewPB(
      id: '${style.name}-folder',
      name: 'Empty folder',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    page = ViewPB(
      id: '${style.name}-page',
      name: 'Empty page',
      layout: ViewLayoutPB.Document,
    );
    final readings = [
      ('Table', ViewLayoutPB.Grid, ''),
      ('Board', ViewLayoutPB.Board, ''),
      ('Calendar', ViewLayoutPB.Calendar, ''),
      (
        'Gallery',
        ViewLayoutPB.Grid,
        TableViewMark.newExtra(TableViewKind.gallery)
      ),
      (
        'Timeline',
        ViewLayoutPB.Grid,
        TableViewMark.newExtra(TableViewKind.timeline)
      ),
      ('Feed', ViewLayoutPB.Grid, TableViewMark.newExtra(TableViewKind.feed)),
      ('Form', ViewLayoutPB.Grid, TableViewMark.newExtra(TableViewKind.form)),
      (
        'Mailbox',
        ViewLayoutPB.Grid,
        TableViewMark.newExtra(TableViewKind.mailbox)
      ),
      ('Chart', ViewLayoutPB.Grid, ChartMetadata.newExtra()),
      ('Map', ViewLayoutPB.Grid, MapMetadata.newExtra()),
    ];
    final views = [
      for (final (index, reading) in readings.indexed)
        ViewPB(
          id: '${style.name}-view-$index',
          parentViewId: index == 0 ? root.id : '${style.name}-view-0',
          name: reading.$1,
          layout: reading.$2,
          extra: reading.$3,
        ),
    ];
    viewTabs = _ViewTabs(
      db.DatabaseTabBarState(
        parentView: views.first, selectedIndex: 0,
        compactModeId: 'component-review', enableCompactMode: false,
        tabBars: [for (final view in views) _TabRecord(view)],
        // No controller => no setting-bar/native renderer lookup in TabBarHeader.
        tabBarControllerByViewId: const {},
      ),
    );
    tabs = [
      for (final name in ['Research library', 'summary.py', 'Field study.jpg'])
        PageManager(plugin: _LabelPlugin(name)),
    ];
  }

  final DefaultIconStyle style;
  final WorkspaceConsistencyData files;
  late final _MemoryKV storage;
  late final DefaultIconStyleStore store;
  late final ViewPB root, pythonView, photoView, folder, page;
  late final List<ViewPB> tables;
  late final _ReviewRepository repository;
  late final WorkspaceExplorerController explorer;
  late final DatabaseCollectionController database;
  late final _ViewTabs viewTabs;
  late final List<PageManager> tabs;
  final clipboard = _EmptyClipboard();
  final listeners = <_ViewListener>[];
  final mediaActions = _NoMediaActions();

  ViewPB _fileView(String id, String name, _ReadOnlyFile file) => ViewPB(
        id: '${style.name}-$id',
        name: name,
        layout: ViewLayoutPB.Document,
        extra: WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          storageUrl: file.path,
          size: file.bytes.length,
        ).mergeIntoExtra(''),
      );

  Future<String?> resolve(ViewPB view) =>
      SynchronousFuture(view.workspaceItem?.storageUrl);
  Future<File> materialize({required String source, required String name}) {
    for (final file in [files._python, files._photo]) {
      if (file.path == source) return SynchronousFuture(file);
    }
    throw StateError('Unexpected fixture file');
  }

  ViewListener listen(String id) {
    final listener = _ViewListener(id);
    listeners.add(listener);
    return listener;
  }
}

class _MemoryKV extends Fake implements KeyValueStorage {
  _MemoryKV(this.style);
  final DefaultIconStyle style;
  int reads = 0, writes = 0;
  @override
  Future<String?> get(String key) async {
    expect(key, DefaultIconStyleStore.storageKey);
    reads++;
    return style.name;
  }

  @override
  Future<void> set(String key, String value) async {
    writes++;
    throw StateError('Visual review must not change a preference');
  }
}

class _EmptyClipboard extends ChangeNotifier implements WorkspaceItemClipboard {
  int calls = 0;
  @override
  WorkspaceItemClipboardData? get data => null;
  @override
  bool get hasData => false;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Clipboard actions must not run in component review');
  }
}

class _ReviewRepository extends Fake implements WorkspaceItemRepository {
  _ReviewRepository(this.rootId, this.children);
  final String rootId;
  final List<ViewPB> children;
  int childrenReads = 0, unexpectedCalls = 0;
  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) async {
    expect(id, rootId);
    childrenReads++;
    return FlowyResult.success(children);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError(
      'Unexpected repository operation: ${invocation.memberName}',
    );
  }
}

class _ViewListener extends ViewListener {
  _ViewListener(String id) : super(viewId: id);
  bool stopped = false;
  @override
  void start({
    void Function(UpdateViewNotifiedValue)? onViewUpdated,
    void Function(ChildViewUpdatePB)? onViewChildViewsUpdated,
    void Function(DeleteViewNotifyValue)? onViewDeleted,
    void Function(RestoreViewNotifiedValue)? onViewRestored,
    void Function(MoveToTrashNotifiedValue)? onViewMoveToTrash,
  }) {}
  @override
  Future<void> stop() async {
    stopped = true;
  }
}

/// Contents and stat come from the real temporary files prepared above. Only
/// asynchronous IO latency and writes are replaced; production decoding,
/// highlighting, code editor, runner chrome and image viewport are unchanged.
class _ReadOnlyFile extends Fake implements File {
  _ReadOnlyFile(this.file, this.bytes, this.details);
  final File file;
  final Uint8List bytes;
  final FileStat details;
  int writes = 0;
  static Future<_ReadOnlyFile> prepare(File file) async =>
      _ReadOnlyFile(file, await file.readAsBytes(), await file.stat());
  @override
  String get path => file.path;
  @override
  Uri get uri => file.uri;
  @override
  Directory get parent => file.parent;
  @override
  Future<bool> exists() => SynchronousFuture(true);
  @override
  Future<int> length() => SynchronousFuture(bytes.length);
  @override
  FileStat statSync() => details;
  @override
  Future<FileStat> stat() => SynchronousFuture(details);
  @override
  Future<Uint8List> readAsBytes() => SynchronousFuture(bytes);
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      SynchronousFuture(encoding.decode(bytes));
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writes++;
    throw StateError('Code must only be displayed');
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    writes++;
    throw StateError('No pending code save may be flushed');
  }
}

class _Summaries extends DatabaseSummaryCache {
  @override
  DatabaseTableSummary summaryFor(String viewId) => DatabaseTableSummary(
        viewId: viewId,
        databaseId: viewId,
        rowCount: 12,
        fields: [
          DatabaseFieldSummary(
            id: 'name',
            name: 'Name',
            type: FieldType.RichText,
            isPrimary: true,
          ),
          DatabaseFieldSummary(
            id: 'status',
            name: 'Status',
            type: FieldType.SingleSelect,
            isPrimary: false,
          ),
          DatabaseFieldSummary(
            id: 'due',
            name: 'Due date',
            type: FieldType.DateTime,
            isPrimary: false,
          ),
          DatabaseFieldSummary(
            id: 'estimate',
            name: 'Estimate',
            type: FieldType.Number,
            isPrimary: false,
          ),
        ],
      );
  @override
  Future<void> readAll(
    List<ViewPB> views, {
    void Function()? onProgress,
  }) async {}
}

class _ViewTabs extends Cubit<db.DatabaseTabBarState>
    implements db.DatabaseTabBarBloc {
  _ViewTabs(super.state);
  final events = <db.DatabaseTabBarEvent>[];
  @override
  void add(db.DatabaseTabBarEvent event) {
    events.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TabRecord extends Fake implements db.DatabaseTabBar {
  _TabRecord(this.view);
  @override
  final ViewPB view;
  @override
  String get viewId => view.id;
}

/// Only the plugin label slot is synthetic; FlowyTab/PageManager are real.
/// ViewTabBarItem is deliberately not mounted: it owns a backend ViewListener.
class _LabelPlugin extends Plugin {
  _LabelPlugin(this.name);
  final String name;
  @override
  String get id => '';
  @override
  PluginType get pluginType => PluginType.document;
  @override
  late final PluginWidgetBuilder widgetBuilder = _LabelBuilder(name);
}

class _LabelBuilder extends PluginWidgetBuilder {
  _LabelBuilder(this.name);
  final String name;
  @override
  List<NavigationItem> get navigationItems => const [];
  @override
  String get viewName => name;
  @override
  Widget get leftBarItem => const SizedBox.shrink();
  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis);
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      throw StateError('No plugin body in tab-face review');
}

class _ReviewDataScope extends InheritedWidget {
  const _ReviewDataScope({required this.data, required super.child});
  final _ColumnData data;
  static _ColumnData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ReviewDataScope>()!.data;
  @override
  bool updateShouldNotify(_ReviewDataScope oldWidget) => data != oldWidget.data;
}

class WorkspaceConsistencyVisualFixture extends StatelessWidget {
  const WorkspaceConsistencyVisualFixture({
    super.key,
    required this.appearance,
    required this.data,
    required this.environment,
  });
  final WorkspaceConsistencyAppearance appearance;
  final WorkspaceConsistencyData data;
  final WorkspaceConsistencyEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final theme = workspaceConsistencyTheme(appearance);
    final defaults = AppFlowyDefaultTheme();
    return DefaultAssetBundle(
      bundle: testAssetBundle,
      child: EasyLocalization(
        supportedLocales: const [_locale],
        startLocale: _locale,
        fallbackLocale: _locale,
        path: 'assets/translations',
        saveLocale: false,
        assetLoader: environment._translations,
        child: Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            theme: theme,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) => AppFlowyTheme(
              data: PremiumTheme.appFlowyTheme(
                base: theme.brightness == Brightness.dark
                    ? defaults.dark()
                    : defaults.light(),
                palette: theme.extension<PremiumThemeExtension>()!,
                brightness: theme.brightness,
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: workspaceConsistencySheetSize,
                  devicePixelRatio: 1,
                  textScaler: TextScaler.noScaling,
                  disableAnimations: true,
                  // Reveal the real toolbars without hover/focus/timer jitter.
                  accessibleNavigation: true, alwaysUse24HourFormat: true,
                ),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => RepaintBoundary(
                  key: workspaceConsistencyCaptureKey,
                  child: ColoredBox(
                    color: WorkspacePalette.of(context).background,
                    child: TooltipVisibility(
                      visible: false,
                      child: IgnorePointer(
                        child: ExcludeFocus(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'COMPONENT REVIEW · ${appearance.name.toUpperCase()}',
                                  style: WorkspaceTypography.style(
                                    context,
                                    WorkspaceTextRole.section,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Production presentation widgets with fixture data — not the live app. '
                                  'Fixed 14 Aug 2026 · controls revealed · no network, native data, editing or execution.',
                                ),
                                const Text(_codeFontNotice),
                                const SizedBox(height: 24),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final column in data._columns) ...[
                                      if (column != data._columns.first)
                                        const SizedBox(
                                          width: 24,
                                        ),
                                      DefaultIconStyleScope(
                                        styles: column.store.styles,
                                        child: _ReviewDataScope(
                                          data: column,
                                          child: SizedBox(
                                            width: _columnWidth,
                                            child: _ComponentColumn(
                                              key: ValueKey(
                                                'review-${column.style.name}',
                                              ),
                                              data: column,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
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
  }
}

class _ComponentColumn extends StatelessWidget {
  const _ComponentColumn({super.key, required this.data});
  final _ColumnData data;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.style.name.toUpperCase(),
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.cardTitle,
            ),
          ),
          const SizedBox(height: 12),
          _Specimen(
            label:
                'Settings + identity cards + tab faces (mock plugin labels only)',
            size: const Size(_columnWidth, 560),
            child: _settings(context),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Specimen(
                label: 'Month + agenda · 400 × 380 · six weeks',
                size: const Size(400, 380),
                child: _calendar(false),
              ),
              const SizedBox(width: 24),
              _Specimen(
                label: 'Month beside agenda · 680 × 340 · same events',
                size: const Size(680, 340),
                child: _calendar(true),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Specimen(
                label:
                    'Local Python · real renderer · Roboto Mono substituted · never run',
                size: const Size(548, 360),
                child: _file(data.pythonView),
              ),
              const SizedBox(width: 24),
              _Specimen(
                label: 'Local JPEG · real image viewport + scan action',
                size: const Size(548, 360),
                child: _file(data.photoView),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Specimen(
            label:
                'CollectionPage + workbench/schema · actual header, 24px gutter, no floating panel',
            size: const Size(_columnWidth, 620),
            child: CollectionPage(
              key: const ValueKey('review-collection'),
              view: data.root,
              controller: data.explorer,
              shellOwnsBreadcrumbs: true,
              onOpen: (_) {},
            ),
          ),
          const SizedBox(height: 24),
          _Specimen(
            label:
                'Database view header · 480px constraint · ten saved view models + add',
            size: const Size(_columnWidth, 160),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 480,
                  child: BlocProvider<db.DatabaseTabBarBloc>.value(
                    value: data.viewTabs,
                    child: const TabBarHeader(),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _settings(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 240,
            height: 560,
            child: SettingsMenu(
              changeSelectedPage: (SettingsPage _) {},
              currentPage: SettingsPage.workspace,
              userProfile: UserProfilePB(),
              isBillingEnabled: false,
              currentUserRole: null,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultIconStyleSetting(store: data.store),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _emptyCard(data.folder, folder: true),
                    const SizedBox(width: 16),
                    _emptyCard(data.page, folder: false),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        children: [
                          SidebarNavItem(
                            icon: SidebarIcon.home,
                            label: 'Home',
                            selected: true,
                            onTap: _nothing,
                          ),
                          SidebarNavItem(
                            icon: SidebarIcon.folder,
                            label: 'Library',
                            onTap: _nothing,
                          ),
                          SidebarNavItem(
                            icon: SidebarIcon.settings,
                            label: 'Settings',
                            onTap: _nothing,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: HomeSizes.tabBarHeight,
                  child: Row(
                    children: [
                      for (var i = 0; i < data.tabs.length; i++)
                        SizedBox(
                          width: 224,
                          child: FlowyTab(
                            pageManager: data.tabs[i],
                            isCurrent: i == 0,
                            isAllPinned: false,
                            showSeparator: i > 0,
                            onTap: _nothing,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _emptyCard(ViewPB view, {required bool folder}) => SizedBox(
        width: 248,
        height: 232,
        child: FolderGalleryCard(
          key: ValueKey('review-${folder ? 'folder' : 'page'}-card'),
          item: WorkspaceExplorerItem.fromView(view),
          view: view,
          preview: SynchronousFuture(
            folder
                ? FolderGalleryPreviewParser.withoutDocument(
                    view: view,
                    item: WorkspaceExplorerItem.fromView(view),
                  )!
                : const FolderGalleryPreview(
                    kind: FolderGalleryPreviewKind.document,
                    blocks: [],
                    wordCount: 0,
                    readingMinutes: 0,
                    tags: [],
                    fileTypeLabel: 'PAGE',
                  ),
          ),
          userProfile: null,
          selected: false,
          editing: false,
          onTap: _nothing,
          onRename: _nothing,
          onRenameSubmitted: (_) async => false,
          onRenameCancelled: _nothing,
          onMore: (_) {},
          onContextMenu: (_) {},
        ),
      );

  Widget _calendar(bool beside) => CalendarMonthAgendaView(
        key: ValueKey('review-calendar-${beside ? 'beside' : 'stacked'}'),
        month: DateTime(2026, 8),
        selectedDay: DateTime(2026, 8, 14),
        now: () => _fixedNow,
        sideBySide: beside,
        compact: true,
        showWeekNumbers: true,
        events: _events,
        onSelectDay: (_) {},
        delegate: CalendarViewDelegate(
          colorOf: (event) => event.color!,
          onOpenEvent: (_) {},
          onCreateAt: (_, {bool hasTime = false}) {},
          onToggleComplete: (_) {},
        ),
      );

  Widget _file(ViewPB view) => WorkspaceFileView(
        key: ValueKey('review-file-${view == data.pythonView ? 'py' : 'jpg'}'),
        view: view,
        editable: false,
        repository: data.repository,
        resolveStorageUrl: data.resolve,
        materializeFile: data.materialize,
        iconListenerFactory: data.listen,
        mediaActions: data.mediaActions,
      );
}

void _nothing() {}

final _events = List<CalendarEvent>.unmodifiable([
  CalendarEvent(
    id: 'review-all-day',
    calendarId: 'research',
    title: 'Collect field notes',
    start: ZonedDateTime.allDay(DateTime(2026, 8, 14)),
    color: const Color(0xFF669985),
  ),
  CalendarEvent(
    id: 'review-meeting',
    calendarId: 'research',
    title: 'Design review',
    start: ZonedDateTime.local(DateTime(2026, 8, 14, 9, 15)),
    end: ZonedDateTime.local(DateTime(2026, 8, 14, 10, 45)),
    kind: CalendarEventKind.task,
    color: const Color(0xFF7397CF),
  ),
  CalendarEvent(
    id: 'review-upcoming',
    calendarId: 'research',
    title: 'Share reading notes',
    start: ZonedDateTime.local(DateTime(2026, 8, 15, 11)),
    color: const Color(0xFFC39059),
  ),
]);

class _NoMediaActions extends Fake implements MediaActionService {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Media actions must only be displayed');
  }
}

/// A label and exact constraint, not a recreated production surface or toolbar.
class _Specimen extends StatelessWidget {
  const _Specimen({
    required this.label,
    required this.size,
    required this.child,
  });
  final String label;
  final Size size;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style:
                  WorkspaceTypography.style(context, WorkspaceTextRole.caption),
            ),
            const SizedBox(height: 8),
            SizedBox(
              key: _specimenBodyKey,
              width: size.width,
              height: size.height,
              child: child,
            ),
          ],
        ),
      );
}

/// Resolve the FIRST JPEG stream on real time, BEFORE mounting Image.file.
/// Resolving after mounting can reuse a pending FakeAsync cache completer and
/// deadlock even inside runAsync. Keep the decoded handle for identity checks.
Future<void> prepareWorkspaceConsistencyFixture(
  WidgetTester tester,
  WorkspaceConsistencyData data,
) async {
  expect(find.byType(WorkspaceConsistencyVisualFixture), findsNothing);
  expect(data._decodedPhoto, isNull);
  await tester.runAsync(() async {
    final provider = FileImage(data._photo);
    expect(
      PaintingBinding.instance.imageCache.statusForKey(provider).pending,
      isFalse,
      reason: 'The JPEG must not already be loading on the fake clock.',
    );
    final firstFrame = Completer<ImageInfo>();
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        if (firstFrame.isCompleted) {
          info.dispose();
        } else {
          firstFrame.complete(info);
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (!firstFrame.isCompleted) firstFrame.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    try {
      data._decodedPhoto = await firstFrame.future.timeout(_fixtureIoTimeout);
      expect(data._decodedPhoto!.image.width, greaterThan(1));
      expect(data._decodedPhoto!.image.height, greaterThan(1));
    } finally {
      stream.removeListener(listener);
    }
    _expectPhotoCached(data);
  });
  expect(tester.takeException(), isNull);
  _expectPhotoCached(data);
}

void _expectPhotoCached(WorkspaceConsistencyData data) {
  expect(data._decodedPhoto, isNotNull);
  final status = PaintingBinding.instance.imageCache.statusForKey(
    FileImage(data._photo),
  );
  expect(status.pending, isFalse);
  expect(status.keepAlive, isTrue);
}

Future<void> settleWorkspaceConsistencyFixture(
  WidgetTester tester,
  WorkspaceConsistencyData data,
) async {
  _expectPhotoCached(data);
  await tester.pump();
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  final pictures = find.byType(SvgPicture).evaluate().toList();
  await tester.runAsync(() async {
    for (final element in pictures) {
      final picture = element.widget as SvgPicture;
      final decoded = await vg
          .loadPicture(picture.bytesLoader, element)
          .timeout(_fixtureIoTimeout);
      decoded.picture.dispose();
    }
  });
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// These gates run BEFORE either screenshot path; a blank/error/loading face
/// must never become a reference. Pixel approval is a separate human step.
void expectWorkspaceConsistencyFixture(
  WidgetTester tester,
  WorkspaceConsistencyAppearance appearance,
  WorkspaceConsistencyData data,
  WorkspaceConsistencyEnvironment environment,
) {
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byKey(const ValueKey('default-icon-style-status')), findsNothing);
  expect(find.byType(DatabaseTabBarView), findsNothing);
  expect(
    tester.getSize(find.byKey(workspaceConsistencyCaptureKey)),
    workspaceConsistencySheetSize,
  );
  final context = tester.element(find.byKey(workspaceConsistencyCaptureKey));
  expect(
    PaperTheme.isEnabled(context),
    appearance == WorkspaceConsistencyAppearance.paper,
  );
  final resolvedFamily = environment.resolvedThemeFamilies[appearance.name]!;
  expect(
    Theme.of(context).textTheme.bodyMedium!.fontFamily,
    resolvedFamily,
  );
  for (final family in {
    resolvedFamily,
    preferredFontFamily,
    bundledFontFamily,
    'Segoe UI',
  }) {
    expect(environment.loadedFamilies, contains(family));
    final style = TextStyle(fontFamily: family, fontSize: 16);
    expect(
      _textWidth('iiii', style),
      lessThan(_textWidth('WWWW', style)),
      reason: '$family must not silently render as Ahem.',
    );
  }
  // Monospace equality alone would also accept Ahem. Verify the real bundled
  // face's sub-em advance AND matching metrics under every substituted alias.
  const monoStyle = TextStyle(fontFamily: builtInCodeFontFamily, fontSize: 16);
  final monoAdvance = _textWidth('iiii', monoStyle);
  expect(monoAdvance, greaterThan(0));
  expect(monoAdvance, lessThan(4 * monoStyle.fontSize!));
  expect(monoAdvance, closeTo(_textWidth('WWWW', monoStyle), 0.01));
  expect(environment.codeFontAliases, hasLength(3));
  for (final family in environment.codeFontAliases) {
    expect(environment.loadedFamilies, contains(family));
    expect(
      _textWidth('iiWW 0123 {}[]', monoStyle.copyWith(fontFamily: family)),
      closeTo(_textWidth('iiWW 0123 {}[]', monoStyle), 0.01),
      reason: 'The alias must render real Roboto Mono, not Ahem or JetBrains.',
    );
  }
  _expectPhotoCached(data);

  for (final column in data._columns) {
    final scope = find.byKey(ValueKey('review-${column.style.name}'));
    _inside(tester, scope, find.byKey(workspaceConsistencyCaptureKey));
    expect(tester.getSize(scope).width, _columnWidth);
    Finder within(Finder finder) =>
        find.descendant(of: scope, matching: finder);
    Finder keyed(String key) => within(find.byKey(ValueKey(key)));
    expect(
      tester
          .widget<DefaultIconStyleSetting>(
            within(find.byType(DefaultIconStyleSetting)),
          )
          .store,
      same(column.store),
    );
    for (final radio in tester.widgetList<RadioListTile<DefaultIconStyle>>(
      within(find.byType(RadioListTile<DefaultIconStyle>)),
    )) {
      expect(radio.groupValue, column.style);
      expect(radio.onChanged, isNotNull);
    }
    final settingsMenu = within(find.byType(SettingsMenu));
    expect(settingsMenu, findsOneWidget);
    expect(
      find.descendant(of: settingsMenu, matching: find.byType(Icon)),
      findsNothing,
      reason: 'Settings must use the shared outlined/vector glyph family.',
    );
    expect(column.listeners, hasLength(2));
    expect(within(find.byType(SidebarNavItem)), findsNWidgets(3));
    expect(within(find.byType(WorkspaceGlyph)), findsWidgets);
    expect(within(find.byType(FolderGalleryCard)), findsNWidgets(2));
    expect(within(find.byType(FolderGalleryRichTextPreview)), findsNothing);
    for (final (id, name) in [('folder', 'folder'), ('page', 'file-text')]) {
      final card = keyed('review-$id-card');
      final glyph = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) => widget is WorkspaceGlyph && widget.size == 64,
        ),
      );
      expect(glyph, findsOneWidget);
      expect(tester.widget<WorkspaceGlyph>(glyph).name, name);
      final svg = tester.widget<SvgPicture>(
        find.descendant(of: glyph, matching: find.byType(SvgPicture)),
      );
      final loader = svg.bytesLoader as SvgStringLoader;
      final vividName = column.style == DefaultIconStyle.vivid
          ? WorkspaceGlyphs.vividNameFor(name)
          : null;
      expect(
        loader,
        SvgStringLoader(
          (vividName == null ? defaultIconSvg(name) : vividIconSvg(vividName))!,
          theme: loader.theme,
          colorMapper: loader.colorMapper,
        ),
        reason: 'Each column must use its injected style, not the singleton.',
      );
      _inside(tester, card, scope);
    }
    final faces = within(find.byKey(const ValueKey('workspace-tab-face')));
    expect(faces, findsNWidgets(3));
    for (final face in faces.evaluate()) {
      expect(
        tester.getSize(find.byWidget(face.widget)).height,
        HomeSizes.tabHeight,
      );
    }
    final active =
        tester.widget<DecoratedBox>(faces.first).decoration as BoxDecoration;
    expect(active.boxShadow, isNull);
    expect(
      active.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(HomeSizes.tabCornerRadius),
      ),
    );

    for (final beside in [false, true]) {
      final calendar =
          keyed('review-calendar-${beside ? 'beside' : 'stacked'}');
      expect(
        tester.getSize(calendar),
        beside ? const Size(680, 340) : const Size(400, 380),
      );
      final widget = tester.widget<CalendarMonthAgendaView>(calendar);
      expect(widget.compact, isTrue, reason: 'The specimen host owns density.');
      expect(widget.now(), _fixedNow);
      expect(widget.events, same(_events));
      final layout = find.descendant(
        of: calendar,
        matching: find.byKey(const ValueKey('calendar-month-agenda-layout')),
      );
      expect(
        tester.widget<Flex>(layout).direction,
        beside ? Axis.horizontal : Axis.vertical,
      );
      final lastDay = find.descendant(
        of: calendar,
        matching: find.byKey(const ValueKey('calendar-day-2026-9-6')),
      );
      _inside(tester, lastDay, calendar);
      _inside(
        tester,
        find.descendant(
          of: calendar,
          matching: find.byKey(
            const ValueKey('calendar-agenda-event-review-meeting'),
          ),
        ),
        calendar,
      );
      expect(
        find.descendant(of: calendar, matching: find.text('09:15–10:45')),
        findsOneWidget,
      );
    }

    for (final (extension, name) in [
      ('py', 'summary.py'),
      ('jpg', 'Field study.jpg'),
    ]) {
      final file = keyed('review-file-$extension');
      Finder inFile(Finder finder) =>
          find.descendant(of: file, matching: finder);
      expect(inFile(find.byType(WorkspaceFileIdentityRow)), findsOneWidget);
      expect(
        inFile(find.text(name)),
        findsOneWidget,
        reason: 'No duplicate renderer filename.',
      );
      _inside(
        tester,
        inFile(find.byKey(const ValueKey('workspace-file-identity-icon'))),
        file,
      );
      _inside(
        tester,
        inFile(find.byKey(const ValueKey('workspace-file-name'))),
        file,
      );
      expect(
        inFile(find.byKey(const ValueKey('workspace-file-media-actions'))),
        findsNothing,
      );
      final toolbars = inFile(find.byType(PreviewToolbar));
      expect(toolbars, findsWidgets);
      for (final toolbar in tester.widgetList<PreviewToolbar>(toolbars)) {
        // Check this toolbar's own paint gate, not an unrelated child fade.
        // The fixture deliberately blocks input; visibility must still be real.
        final reveal = find.descendant(
          of: find.byWidget(toolbar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedOpacity &&
                identical(widget.child, toolbar.child),
          ),
        );
        expect(reveal, findsOneWidget);
        expect(tester.widget<AnimatedOpacity>(reveal).opacity, 1);
        final painted = tester.renderObject<RenderAnimatedOpacity>(reveal);
        expect(painted.attached, isTrue);
        expect(
          painted.opacity.value,
          1,
          reason: 'Controls must be painted in the capture.',
        );
        _inside(tester, reveal, file);
      }
      if (extension == 'py') {
        final runner = tester.widget<SandboxedCodeRunner>(
          inFile(find.byType(SandboxedCodeRunner)),
        );
        expect(runner.code, _code);
        expect(runner.language, 'python');
        final field = tester.widget<TextField>(inFile(find.byType(TextField)));
        expect(field.controller!.text, _code);
        expect(field.readOnly, isTrue);
        expect(environment.loadedFamilies, contains(field.style!.fontFamily));
        expect(
          environment.codeFontAliases,
          contains(field.style!.fontFamily),
          reason: 'This is a declared Roboto Mono substitution, not proof '
              'that the production JetBrains Mono font was loaded.',
        );
        expect(
          _textWidth(_code, field.style!),
          closeTo(
            _textWidth(
              _code,
              field.style!.copyWith(fontFamily: builtInCodeFontFamily),
            ),
            0.01,
          ),
        );
        expect(
          tester
              .widget<CodeToolbarButton>(
                inFile(find.byKey(const ValueKey('code-run'))),
              )
              .icon,
          Icons.play_arrow_rounded,
        );
        expect(inFile(find.text('Terminal')), findsNothing);
      } else {
        expect(inFile(find.byType(InteractiveViewer)), findsOneWidget);
        final raster =
            tester.widget<RawImage>(inFile(find.byType(RawImage))).image;
        expect(
          raster,
          isNotNull,
          reason: 'The actual JPEG, not its fallback, must render.',
        );
        expect(raster!.width, greaterThan(1));
        expect(raster.isCloneOf(data._decodedPhoto!.image), isTrue);
        final scan = inFile(
          find.byWidgetPredicate(
            (widget) =>
                widget is DocumentViewportButton &&
                widget.icon == Icons.document_scanner_rounded,
          ),
        );
        expect(scan, findsOneWidget);
        _inside(tester, scan, file);
        expect(
          tester.widget<DocumentViewportButton>(scan).tooltip,
          'Extract text',
        );
        expect(inFile(find.byIcon(Icons.text_fields_rounded)), findsNothing);
        expect(
          inFile(
            find.byWidgetPredicate(
              (widget) =>
                  widget is WorkspaceGlyph &&
                  const ['input', 'text'].contains(widget.name),
            ),
          ),
          findsNothing,
        );
      }
    }

    final collection = keyed('review-collection');
    Finder inCollection(Finder finder) =>
        find.descendant(of: collection, matching: finder);
    final pageRow = inCollection(find.byType(WorkspaceActionRow));
    expect(pageRow, findsOneWidget);
    final pageActions = tester.widget<WorkspaceActionRow>(pageRow);
    expect(pageActions.leading, isA<CollectionViewSwitcher>());
    expect(pageActions.children, hasLength(2));
    expect(
      find.descendant(
        of: pageRow,
        matching: find.byType(DecorationActionButton),
      ),
      findsNothing,
    );
    final iconRow =
        inCollection(find.byKey(const ValueKey('workspace-page-icon-row')));
    expect(
      find.descendant(
        of: iconRow,
        matching: find.byWidgetPredicate(
          (widget) => widget is TextButton || widget is IconButton,
        ),
      ),
      findsNWidgets(3),
      reason: 'Artwork picker, labelled icon picker and Add Cover stay local.',
    );
    expect(
      find.descendant(of: iconRow, matching: find.byType(ViewIconPicker)),
      findsNWidgets(2),
    );
    for (final key in ['view-decoration-icon', 'view-decoration-cover']) {
      expect(
        find.descendant(of: iconRow, matching: find.byKey(ValueKey(key))),
        findsOneWidget,
      );
    }
    final collectionHeader = inCollection(find.byType(WorkspacePageHeader));
    final identity = inCollection(find.byType(WorkspacePageIdentity));
    final icon =
        inCollection(find.byKey(const ValueKey('workspace-page-icon')));
    final title = inCollection(find.byKey(const ValueKey('collection-title')));
    expect(inCollection(find.byType(WorkspacePageCover)), findsNothing);
    expect(tester.getSize(icon), const Size.square(56));
    expect(
      tester.getTopLeft(identity).dy - tester.getTopLeft(collectionHeader).dy,
      closeTo(WorkspaceTokens.pageTopWithoutCover, 0.01),
    );
    expect(
      tester.getTopLeft(title).dy - tester.getBottomLeft(icon).dy,
      closeTo(WorkspaceTokens.pageIconTitleGap, 0.01),
    );
    expect(
      tester.getBottomLeft(collectionHeader).dy -
          tester.getBottomLeft(identity).dy,
      closeTo(WorkspaceTokens.pageHeaderBottom, 0.01),
    );
    _inside(tester, iconRow, collection);
    final left = tester.getTopLeft(collection).dx + 24;
    for (final finder in [
      inCollection(find.byKey(const ValueKey('collection-title'))),
      inCollection(find.byType(CollectionViewSwitcher)),
      pageRow,
      inCollection(find.byType(DatabaseTableRail)),
    ]) {
      expect(finder, findsOneWidget);
      expect(tester.getTopLeft(finder).dx, closeTo(left, 0.01));
      _inside(tester, finder, collection);
    }
    expect(inCollection(find.byType(CollectionWorkspaceSplit)), findsOneWidget);
    expect(inCollection(find.byType(DatabaseSchemaPanel)), findsOneWidget);
    final collectionTabs = inCollection(find.byType(CollectionViewSwitcher));
    final collectionTools = find.descendant(
      of: pageRow,
      matching: find.byType(PreviewToolbar),
    );
    expect(collectionTools, findsOneWidget);
    expect(
      find.descendant(
        of: collectionTools,
        matching: find.byWidgetPredicate(
          (widget) => widget is TextButton || widget is IconButton,
        ),
      ),
      findsNWidgets(2),
      reason: 'Only Search and Add share the collection navigation row.',
    );
    final navigationBounds = tester.getRect(collectionTabs);
    final toolsBounds = tester.getRect(collectionTools);
    expect(toolsBounds.left, closeTo(navigationBounds.right + 8, 0.01));
    expect(toolsBounds.center.dy, closeTo(navigationBounds.center.dy, 0.01));
    expect(inCollection(find.text('Estimate')), findsOneWidget);
    for (final surface
        in inCollection(find.byType(CollectionWorkspaceSurface)).evaluate()) {
      final decoration = tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byWidget(surface.widget),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration as BoxDecoration;
      expect(decoration.boxShadow, isNull);
      expect(decoration.border, isNull);
      expect(decoration.borderRadius, BorderRadius.zero);
      expect(decoration.color, WorkspacePalette.of(surface).background);
    }
    final header = within(find.byType(TabBarHeader));
    final tabs = within(find.byType(DatabaseTabBarItem));
    expect(tabs, findsNWidgets(10));
    final rows = <double>{};
    const tabGlyphs = [
      'table',
      'kanban',
      'calendar-blank',
      'squares-four',
      'graph',
      'article',
      'list-checks',
      'mail-unread',
      'chart-bar',
      'map-trifold',
    ];
    for (final (index, tab) in tabs.evaluate().indexed) {
      final finder = find.byWidget(tab.widget);
      expect(
        tester
            .widget<WorkspaceGlyph>(
              find.descendant(
                of: finder,
                matching: find.byType(WorkspaceGlyph),
              ),
            )
            .name,
        tabGlyphs[index],
      );
      rows.add(tester.getTopLeft(finder).dy);
      _inside(tester, finder, header);
    }
    expect(
      rows.length,
      greaterThan(1),
      reason: 'This specimen must exercise real wrapping.',
    );
    _inside(tester, within(find.byType(AddDatabaseViewButton)), header);
    expect(
      find.descendant(
        of: header,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
    for (final specimen in within(find.byType(_Specimen)).evaluate()) {
      final finder = find.byWidget(specimen.widget);
      final body = find.descendant(
        of: finder,
        matching: find.byKey(_specimenBodyKey),
      );
      expect(tester.getSize(body), (specimen.widget as _Specimen).size);
      _inside(tester, body, finder);
      _inside(tester, finder, scope);
      _inside(tester, finder, find.byKey(workspaceConsistencyCaptureKey));
    }
  }
  data.expectReadOnly();
  environment.expectOffline();
  expect(tester.takeException(), isNull);
}

double _textWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void _inside(WidgetTester tester, Finder child, Finder parent) {
  expect(child, findsOneWidget);
  expect(parent, findsOneWidget);
  final rect = tester.getRect(child);
  final frame = tester.getRect(parent);
  expect(rect.isFinite, isTrue);
  expect(frame.isFinite, isTrue);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(rect.left, greaterThanOrEqualTo(frame.left - 0.01));
  expect(rect.top, greaterThanOrEqualTo(frame.top - 0.01));
  expect(rect.right, lessThanOrEqualTo(frame.right + 0.01));
  expect(rect.bottom, lessThanOrEqualTo(frame.bottom + 0.01));
}

Future<void> unmountWorkspaceConsistencyFixture(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  expect(tester.takeException(), isNull);
}
