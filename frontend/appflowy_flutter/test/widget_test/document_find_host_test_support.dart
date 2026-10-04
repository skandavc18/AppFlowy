import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/plugins/database/widgets/row/row_banner.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail_scroll_surface.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_host.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_search_highlight.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/find_and_replace_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shared_context/shared_context.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/spell_check/spell_check_settings.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rowFindTitleKey = ValueKey('row-banner-title');

void setUpFindHostTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    getIt.pushNewScope();
    getIt.registerSingleton<ApplicationDataStorage>(_MemoryStorage());
    getIt.registerSingleton<CachedRecentService>(_UnusedRecentService());
    SpellCheckSettings.instance.seedForTest(spelling: false, grammar: false);
  });
  tearDown(() async {
    DocumentFindMenu.dismiss();
    SpellCheckSettings.instance.seedForTest();
    await getIt.popScope();
  });
}

/// The app page's shortcut initialization is left intact, but its storage
/// boundary is an in-memory file. No FFI, workspace files or user preferences.
Future<void> withFindHostStorage(Future<void> Function() body) =>
    IOOverrides.runWithIOOverrides(body, _ShortcutIO());

class _MemoryStorage extends Fake implements ApplicationDataStorage {
  static final root = p.join(p.separator, 'in-memory-row-find');
  @override
  Future<String> getPath() async => root;
}

class _ShortcutIO extends IOOverrides {
  final file = _ShortcutFile();
  @override
  File createFile(String path) =>
      p.equals(path, p.join(_MemoryStorage.root, 'shortcuts', 'shortcuts.json'))
          ? file
          : super.createFile(path);
}

class _ShortcutFile extends Fake implements File {
  @override
  void createSync({bool recursive = false, bool exclusive = false}) {}
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async => '';
}

class _UnusedRecentService extends Fake implements CachedRecentService {}

/// Only native metadata/access I/O is replaced. Tests use the production row
/// scope, AppFlowyEditorPage, RowBannerTitleField, menu, session and transactions.
class FindHostRepository extends Fake implements PageAccessLevelRepository {
  FindHostRepository() {
    views['row-doc'] = ViewPB(id: 'row-doc', name: 'Orphan default name');
    views['table'] = ViewPB(
      id: 'table',
      name: 'Table name',
      layout: ViewLayoutPB.Grid,
    );
  }

  final views = <String, ViewPB>{};
  final viewReads = <String>[];
  final accessReads = <String>[];
  final failedViews = <String>{};
  final heldViews = <String, Completer<FlowyResult<ViewPB, FlowyError>>>{};
  final allHeldViews = <Completer<FlowyResult<ViewPB, FlowyError>>>[];
  final allHeldAccess =
      <Completer<FlowyResult<ShareAccessLevel, FlowyError>>>[];
  Completer<FlowyResult<ShareAccessLevel, FlowyError>>? heldAccess;
  ShareAccessLevel access = ShareAccessLevel.fullAccess;
  bool failAccess = false;
  final changes =
      StreamController<DocumentFindHostChange>.broadcast(sync: true);

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String pageId) async {
    viewReads.add(pageId);
    final held = heldViews.remove(pageId);
    if (held != null) return held.future;
    final view = views[pageId];
    return view == null || failedViews.contains(pageId)
        ? FlowyResult.failure(FlowyError(msg: 'Unavailable test metadata'))
        : FlowyResult.success(ViewPB.fromBuffer(view.writeToBuffer()));
  }

  @override
  Future<FlowyResult<ShareAccessLevel, FlowyError>> getAccessLevel(
    String pageId,
  ) async {
    accessReads.add(pageId);
    final held = heldAccess;
    heldAccess = null;
    if (held != null) return held.future;
    return failAccess
        ? FlowyResult.failure(FlowyError(msg: 'Missing test authority'))
        : FlowyResult.success(access);
  }

  Completer<FlowyResult<ShareAccessLevel, FlowyError>> holdAccess() {
    final held =
        heldAccess = Completer<FlowyResult<ShareAccessLevel, FlowyError>>();
    allHeldAccess.add(held);
    return held;
  }

  Completer<FlowyResult<ViewPB, FlowyError>> holdView(String id) {
    final held = heldViews[id] = Completer<FlowyResult<ViewPB, FlowyError>>();
    allHeldViews.add(held);
    return held;
  }

  void change(String id, {bool deleted = false}) => changes.add(
        DocumentFindHostChange(
          id,
          kind: deleted
              ? DocumentFindHostChangeKind.deleted
              : DocumentFindHostChangeKind.updated,
        ),
      );

  void dispose() {
    for (final held in allHeldViews) {
      if (!held.isCompleted) {
        held.complete(FlowyResult.failure(FlowyError(msg: 'Disposed fixture')));
      }
    }
    for (final held in allHeldAccess) {
      if (!held.isCompleted) {
        held.complete(FlowyResult.failure(FlowyError(msg: 'Disposed fixture')));
      }
    }
    unawaited(changes.close());
  }
}

class FindHostDocument extends Cubit<DocumentState> implements DocumentBloc {
  FindHostDocument(this.documentId, EditorState editor)
      : super(
          DocumentState.initial().copyWith(
            editorState: editor,
            isLoading: false,
          ),
        );
  @override
  final String documentId;
  @override
  bool isClosing = false;
  @override
  bool get isLocalMode => true;
  void delete() => emit(state.copyWith(isDeleted: true));
  void forceClose() => emit(state.copyWith(forceClose: true));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FindHostView extends Cubit<ViewState> implements ViewBloc {
  FindHostView(ViewPB view) : super(ViewState.init(view));
  final events = <ViewEvent>[];
  @override
  ViewPB get view => state.view;
  @override
  void add(ViewEvent event) => events.add(event);
  void update(ViewPB view) => emit(state.copyWith(view: view));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FindHostViewInfo extends Fake implements ViewInfoBloc {
  final events = <ViewInfoEvent>[];
  @override
  void add(ViewInfoEvent event) => events.add(event);
}

class FindHostAccess extends Cubit<PageAccessLevelState>
    implements PageAccessLevelBloc {
  FindHostAccess(ViewPB view)
      : super(
          PageAccessLevelState.initial(view).copyWith(
            isLoadingLockStatus: false,
            accessLevel: ShareAccessLevel.fullAccess,
          ),
        );
  void update(PageAccessLevelState value) => emit(value);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FindHostAppearance extends Fake implements AppearanceSettingsCubit {
  @override
  AppearanceSettingsState get state => AppearanceSettingsState(
        appTheme: AppTheme.fallback,
        themeMode: ThemeMode.light,
        font: 'Ahem',
        layoutDirection: LayoutDirection.ltrLayout,
        textDirection: AppFlowyTextDirection.ltr,
        enableRtlToolbarItems: false,
        locale: const Locale('en', 'US'),
        isMenuCollapsed: false,
        menuOffset: 0,
        dateFormat: UserDateFormatPB.Locally,
        timeFormat: UserTimeFormatPB.TwentyFourHour,
        timezoneId: 'UTC',
        documentCursorColor: null,
        documentSelectionColor: null,
        textScaleFactor: 1,
        enableKineticScrolling: false,
      );
}

class _HostStyle extends EditorStyleCustomizer {
  _HostStyle(BuildContext context)
      : super(context: context, padding: const EdgeInsets.all(24));
  @override
  EditorStyle style() => EditorStyle.desktop(
        padding: padding,
        textSpanDecorator: (context, node, start, text, before, after) =>
            decorateWithSearchHighlight(context, node, start, after),
      );
}

class _Strings extends AssetLoader {
  const _Strings();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value({
        'findAndReplace': {
          'find': 'Find',
          'replace': 'Replace',
          'replaceAll': 'Replace all',
          'matchOfTotal': '{} of {}',
          'noResult': 'No results',
        },
      });
}

Widget findHostApp(Widget body, {String mode = 'light'}) {
  final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
  final theme = DesktopAppearance()
      .getThemeData(
        mode == 'paper'
            ? AppTheme.builtins
                .firstWhere((t) => t.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        brightness,
        'Ahem',
        'Ahem',
      )
      .copyWith(platform: TargetPlatform.windows);
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    fallbackLocale: const Locale('en', 'US'),
    path: 'unused-test-translations',
    assetLoader: const _Strings(),
    saveLocale: false,
    child: Builder(
      builder: (context) => MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: AppFlowyTheme(
          data: brightness == Brightness.dark
              ? AppFlowyDefaultTheme().dark()
              : AppFlowyDefaultTheme().light(),
          child: Scaffold(body: body),
        ),
      ),
    ),
  );
}

class RowFindHarness {
  RowFindHarness({this.popup = true}) {
    bind('row-doc');
    title.addListener(() => titleNotifications++);
  }
  final bool popup;
  final repository = FindHostRepository();
  // StreamController.stream creates a new wrapper on each read. A fixture
  // rebuild must not look like a replacement subscription to the native host.
  late final hostChanges = repository.changes.stream;
  final title = TextEditingController(text: 'Visible needle row title');
  final titleFocus = FocusNode();
  final shared = SharedEditorContext()..isInDatabaseRowPage = true;
  final appearance = DocumentAppearanceCubit();
  final view = FindHostView(
    ViewPB(id: 'table', name: 'Table name', layout: ViewLayoutPB.Grid),
  );
  final editors = <EditorState>[];
  final documents = <FindHostDocument>[];
  final writes = <StreamSubscription<EditorTransactionValue>>[];
  late EditorState editor;
  late FindHostDocument document;
  DocumentFindMetadataScope? scope;
  FindHostAccess? inheritedAccess;
  bool showTitle = true;
  bool selected = true;
  int bodyWrites = 0;
  int titleNotifications = 0;
  int titleSubmits = 0;

  void bind(String id) {
    repository.views
        .putIfAbsent(id, () => ViewPB(id: id, name: 'Other orphan'));
    editor = EditorState(
      document: Document(
        root: pageNode(
          children: [
            paragraphNode(text: 'needle body'),
          ],
        ),
      ),
    )..disableSealTimer = true;
    document = FindHostDocument(id, editor);
    editors.add(editor);
    documents.add(document);
    writes.add(
      editor.transactionStream.listen((event) {
        if (event.$1 == TransactionTime.after &&
            event.$2.operations.isNotEmpty) {
          bodyWrites++;
        }
      }),
    );
  }

  Future<void> mount(WidgetTester tester, {String mode = 'light'}) async {
    await tester.pumpWidget(
      findHostApp(
        MultiProvider(
          providers: [
            Provider<AppearanceSettingsCubit>.value(
              value: FindHostAppearance(),
            ),
            Provider<SharedEditorContext>.value(value: shared),
            BlocProvider<DocumentAppearanceCubit>.value(value: appearance),
            BlocProvider<DocumentBloc>.value(value: document),
            BlocProvider<ViewBloc>.value(value: view),
            if (inheritedAccess != null)
              BlocProvider<PageAccessLevelBloc>.value(value: inheritedAccess!),
          ],
          child: RowDocumentFindHost(
            documentId: document.documentId,
            tableViewId: 'table',
            editorState: editor,
            initialDocumentView:
                popup ? repository.views[document.documentId] : null,
            repository: repository,
            changes: hostChanges,
            builder: (context, findScope) {
              scope = findScope;
              return AppFlowyEditorPage(
                key: ObjectKey(editor),
                editorState: editor,
                autoFocus: false,
                useViewInfoBloc: false,
                isSelected: () => selected,
                findMetadataScope: findScope,
                styleCustomizer: _HostStyle(context),
                header: RowDetailScrollHeader(
                  child: showTitle
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(28, 160, 28, 24),
                          child: RowBannerTitleField(
                            controller: title,
                            focusNode: titleFocus,
                            findDocumentId: document.documentId,
                            spacious: popup,
                            onEditingComplete: () => titleSubmits++,
                          ),
                        )
                      : const SizedBox(height: 80),
                ),
              );
            },
          ),
        ),
        mode: mode,
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> open(
    WidgetTester tester, {
    bool replace = false,
    bool fromTitle = true,
  }) async {
    if (showTitle && fromTitle) {
      titleFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(
        replace ? LogicalKeyboardKey.keyH : LogicalKeyboardKey.keyF,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    } else {
      expect(
        ContextualFindRegion.dispatch(
          tester.element(find.byType(AppFlowyEditor)),
          replace: replace,
        ),
        isTrue,
      );
    }
    await tester.pump();
    await tester.pump();
    expect(find.byType(FindAndReplaceMenuWidget), findsOneWidget);
  }

  Future<void> dispose(WidgetTester tester) async {
    DocumentFindMenu.dismiss();
    // Closing defers highlight removal, which can queue native list position
    // reporting for the following frame. Drain both while the list is alive;
    // its dependency does not cancel that callback when the list is disposed.
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
    for (final subscription in writes) {
      unawaited(subscription.cancel());
    }
    for (final bloc in documents) {
      unawaited(bloc.close());
    }
    unawaited(view.close());
    unawaited(appearance.close());
    unawaited(inheritedAccess?.close());
    title.dispose();
    titleFocus.dispose();
    shared.dispose();
    for (final editor in editors) {
      editor.dispose();
      editor.editableNotifier.dispose();
    }
    await tester.pump();
  }
}

FindReplaceBar findHostBar(WidgetTester tester) =>
    tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));

FindAndReplaceMenuWidget findHostMenu(WidgetTester tester) => tester
    .widget<FindAndReplaceMenuWidget>(find.byType(FindAndReplaceMenuWidget));

Future<void> findHostQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('findTextField')), query);
  await tester.pump();
  await tester.pump();
}

Future<void> untilFindHost(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 40 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Bounded wait for native host state');
}
