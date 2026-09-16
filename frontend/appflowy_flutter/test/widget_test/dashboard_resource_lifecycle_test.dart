import 'dart:async';

import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_sync_indicator.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/cover_flip.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/album_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/book_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_versions/page_version_host.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

void main() => runDashboardResourceLifecycleTests();

/// The production previews, with isolated pending repositories instead of the
/// user's workspace. Also runs against the native Windows engine.
void runDashboardResourceLifecycleTests() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final kind in [CollectionKind.book, CollectionKind.album]) {
      final phases = [
        'loading',
        'empty',
        if (kind == CollectionKind.book) ...[
          BookEmbedStyles.shelf,
          BookEmbedStyles.contents,
          BookEmbedStyles.cover,
        ] else ...[
          AlbumEmbedStyles.grid,
          AlbumEmbedStyles.slideshow,
          AlbumEmbedStyles.collage,
          AlbumEmbedStyles.timeline,
          AlbumEmbedStyles.cover,
        ],
      ];
      for (final phase in phases) {
        testWidgets('$appearance: ${kind.name} $phase preview unmounts safely',
            (tester) async {
          final repository = _PendingItems();
          final controller = _controller(kind, repository);
          final visible = ValueNotifier(true);
          if (phase != 'loading') {
            repository.complete(
              phase == 'empty'
                  ? const []
                  : [_item(kind), _item(kind, index: 1)],
            );
          }
          try {
            await _warmLabels(tester, appearance);
            await tester.pumpWidget(
              _app(
                appearance,
                ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (_, show, __) => show
                      ? PageVersionHost(
                          // An empty identity avoids recorders/backend reads.
                          viewId: '',
                          child: _embed(
                            controller,
                            style: phase == 'loading' || phase == 'empty'
                                ? kind == CollectionKind.book
                                    ? BookEmbedStyles.shelf
                                    : AlbumEmbedStyles.grid
                                : phase,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            );
            await tester.pump();
            expect(controller.isLoading, phase == 'loading');
            final preview = tester.state(
              find.byType(
                kind == CollectionKind.book
                    ? BookEmbedPreview
                    : AlbumEmbedPreview,
              ),
            );
            final host = tester.element(find.byType(PageVersionHost));
            expect(tester.takeException(), isNull);

            if (phase == BookEmbedStyles.cover) {
              await tester.tap(find.byType(CoverFlip));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 30));
              expect(
                tester.widget<CoverFlip>(find.byType(CoverFlip)).progress,
                inExclusiveRange(0, 1),
              );
            }

            visible.value = false;
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(preview.mounted, isFalse);
            expect(host.debugIsDefunct, isTrue);
            expect(tester.binding.transientCallbackCount, 0);
            repository.complete(const []);
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull);
            expect(tester.binding.transientCallbackCount, 0);
          } finally {
            repository.complete(const []);
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            visible.dispose();
          }
        });
      }
    }

    testWidgets(
        '$appearance: a closing book never strands four sibling spinners',
        (tester) async {
      final repositories = [for (var i = 0; i < 5; i++) _PendingItems()];
      final kinds = [
        CollectionKind.book,
        CollectionKind.album,
        CollectionKind.bookmark,
        CollectionKind.repository,
        CollectionKind.folder,
      ];
      final controllers = [
        for (var i = 0; i < kinds.length; i++)
          _controller(kinds[i], repositories[i]),
      ];
      // The shelf does not need its optional cover-flip controller. Its
      // dispose used to initialize that controller against a defunct element,
      // aborting Flutter's remaining child teardown and abandoning spinners.
      repositories.first.complete(const []);
      final visible = ValueNotifier(true);
      try {
        await _warmLabels(tester, appearance);
        await tester.pumpWidget(
          _app(
            appearance,
            ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, __) => show
                  ? PageVersionHost(
                      viewId: '',
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final controller in controllers)
                              _embed(controller, style: BookEmbedStyles.shelf),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pump();
        final spinners = find
            .byType(CircularProgressIndicator, skipOffstage: false)
            .evaluate()
            .toList();
        final host = tester.element(find.byType(PageVersionHost));
        expect(spinners, hasLength(4));
        expect(tester.binding.transientCallbackCount, 4);
        expect(tester.takeException(), isNull);

        visible.value = false;
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'host defunct=${host.debugIsDefunct}, '
              'retained spinners=${spinners.where((e) => e.mounted).length}, '
              'tickers=${tester.binding.transientCallbackCount}',
        );
        expect(host.debugIsDefunct, isTrue);
        expect(spinners.every((element) => !element.mounted), isTrue);
        expect(tester.binding.transientCallbackCount, 0);
        for (final repository in repositories) {
          repository.complete(const []);
        }
        await tester.pump(const Duration(seconds: 1));
        expect(
          controllers.every((controller) => !controller.isLoading),
          isTrue,
        );
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      } finally {
        for (final repository in repositories) {
          repository.complete(const []);
        }
        await tester.pumpWidget(const SizedBox());
        for (final controller in controllers) {
          controller.dispose();
        }
        visible.dispose();
      }
    });

    testWidgets('$appearance: an idle calendar sync indicator unmounts safely',
        (tester) async {
      final workspace = CalendarWorkspace(providers: [_OfflineCalendar()]);
      try {
        await _warmLabels(tester, appearance);
        await tester.pumpWidget(
          _app(appearance, CalendarSyncIndicator(workspace: workspace)),
        );
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      } finally {
        workspace.dispose();
      }
    });
  }
}

CollectionEmbedController _controller(
  CollectionKind kind,
  WorkspaceItemRepository repository,
) =>
    CollectionEmbedController(
      collection: ViewPB(
        id: 'resource-fixture-${kind.name}',
        name: 'Collection',
        extra: CollectionMetadata.newExtra(kind),
      ),
      repository: repository,
      listenForUpdates: false,
    );

// An audio item exercises every album layout without image IO, native players,
// network, or thumbnail workers. A book chapter likewise needs no backend.
ViewPB _item(CollectionKind kind, {int index = 0}) => ViewPB(
      id: 'resource-fixture-item-$index',
      name: kind == CollectionKind.book ? 'Chapter' : 'Track.mp3',
      layout: ViewLayoutPB.Document,
      extra: kind == CollectionKind.book
          ? ''
          : const WorkspaceItemMetadata.file(
              contentKind: WorkspaceFileContentKind.binary,
              storageUrl: '',
            ).mergeIntoExtra(''),
    );

Widget _embed(CollectionEmbedController controller, {required String style}) =>
    SizedBox(
      width: 640,
      height: 320,
      child: CollectionEmbed(
        collection: controller.collection,
        controller: controller,
        fullscreen: true,
        settings: CollectionEmbedSettings(style: style),
        onSettingsChanged: (_) {},
      ),
    );

Future<void> _warmLabels(WidgetTester tester, String appearance) async {
  // Resolve localization before mounting deliberately-pending spinners; those
  // spinners intentionally cannot pumpAndSettle until their owner is removed.
  await tester.pumpWidget(_app(appearance, const SizedBox()));
  await tester.pumpAndSettle();
}

Widget _app(String appearance, Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: DesktopAppearance().getThemeData(
            appearance == 'paper'
                ? AppTheme.builtins
                    .firstWhere((t) => t.themeName == BuiltInTheme.paper)
                : AppTheme.fallback,
            appearance == 'dark' ? Brightness.dark : Brightness.light,
            defaultFontFamily,
            builtInCodeFontFamily,
          ),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );

class _PendingItems implements WorkspaceItemRepository {
  final _result = Completer<FlowyResult<List<ViewPB>, FlowyError>>();

  void complete(List<ViewPB> items) {
    if (!_result.isCompleted) _result.complete(FlowySuccess(items));
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) =>
      _result.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineCalendar extends CalendarProvider {
  @override
  CalendarService get service => CalendarService.google;

  @override
  CalendarSyncStatus get status =>
      const CalendarSyncStatus(state: CalendarSyncState.offline);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
