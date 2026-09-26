import 'dart:io';

import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/table_views/gallery_stage.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/window_title_bar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_header.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_workspace_layout.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

/// Test-only composition of production presentation widgets, not another app
/// shell. No HomeStack, plugin startup, service registration or live workspace.
/// Native captions, navigation, editing and persistence are deliberately outside
/// this fixture's scope. Both entrypoints use these exact widgets and models.
enum WorkspaceDesignSheet { library, dashboard, settings }

enum WorkspaceDesignAppearance { light, dark, paper }

enum WorkspaceDesignViewport {
  desktop(Size(1440, 1050)),
  compact(Size(560, 1280));

  const WorkspaceDesignViewport(this.size);

  final Size size;
}

@immutable
class WorkspaceDesignCase {
  const WorkspaceDesignCase(this.sheet, this.viewport, this.appearance);

  final WorkspaceDesignSheet sheet;
  final WorkspaceDesignViewport viewport;
  final WorkspaceDesignAppearance appearance;

  String get id => '${sheet.name}_${viewport.name}_${appearance.name}';
}

final workspaceDesignCases = List<WorkspaceDesignCase>.unmodifiable([
  for (final sheet in WorkspaceDesignSheet.values)
    for (final viewport in WorkspaceDesignViewport.values)
      for (final appearance in WorkspaceDesignAppearance.values)
        WorkspaceDesignCase(sheet, viewport, appearance),
]);

const workspaceDesignCaptureKey = ValueKey('workspace-design-capture');
const _pageTitleKey = ValueKey('workspace-design-page-title');
const _notesCardKey = ValueKey('workspace-design-notes-card');
const _coverCardKey = ValueKey('workspace-design-cover-card');
const _tableCardKey = ValueKey('workspace-design-table-card');
const _menuKey = ValueKey('workspace-design-menu');
const _locale = Locale('en', 'US');
const _pageCover = PageStyleCover(
  type: PageStyleCoverImageType.builtInImage,
  value: 'n3',
);
const _cardCover = PageStyleCover(
  type: PageStyleCoverImageType.builtInImage,
  value: 'n5',
);

ThemeData workspaceDesignTheme(WorkspaceDesignAppearance appearance) =>
    DesktopAppearance()
        .getThemeData(
          appearance == WorkspaceDesignAppearance.paper
              ? AppTheme.builtins.firstWhere(
                  (theme) => theme.themeName == BuiltInTheme.paper,
                )
              : AppTheme.fallback,
          appearance == WorkspaceDesignAppearance.dark
              ? Brightness.dark
              : Brightness.light,
          preferredFontFamily,
          builtInCodeFontFamily,
        )
        .copyWith(platform: TargetPlatform.windows);

/// Call after choosing the binding, from setUpAll (real asset IO, not fake time).
/// Preferences are replaced in memory BEFORE localization initializes. They are
/// never read from or flushed to the user's installed app. Each entrypoint runs
/// in its own test process; do not import this setup into normal app startup.
class WorkspaceDesignEnvironment {
  final _previousRuntimeFonts = GoogleFonts.config.allowRuntimeFetching;
  final _previousRecents = RecentIcons.enable;
  final _previousHttp = HttpOverrides.current;
  final _network = _NoFixtureNetwork();

  int get httpClientAttempts => _network.attempts;

  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    RecentIcons.enable = false;
    HttpOverrides.global = _network;
    await EasyLocalization.ensureInitialized();

    // Use the RESOLVED face, not merely the family requested from the theme.
    final families = {
      for (final appearance in WorkspaceDesignAppearance.values)
        workspaceDesignTheme(appearance).textTheme.bodyMedium!.fontFamily,
    };
    for (final family in families) {
      if (family != preferredFontFamily) {
        throw StateError('Expected bundled DM Sans; theme resolved $family.');
      }
      await _loadFont(family!, const [
        'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
        'assets/google_fonts/DM_Sans/DMSans-VariableItalic.ttf',
      ]);
    }
    // The real gallery preview explicitly uses Inter; do not alias it to Sans.
    await _loadFont(bundledFontFamily, const [
      'assets/google_fonts/Inter/Inter-Variable.ttf',
      'assets/google_fonts/Inter/Inter-VariableItalic.ttf',
    ]);
    await _loadFont(builtInCodeFontFamily, const [
      'assets/google_fonts/Roboto_Mono/RobotoMono-Regular.ttf',
    ]);
    await _loadFont('MaterialIcons', const [
      'fonts/MaterialIcons-Regular.otf',
    ]);

    // Warm only definitions actually instantiated below. Do not replace any
    // builders or start the extension host. Registry registration itself is lazy
    // and does not mount the unused service-backed widget definitions.
    for (final spec in _dashboardDocument.allWidgets) {
      if (!const {'text', 'checklist', 'counter'}.contains(spec.type) ||
          spec.source.isBound ||
          spec.bindings.isNotEmpty ||
          spec.actions.isNotEmpty ||
          DashboardWidgetRegistry.definitionFor(spec.type) == null) {
        throw StateError('Unsafe or missing fixture widget: ${spec.type}');
      }
    }
  }

  void expectOffline() {
    expect(
      httpClientAttempts,
      0,
      reason: 'A visual fixture must not attempt an HTTP request.',
    );
  }

  void dispose() {
    HttpOverrides.global = _previousHttp;
    RecentIcons.enable = _previousRecents;
    GoogleFonts.config.allowRuntimeFetching = _previousRuntimeFonts;
  }
}

Future<void> _loadFont(String family, List<String> assets) async {
  final loader = FontLoader(family);
  for (final asset in assets) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}

class _NoFixtureNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError(
      'Network access is forbidden in workspace design fixtures.',
    );
  }
}

const _preview = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: [
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.heading,
      level: 2,
      runs: [FolderGalleryTextRun(text: 'Make room for the work')],
    ),
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.paragraph,
      runs: [
        FolderGalleryTextRun(
          text:
              'A few observations, a useful reference, and one clear next step.',
        ),
      ],
    ),
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.bulletedList,
      runs: [FolderGalleryTextRun(text: 'Keep the page identity clear.')],
    ),
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.todo,
      checked: true,
      runs: [FolderGalleryTextRun(text: 'Collect the reading notes.')],
    ),
  ],
  wordCount: 96,
  readingMinutes: 1,
  tags: ['research', 'design'],
  fileTypeLabel: 'MD',
);

const _tableRow = TableRowCard(
  rowId: 'workspace-design-row',
  title: 'A quieter workspace',
  cover: TableCover(kind: TableCoverKind.colour, value: '#B8D8C4'),
  // No document ID, media, URL or location property: nothing to resolve.
  properties: [
    TableProperty(
      fieldId: 'progress',
      name: 'Progress',
      value: '64%',
      kind: TablePropertyKind.progress,
      fraction: 0.64,
    ),
    TableProperty(
      fieldId: 'status',
      name: 'Status',
      value: 'In review',
      kind: TablePropertyKind.badge,
    ),
    TableProperty(
      fieldId: 'area',
      name: 'Area',
      value: 'Workspace design',
      kind: TablePropertyKind.text,
    ),
  ],
);

// No clock/date-dependent widgets, sources, refresh timers or action bindings.
// These are the existing registered implementations, not fixture replacements.
const _dashboardDocument = DashboardDocument(
  subtitle: 'Small plans, useful notes, and a little space to think.',
  settings: DashboardSettings(showControlBar: false, reduceMotion: true),
  sections: [
    DashboardSection(
      id: 'design-focus',
      title: 'Today',
      widgets: [
        DashboardWidgetSpec(
          id: 'design-note',
          type: 'text',
          title: 'A note for today',
          placement: DashboardPlacement(columnSpan: 6),
          settings: {
            'text': 'Start with the important thing.\n\n'
                'Keep the next step small enough to begin.',
          },
        ),
        DashboardWidgetSpec(
          id: 'design-checklist',
          type: 'checklist',
          title: 'Next steps',
          placement: DashboardPlacement(column: 6, columnSpan: 6),
          settings: {
            'items': [
              {'label': 'Gather the notes', 'done': true},
              {'label': 'Review the layout', 'done': false},
              {'label': 'Choose the next step', 'done': false},
            ],
          },
        ),
        DashboardWidgetSpec(
          id: 'design-counter',
          type: 'counter',
          title: 'Ideas collected',
          placement: DashboardPlacement(row: 4, columnSpan: 12, rowSpan: 2),
          settings: {'value': 7},
        ),
      ],
    ),
  ],
);

ViewPB _fileView(String id, String name, {PageStyleCover? cover}) {
  var extra = WorkspaceItemMetadata.file(
    contentKind: WorkspaceFileContentKind.binary,
    size: 2048,
    modifiedAt: DateTime(2020, 4, 12, 12),
  ).mergeIntoExtra('');
  if (cover != null) extra = ViewCoverCodec.mergeCover(extra, cover);
  extra = ViewPreviewModeCodec.merge(
    extra,
    cover == null ? ViewPreviewMode.content : ViewPreviewMode.cover,
  );
  // A real persisted metadata round trip, but never a backend create/read.
  return ViewPB.fromBuffer(
    ViewPB(id: id, name: name, layout: ViewLayoutPB.Document, extra: extra)
        .writeToBuffer(),
  );
}

class WorkspaceDesignFixture extends StatefulWidget {
  const WorkspaceDesignFixture({super.key, required this.scenario});

  final WorkspaceDesignCase scenario;

  @override
  State<WorkspaceDesignFixture> createState() => _WorkspaceDesignFixtureState();
}

class _WorkspaceDesignFixtureState extends State<WorkspaceDesignFixture> {
  // DashboardPage borrows this controller, so it never starts a ViewListener.
  // Empty viewId is the controller's production no-persistence path.
  final _dashboard = DashboardController(
    viewId: '',
    document: _dashboardDocument,
  );
  final _dashboardView = ViewPB(name: 'Your workspace');
  final _page = _fileView('design-page', 'Design notes', cover: _pageCover);
  final _notes = _fileView('design-notes', 'Research notes.md');
  final _journal =
      _fileView('design-journal', 'Field journal.md', cover: _cardCover);
  final _completedPreview = SynchronousFuture<FolderGalleryPreview>(_preview);

  @override
  void dispose() {
    _dashboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scenario = widget.scenario;
    final theme = workspaceDesignTheme(scenario.appearance);
    final base = AppFlowyDefaultTheme();
    return DefaultAssetBundle(
      bundle: testAssetBundle,
      child: EasyLocalization(
        supportedLocales: const [_locale],
        startLocale: _locale,
        fallbackLocale: _locale,
        path: 'assets/translations',
        saveLocale: false,
        useFallbackTranslations: true,
        assetLoader: const TestBundleAssetLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            theme: theme,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: scenario.viewport.size,
                devicePixelRatio: 1,
                textScaler: TextScaler.noScaling,
                disableAnimations: true,
                accessibleNavigation: false,
              ),
              child: AppFlowyTheme(
                data: PremiumTheme.appFlowyTheme(
                  base: theme.brightness == Brightness.dark
                      ? base.dark()
                      : base.light(),
                  palette: theme.extension<PremiumThemeExtension>()!,
                  brightness: theme.brightness,
                ),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => RepaintBoundary(
                  key: workspaceDesignCaptureKey,
                  child: ColoredBox(
                    color: WorkspacePalette.of(context).background,
                    // Capture-only: pointer position must not change a golden
                    // or activate a real rename/source picker in a native run.
                    child: IgnorePointer(
                      child: ExcludeFocus(child: _buildComposition(context)),
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

  Widget _buildComposition(BuildContext context) {
    final scenario = widget.scenario;
    final title = switch (scenario.sheet) {
      WorkspaceDesignSheet.library => 'Design notes',
      WorkspaceDesignSheet.dashboard => 'Your workspace',
      WorkspaceDesignSheet.settings => 'Settings',
    };
    return Row(
      children: [
        if (scenario.viewport == WorkspaceDesignViewport.desktop)
          SizedBox(
            width: WorkspaceTokens.navigationWidth,
            child: _FixtureNavigation(sheet: scenario.sheet),
          ),
        Expanded(
          child: Column(
            children: [
              WindowTitleBar(
                // The production caption listener calls window_manager. This
                // fixture covers Flutter context chrome, not native buttons.
                showCaptionButtons: false,
                title: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const SidebarGlyph(SidebarIcon.folder, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Workspace',
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.metadata,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.chevron_right_rounded, size: 16),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WorkspaceTypography.style(
                            context,
                            WorkspaceTextRole.metadata,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: switch (scenario.sheet) {
                  WorkspaceDesignSheet.library => _buildLibrary(context),
                  WorkspaceDesignSheet.dashboard => DashboardPage(
                      view: _dashboardView,
                      controller: _dashboard,
                    ),
                  WorkspaceDesignSheet.settings => const _FixtureSettings(),
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLibrary(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          primary: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkspacePageHeader(
                cover: ViewCoverImage(
                  cover: ViewCoverCodec.decodeCover(_page.extra)!,
                  width: double.infinity,
                ),
                identity: WorkspacePageIdentity(
                  icon: SidebarGlyph(
                    SidebarIcon.document,
                    size: WorkspaceTokens.pageIconSize,
                    color: WorkspacePalette.of(context).accent,
                  ),
                  title: Text(
                    _page.name,
                    key: _pageTitleKey,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.pageTitle,
                    ),
                  ),
                  description: const Text(
                    'Notes, projects, and the next small step.',
                  ),
                  metadata: const Text('Personal workspace · 3 items'),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: WorkspaceTokens.pageMaxWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      WorkspaceTokens.pageInset(constraints.maxWidth),
                      0,
                      WorkspaceTokens.pageInset(constraints.maxWidth),
                      WorkspaceTokens.space12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'On the desk',
                          style: WorkspaceTypography.style(
                            context,
                            WorkspaceTextRole.section,
                          ),
                        ),
                        const SizedBox(height: WorkspaceTokens.space2),
                        Text(
                          'A saved file preview, a database row, and a cover.',
                          style: WorkspaceTypography.style(
                            context,
                            WorkspaceTextRole.metadata,
                          ),
                        ),
                        const SizedBox(height: WorkspaceTokens.space4),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final metrics = GalleryCardMetrics.resolve(
                              available: constraints.maxWidth,
                              size: GalleryCardSize.large,
                              spacing: 18,
                            );
                            return Wrap(
                              spacing: metrics.spacing,
                              runSpacing: metrics.spacing,
                              children: [
                                for (final child in [
                                  _fileCard(_notes, _notesCardKey),
                                  TableGalleryCard(
                                    key: _tableCardKey,
                                    card: _tableRow,
                                    palette: tableViewPaletteOf(context),
                                    face: GalleryCardFace.cover,
                                    coverHeight: metrics.height * 0.6,
                                    showPlaceholder: false,
                                    quiet: false,
                                    onOpen: _nothing,
                                    onContextMenu: (_) async {},
                                  ),
                                  _fileCard(_journal, _coverCardKey),
                                ])
                                  SizedBox(
                                    width: metrics.width,
                                    height: metrics.height,
                                    child: child,
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _fileCard(ViewPB view, Key key) => FolderGalleryCard(
        key: key,
        item: WorkspaceExplorerItem.fromView(view),
        view: view,
        preview: _completedPreview,
        userProfile: null,
        selected: false,
        editing: false,
        onTap: _nothing,
        onRename: _nothing,
        onRenameSubmitted: (_) async => false,
        onRenameCancelled: _nothing,
        onMore: (_) {},
        onContextMenu: (_) {},
      );
}

void _nothing() {}

class _FixtureNavigation extends StatelessWidget {
  const _FixtureNavigation({required this.sheet});

  final WorkspaceDesignSheet sheet;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    return ColoredBox(
      color: palette.background,
      child: Padding(
        padding: const EdgeInsets.all(WorkspaceTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
              child: Text(
                'Studio workspace',
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.cardTitle,
                ),
              ),
            ),
            const SidebarNavItem(
              icon: SidebarIcon.search,
              label: 'Search',
              shortcut: 'Ctrl K',
              onTap: _nothing,
            ),
            SidebarNavItem(
              icon: SidebarIcon.home,
              label: 'Home',
              selected: sheet == WorkspaceDesignSheet.dashboard,
              onTap: _nothing,
            ),
            const SizedBox(height: WorkspaceTokens.space6),
            const SidebarSectionLabel('Private'),
            const SizedBox(height: WorkspaceTokens.space2),
            for (final (label, icon) in const [
              ('Design notes', SidebarIcon.document),
              ('Projects', SidebarIcon.folder),
              ('Reading list', SidebarIcon.book),
              ('Tasks', SidebarIcon.board),
              ('Photo library', SidebarIcon.album),
              ('Repository', SidebarIcon.repository),
            ])
              SidebarRow(
                reserveLeadingSpace: true,
                selected: sheet == WorkspaceDesignSheet.library &&
                    icon == SidebarIcon.document,
                icon: SidebarGlyph(icon),
                label: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.body,
                    color: palette.textBody,
                  ),
                ),
                onTap: _nothing,
              ),
            const Spacer(),
            const SidebarNavItem(
              icon: SidebarIcon.templates,
              label: 'Templates',
              onTap: _nothing,
            ),
            SidebarNavItem(
              icon: SidebarIcon.settings,
              label: 'Settings',
              selected: sheet == WorkspaceDesignSheet.settings,
              onTap: _nothing,
            ),
          ],
        ),
      ),
    );
  }
}

class _FixtureSettings extends StatelessWidget {
  const _FixtureSettings();

  @override
  Widget build(BuildContext context) {
    Widget navigation({bool compact = false}) => SettingsMenu(
          compact: compact,
          changeSelectedPage: (SettingsPage _) {},
          currentPage: SettingsPage.workspace,
          userProfile: UserProfilePB(),
          isBillingEnabled: false,
          currentUserRole: null,
        );
    return Padding(
      padding: const EdgeInsets.all(WorkspaceTokens.space6),
      child: WorkspaceSurface(
        kind: WorkspaceSurfaceKind.floating,
        child: SettingsWorkspaceLayout(
          navigation: navigation(),
          navigationPicker: navigation(compact: true),
          onClose: _nothing,
          child: SettingsBody(
            title: 'Workspace',
            description: 'A comfortable place for your everyday work.',
            children: [
              SettingsCategory(
                title: 'Reading',
                description: 'Keep the content steady and the controls quiet.',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Reduce motion',
                          style: WorkspaceTypography.style(
                            context,
                            WorkspaceTextRole.body,
                          ),
                        ),
                      ),
                      Switch(value: true, onChanged: (_) {}),
                    ],
                  ),
                ],
              ),
              const SettingsCategory(
                title: 'Page actions',
                description:
                    'The shared menu, shown here without opening a route.',
                children: [
                  AppMenuSurface(
                    key: _menuKey,
                    width: 288,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppMenuSectionLabel(label: 'Page'),
                        AppMenuRow(
                          label: 'Open in new tab',
                          icon: Icons.open_in_new_rounded,
                          highlighted: true,
                        ),
                        AppMenuRow(
                          label: 'Pin to sidebar',
                          icon: Icons.push_pin_rounded,
                          selected: true,
                        ),
                        AppMenuSeparatorLine(),
                        AppMenuRow(
                          label: 'Rename',
                          icon: Icons.edit_rounded,
                          shortcut: 'F2',
                        ),
                        AppMenuRow(
                          label: 'Duplicate',
                          icon: Icons.copy_rounded,
                          enabled: false,
                        ),
                        AppMenuRow(
                          label: 'Move to trash',
                          icon: Icons.delete_outline_rounded,
                          destructive: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Decode actual bundled pictures on the real IO clock. ViewCoverImage has an
/// errorBuilder, so checking takeException alone could approve a blank fallback.
Future<void> settleWorkspaceDesignFixture(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
  final frame = find.byKey(workspaceDesignCaptureKey);
  expect(frame, findsOneWidget);
  final context = tester.element(frame);
  final covers = tester.widgetList<ViewCoverImage>(find.byType(ViewCoverImage));
  await tester.runAsync(() async {
    for (final cover in covers) {
      Object? failure;
      await precacheImage(
        AssetImage(
          PageStyleCoverImageType.builtInImagePath(cover.cover.value),
          bundle: testAssetBundle,
        ),
        context,
        onError: (error, _) => failure = error,
      ).timeout(const Duration(seconds: 10));
      if (failure != null) {
        throw StateError('Bundled fixture cover did not decode: $failure');
      }
    }
  });
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// Shared checks run before either a golden comparison or a native capture.
/// These check the production widget tree; they do not claim visual approval.
void expectWorkspaceDesignFixture(
  WidgetTester tester,
  WorkspaceDesignCase scenario,
) {
  final frame = find.byKey(workspaceDesignCaptureKey);
  final context = tester.element(frame);
  expect(tester.takeException(), isNull);
  expect(find.byType(ErrorWidget), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(tester.getSize(frame), scenario.viewport.size);
  expect(
    Theme.of(context).textTheme.bodyMedium!.fontFamily,
    preferredFontFamily,
  );
  expect(
    PaperTheme.isEnabled(context),
    scenario.appearance == WorkspaceDesignAppearance.paper,
  );
  expect(find.byType(WindowTitleBar), findsOneWidget);
  expect(
    tester.getSize(find.byType(WindowTitleBar)).height,
    WorkspaceTokens.headerHeight,
  );
  expect(
    tester
        .widget<WindowTitleBar>(find.byType(WindowTitleBar))
        .showCaptionButtons,
    isFalse,
  );
  if (scenario.viewport == WorkspaceDesignViewport.desktop) {
    expect(find.byType(SidebarRow), findsWidgets);
  }

  switch (scenario.sheet) {
    case WorkspaceDesignSheet.library:
      expect(find.byType(WorkspacePageHeader), findsOneWidget);
      expect(find.byType(WorkspacePageIdentity), findsOneWidget);
      expect(find.byType(FolderGalleryCard), findsNWidgets(2));
      expect(find.byType(FolderGalleryRichTextPreview), findsOneWidget);
      expect(find.byType(TableGalleryCard), findsOneWidget);
      expect(find.byType(ViewCoverImage), findsNWidgets(2));
      for (final card in tester.widgetList<FolderGalleryCard>(
        find.byType(FolderGalleryCard),
      )) {
        expect(card.item.isFolder, isFalse);
        expect(
          card.item.metadata!.contentKind,
          WorkspaceFileContentKind.binary,
        );
        expect(card.preview, isA<SynchronousFuture<FolderGalleryPreview>>());
      }
      for (final element in find.byType(ViewCoverImage).evaluate()) {
        final cover = element.widget as ViewCoverImage;
        expect(cover.cover.type, PageStyleCoverImageType.builtInImage);
        final image = find.descendant(
          of: find.byWidget(cover),
          matching: find.byType(RawImage),
        );
        expect(
          image,
          findsOneWidget,
          reason: 'A cover fallback is not a reference.',
        );
        expect(tester.widget<RawImage>(image).image, isNotNull);
      }
      for (final key in [
        _pageTitleKey,
        _notesCardKey,
        _tableCardKey,
        _coverCardKey,
      ]) {
        _expectInFrame(tester, find.byKey(key));
      }
    case WorkspaceDesignSheet.dashboard:
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.byType(WorkspacePageHeader), findsOneWidget);
      expect(find.byType(WorkspacePageIdentity), findsOneWidget);
      final page = tester.widget<DashboardPage>(find.byType(DashboardPage));
      expect(page.controller, isNotNull);
      expect(page.controller!.viewId, isEmpty);
      expect(page.controller!.document, _dashboardDocument);
      expect(find.byType(DashboardCard), findsNWidgets(3));
      expect(find.text('Gather the notes'), findsOneWidget);
      for (final spec in _dashboardDocument.allWidgets) {
        _expectInFrame(tester, find.widgetWithText(DashboardCard, spec.title));
      }
    case WorkspaceDesignSheet.settings:
      expect(find.byType(SettingsWorkspaceLayout), findsOneWidget);
      expect(find.byType(SettingsHeader), findsOneWidget);
      expect(find.byType(SettingsCategory), findsNWidgets(2));
      expect(find.byType(SettingsMenu), findsOneWidget);
      expect(find.byType(AppMenuSurface), findsOneWidget);
      expect(find.byType(AppMenuRow), findsNWidgets(5));
      _expectInFrame(tester, find.byKey(_menuKey));
  }
  expect(tester.takeException(), isNull);
}

void _expectInFrame(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final frame = tester.getRect(find.byKey(workspaceDesignCaptureKey));
  final rect = tester.getRect(finder);
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
  expect(rect.left, greaterThanOrEqualTo(frame.left - 0.01));
  expect(rect.top, greaterThanOrEqualTo(frame.top - 0.01));
  expect(rect.right, lessThanOrEqualTo(frame.right + 0.01));
  expect(rect.bottom, lessThanOrEqualTo(frame.bottom + 0.01));
}
