import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/bookmark_plugin.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_card.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_context_menu.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_feed_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_grid_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_page_preview.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_shelf_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_timeline_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_toolbar.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_service.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart';

// Production opening callbacks and live modal permission changes. Opening-only
// tests inspect route descriptions; mounted readers substitute snapshot IO,
// backend writes and the website leaf, not the permission or dismissal logic.
// The query probe exercises retained local state, not native WebView behavior.
late Map<String, dynamic> _translations;
const _localizedHomeKey = ValueKey('bookmark-permission-home');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontFetching = GoogleFonts.config.allowRuntimeFetching;
  late bool sharedSectionWasOn;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await prepareVividIconTestAssets();
    _translations = await const TestBundleAssetLoader().load(
      'assets/translations',
      const Locale('en', 'US'),
    );
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);
  setUp(() async {
    sharedSectionWasOn = FeatureFlag.sharedSection.isOn;
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(_MemoryKeyValue());
    await FeatureFlag.sharedSection.turnOn();
  });
  tearDown(() async {
    await FeatureFlag.sharedSection.update(sharedSectionWasOn);
    await getIt.popScope();
  });

  _test('collection lookup reads live access and graph locks at invocation',
      (tester) async {
    final fixture = _CollectionFixture();
    late BuildContext source;
    try {
      await _pumpApp(
        tester,
        _app(
          BlocProvider<PageAccessLevelBloc>.value(
            value: fixture.access,
            child: Builder(
              builder: (context) {
                source = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      bool readOnly() => bookmarkCollectionReadOnly(source, fixture.collection);
      expect(readOnly(), isFalse);
      fixture.access.change(ShareAccessLevel.readOnly);
      expect(readOnly(), isTrue);
      fixture.access.change(ShareAccessLevel.readAndWrite);
      expect(readOnly(), isFalse);
      fixture.access.change(ShareAccessLevel.fullAccess, locked: true);
      expect(readOnly(), isTrue);
      fixture.access.change(ShareAccessLevel.fullAccess);
      fixture.lock(true);
      expect(
        fixture.collection.collectionView.isLocked,
        isFalse,
        reason: 'The handed-out collection view is deliberately stale.',
      );
      expect(readOnly(), isTrue);
      fixture.lock(false);
      expect(readOnly(), isFalse);

      await FeatureFlag.sharedSection.update(false);
      fixture.access.change(ShareAccessLevel.readOnly);
      expect(
        readOnly(),
        isFalse,
        reason: 'Use isEditable, including its existing feature-flag rule.',
      );
      fixture.access.change(ShareAccessLevel.readOnly, locked: true);
      expect(readOnly(), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.dispose(tester);
    }
  });

  for (final unrelatedBloc in [false, true]) {
    _test('missing/mismatched access ($unrelatedBloc) keeps lock-only fallback',
        (tester) async {
      final fixture = _CollectionFixture();
      final ambient = _AccessBloc(
        ViewPB(id: 'unrelated-page'),
        ShareAccessLevel.readOnly,
      );
      late BuildContext source;
      try {
        final probe = Builder(
          builder: (context) {
            source = context;
            return const SizedBox();
          },
        );
        await _pumpApp(
          tester,
          _app(
            unrelatedBloc
                ? BlocProvider<PageAccessLevelBloc>.value(
                    value: ambient,
                    child: probe,
                  )
                : probe,
          ),
        );
        expect(bookmarkCollectionReadOnly(source, fixture.collection), isFalse);
        fixture.lock(true);
        expect(bookmarkCollectionReadOnly(source, fixture.collection), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _closeAccessBloc(tester, ambient);
        await fixture.dispose(tester);
      }
    });
  }

  for (final appearance in vividIconTestAppearances) {
    for (final surface in _Surface.values) {
      for (final readOnly in [false, true]) {
        _test('$appearance ${surface.name}: opener forwards live $readOnly',
            (tester) async {
          final fixture = _CollectionFixture();
          final routes = _Routes();
          try {
            await fixture.explorer.initialize();
            fixture.access.change(
              readOnly
                  ? ShareAccessLevel.fullAccess
                  : ShareAccessLevel.readOnly,
            );
            await _pumpApp(
              tester,
              _app(
                BlocProvider<PageAccessLevelBloc>.value(
                  value: fixture.access,
                  child: _surface(surface, fixture.collection),
                ),
                appearance: appearance,
                routes: routes,
              ),
            );
            await _pumpReaderTransition(tester);
            final host = find.byType(BookmarkScaffold);
            final source = tester.element(host);
            final controller = tester.widget<BookmarkScaffold>(host).controller;
            final entry = controller.entries.single;
            final open = _openCallback(tester, surface);
            expect(controller.state.activeId, isNull);

            // Do not rebuild the row/card: invoke its already-captured callback
            // after permission changes, exactly as a delayed user action can.
            fixture.access.change(
              readOnly
                  ? ShareAccessLevel.readOnly
                  : ShareAccessLevel.fullAccess,
            );
            open();
            expect(
              find.byType(BookmarkReader),
              findsNothing,
              reason: 'Opening-only checks must not mount native reader IO.',
            );
            final reader =
                _dialogContent(routes.dialog, source) as BookmarkReader;
            _expectHandoff(reader, entry, controller, readOnly: readOnly);
            expect(fixture.opened, isEmpty);
            expect(fixture.openedViews, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await fixture.dispose(tester);
          }
        });
      }
    }
  }

  _test('menu Read resolves permission when selected, not when the menu opens',
      (tester) async {
    final fixture = _CollectionFixture();
    final controller = BookmarkController()..setViews([fixture.bookmark]);
    final routes = _Routes();
    late BuildContext source;
    try {
      await _pumpApp(
        tester,
        _app(
          BlocProvider<PageAccessLevelBloc>.value(
            value: fixture.access,
            child: Builder(
              builder: (context) {
                source = context;
                return const SizedBox.expand();
              },
            ),
          ),
          routes: routes,
        ),
      );
      final entry = controller.entries.single;
      unawaited(
        showBookmarkMenu(
          context: source,
          entry: entry,
          controller: controller,
          collection: fixture.collection,
          position: const Offset(20, 20),
        ),
      );
      await _pumpReaderTransition(tester);
      final readRow = tester.widget<AppMenuRow>(
        find.widgetWithText(
          AppMenuRow,
          LocaleKeys.collections_bookmark_read.tr(),
        ),
      );
      expect(readRow.enabled, isTrue);
      expect(readRow.onTap, isNotNull);
      fixture.access.change(ShareAccessLevel.readOnly);
      readRow.onTap!();
      // Allow the menu's deferred action without advancing the native reader.
      await tester.pump();
      expect(
        find.byType(BookmarkReader),
        findsNothing,
        reason: 'Inspect the deferred opening before mounting native IO.',
      );
      final reader = _dialogContent(routes.dialog, source) as BookmarkReader;
      _expectHandoff(reader, entry, controller, readOnly: true);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await fixture.dispose(tester);
    }
  });

  for (final revocation in ['access', 'root']) {
    for (final waitForDebounce in [false, true]) {
      _test(
          '$revocation revocation with pending query/notes, debounce=$waitForDebounce: outside close writes nothing',
          (tester) async {
        final fixture = _ModalFixture();
        try {
          // An explicit false is not a grant that can override live access.
          await fixture.mount(tester);
          final readerFinder = find.byType(BookmarkReader);
          final reader = tester.widget<BookmarkReader>(readerFinder);
          final readerState = tester.state(readerFinder);
          final leaf =
              tester.state<_ReaderProbeState>(find.byType(_ReaderProbe));
          final notes = tester.widget<TextField>(_readerKey('notes'));
          final tags = tester.widget<TextField>(_readerKey('tag-input'));
          final notesElement = tester.element(_readerKey('notes'));
          final star =
              _readerAction(tester, Icons.star_outline_rounded).onPressed!;
          final download =
              _readerAction(tester, Icons.download_rounded).onPressed!;
          final original =
              fixture.controller.entries.single.view.writeToBuffer();
          await tester.enterText(_readerQuery, 'retained query');
          leaf.query.selection =
              const TextSelection(baseOffset: 1, extentOffset: 5);
          await tester.enterText(_readerKey('notes'), 'Pending private notes');
          notes.controller!.selection =
              const TextSelection(baseOffset: 2, extentOffset: 8);
          await tester.enterText(_readerKey('tag-input'), 'pending-tag');
          final queryValue = leaf.query.value;
          final notesValue = notes.controller!.value;

          if (revocation == 'access') {
            fixture.source.access.change(ShareAccessLevel.readOnly);
          } else {
            fixture.source.lock(true);
            expect(fixture.source.collection.collectionView.isLocked, isFalse);
          }
          // Invoke callbacks before any rebuild/stream delivery. They must
          // consult the captured sources, not this old writable description.
          expect(reader.readOnly, isFalse);
          expect(reader.canEdit!(), isFalse);
          star();
          download();
          tags.onSubmitted!('late tag');
          notes.onChanged!('late change');
          expect(fixture.service.writes, isEmpty);
          expect(fixture.controller.refreshes, isEmpty);
          await _pumpReader(tester);
          expect(tester.widget<BookmarkReader>(readerFinder).readOnly, isTrue);
          expect(tester.state(readerFinder), same(readerState));
          expect(tester.state(find.byType(_ReaderProbe)), same(leaf));
          expect(tester.element(_readerKey('notes')), same(notesElement));
          expect(
            tester.widget<TextField>(_readerKey('notes')).controller,
            same(notes.controller),
          );
          expect(notes.controller!.value, notesValue);
          expect(leaf.query.value, queryValue);
          expect(tags.controller!.text, 'pending-tag');
          expect(
            tester.widget<TextField>(_readerKey('notes')).readOnly,
            isTrue,
          );
          expect(
            tester.widget<TextField>(_readerKey('tag-input')).readOnly,
            isTrue,
          );
          expect(
            _readerAction(tester, Icons.star_outline_rounded).onPressed,
            isNull,
          );
          expect(
            _readerAction(tester, Icons.download_rounded).onPressed,
            isNull,
          );

          // Page interaction/search is not AppFlowy bookmark metadata.
          expect(tester.widget<TextField>(_readerQuery).readOnly, isFalse);
          await tester.enterText(_readerQuery, 'website query still editable');
          expect(leaf.query.text, 'website query still editable');
          if (waitForDebounce) {
            await tester.pump(const Duration(milliseconds: 650));
            expect(fixture.service.writes, isEmpty);
          }
          await _closeReader(tester);
          await tester.pump(const Duration(seconds: 1));
          expect(fixture.service.writes, isEmpty);
          expect(fixture.controller.refreshes, isEmpty);
          expect(
            fixture.controller.entries.single.view.writeToBuffer(),
            original,
          );
          expect(
            fixture.controller.state.activeId,
            fixture.source.bookmark.id,
            reason: 'Opening/history is still allowed.',
          );
          expect(fixture.source.access.isClosed, isFalse);
          expect(fixture.source.explorer.hasRegisteredListeners, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      });
    }
  }

  _test('unmounting the opener denies callbacks and the final draft flush',
      (tester) async {
    final fixture = _ModalFixture();
    try {
      await fixture.mount(tester);
      final reader = tester.widget<BookmarkReader>(find.byType(BookmarkReader));
      final readerState = tester.state(find.byType(BookmarkReader));
      final star = _readerAction(tester, Icons.star_outline_rounded).onPressed!;
      await tester.enterText(_readerQuery, 'query survives its opener');
      await tester.enterText(_readerKey('notes'), 'Unmounted owner draft');
      fixture.ownerVisible.value = false;
      await _pumpReader(tester);
      expect(fixture.owner.mounted, isFalse);
      expect(tester.state(find.byType(BookmarkReader)), same(readerState));
      expect(reader.canEdit!(), isFalse);
      star();
      await tester.pump(const Duration(milliseconds: 650));
      expect(fixture.service.writes, isEmpty);
      expect(
        tester.widget<TextField>(_readerKey('notes')).controller!.text,
        'Unmounted owner draft',
      );
      await _closeReader(tester);
      expect(fixture.service.writes, isEmpty);
      expect(fixture.source.access.isClosed, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final explicitReadOnly in [false, true]) {
    _test('live unlock/regrant retains the reader, explicit=$explicitReadOnly',
        (tester) async {
      final fixture = _ModalFixture();
      try {
        await fixture.mount(tester, readOnly: explicitReadOnly);
        final readerFinder = find.byType(BookmarkReader);
        final state = tester.state(readerFinder);
        final leaf = tester.state(find.byType(_ReaderProbe));
        await tester.enterText(_readerQuery, 'retained through access updates');
        fixture.source.access.change(ShareAccessLevel.readOnly);
        await _pumpReader(tester);
        expect(tester.widget<BookmarkReader>(readerFinder).readOnly, isTrue);
        fixture.source.lock(true);
        fixture.source.access.change(ShareAccessLevel.fullAccess);
        await _pumpReader(tester);
        expect(
          tester.widget<BookmarkReader>(readerFinder).readOnly,
          isTrue,
          reason: 'The live root lock still wins.',
        );
        fixture.source.lock(false);
        await _pumpReader(tester);
        expect(
          tester.widget<BookmarkReader>(readerFinder).readOnly,
          explicitReadOnly,
        );
        expect(
          tester.widget<TextField>(_readerKey('notes')).readOnly,
          explicitReadOnly,
        );
        expect(tester.state(readerFinder), same(state));
        expect(tester.state(find.byType(_ReaderProbe)), same(leaf));
        expect(
          tester.widget<TextField>(_readerQuery).controller!.text,
          'retained through access updates',
        );
        await _closeReader(tester);
        expect(fixture.service.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  for (final unrelatedBloc in [false, true]) {
    _test('modal missing/mismatched access ($unrelatedBloc) is lock-only',
        (tester) async {
      final fixture = _ModalFixture();
      final ambient =
          _AccessBloc(ViewPB(id: 'unrelated-page'), ShareAccessLevel.readOnly);
      try {
        await fixture.mount(tester, withAccess: unrelatedBloc, access: ambient);
        final readerFinder = find.byType(BookmarkReader);
        expect(tester.widget<BookmarkReader>(readerFinder).readOnly, isFalse);
        ambient.change(ShareAccessLevel.readOnly, locked: true);
        await _pumpReader(tester);
        expect(tester.widget<BookmarkReader>(readerFinder).readOnly, isFalse);
        fixture.source.lock(true);
        await _pumpReader(tester);
        expect(tester.widget<BookmarkReader>(readerFinder).readOnly, isTrue);
        fixture.source.lock(false);
        await _pumpReader(tester);
        expect(tester.widget<BookmarkReader>(readerFinder).readOnly, isFalse);
        await tester.enterText(
          _readerKey('notes'),
          'Still owned by this library',
        );
        await _closeReader(tester);
        expect(
          fixture.service.writes.single.notes,
          'Still owned by this library',
        );
        expect(ambient.isClosed, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        await _closeAccessBloc(tester, ambient);
      }
    });
  }

  for (final readOnly in [false, true]) {
    _test(
        'direct reader keeps explicit readOnly=$readOnly despite ambient denial',
        (tester) async {
      final fixture = _ModalFixture();
      try {
        fixture.source.access.change(ShareAccessLevel.readOnly, locked: true);
        fixture.source.lock(true);
        await _pumpApp(
          tester,
          _app(
            BlocProvider<PageAccessLevelBloc>.value(
              value: fixture.source.access,
              child: BookmarkReader(
                entryId: fixture.source.bookmark.id,
                controller: fixture.controller,
                standalone: true,
                readOnly: readOnly,
                snapshots: fixture.snapshots,
                webPageBuilder: _readerProbe,
              ),
            ),
          ),
        );
        final reader =
            tester.widget<BookmarkReader>(find.byType(BookmarkReader));
        expect(reader.canEdit, isNull);
        expect(reader.readOnly, readOnly);
        expect(
          tester.widget<TextField>(_readerKey('notes')).readOnly,
          readOnly,
        );
        expect(tester.widget<TextField>(_readerQuery).readOnly, isFalse);
        await tester.enterText(_readerQuery, 'website remains interactive');
        if (readOnly) {
          tester.widget<TextField>(_readerKey('notes')).onChanged!('blocked');
        } else {
          await tester.enterText(_readerKey('notes'), 'Direct reader draft');
        }
        await tester.pump(const Duration(milliseconds: 650));
        expect(fixture.service.writes, hasLength(readOnly ? 0 : 1));
        if (!readOnly) {
          expect(fixture.service.writes.single.notes, 'Direct reader draft');
        }
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  for (final revocation in ['access', 'root', 'owner']) {
    _test(
        'pending download after $revocation revocation has no reader follow-up',
        (tester) async {
      final fixture = _ModalFixture();
      final gate = fixture.controller.refreshGate = Completer<void>();
      try {
        await fixture.mount(tester);
        final leaf = tester.state(find.byType(_ReaderProbe));
        _readerAction(tester, Icons.download_rounded).onPressed!();
        await _pumpReader(tester);
        expect(fixture.controller.refreshes, [fixture.source.bookmark.id]);
        if (revocation == 'access') {
          fixture.source.access.change(ShareAccessLevel.readOnly);
        } else if (revocation == 'root') {
          fixture.source.lock(true);
        } else {
          fixture.ownerVisible.value = false;
        }
        await _pumpReader(tester);
        final reads = fixture.snapshots.reads.length;
        // The already-delegated operation still completes; only subsequent
        // reader work can be stopped without changing the controller API.
        gate.complete();
        await _pumpReader(tester);
        expect(fixture.snapshots.reads.length, reads);
        expect(tester.state(find.byType(_ReaderProbe)), same(leaf));
        expect(fixture.service.writes, isEmpty);
        await _closeReader(tester);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  _test(
      'standalone plugin lends its bloc and retains the reader on access changes',
      (tester) async {
    // No bookmark envelope: the real reader mounts without starting a website
    // or writing metadata. This test concerns ownership and live propagation.
    final view = ViewPB(id: 'standalone-bookmark', isLocked: true);
    final access = _AccessBloc(view, ShareAccessLevel.fullAccess);
    final ambient = _AccessBloc(view, ShareAccessLevel.readOnly);
    final body = BookmarkPluginWidgetBuilder(
      notifier: _Notifier(view),
      viewInfoBloc: _ViewInfoBloc(),
      pageAccessLevelBloc: access,
    ).buildWidget(context: PluginContext(), shrinkWrap: false);
    try {
      expect(body, isA<BlocProvider<PageAccessLevelBloc>>());
      expect(
        (body as BlocProvider<PageAccessLevelBloc>).child,
        isA<BookmarkPage>(),
      );
      expect(body.child!.key, ValueKey(view.id));
      await _pumpApp(
        tester,
        _app(
          BlocProvider<PageAccessLevelBloc>.value(
            value: ambient,
            child: body,
          ),
        ),
      );
      final finder = find.byType(BookmarkReader);
      final reader = tester.widget<BookmarkReader>(finder);
      final state = tester.state(finder);
      expect(tester.element(finder).read<PageAccessLevelBloc>(), same(access));
      expect(reader.standalone, isTrue);
      expect(reader.entryId, view.id);
      expect(access.state.isEditable, isTrue);
      expect(
        reader.readOnly,
        isTrue,
        reason: 'The initial view lock is known before the bloc lock loads.',
      );
      access.change(ShareAccessLevel.fullAccess);
      await _pumpReader(tester);
      expect(
        tester.widget<BookmarkReader>(finder).readOnly,
        isFalse,
        reason: 'A live unlock must supersede the original locked widget.',
      );
      for (final level in [
        ShareAccessLevel.readOnly,
        ShareAccessLevel.readAndWrite,
        ShareAccessLevel.fullAccess,
      ]) {
        access.change(level);
        await _pumpReader(tester);
        final updated = tester.widget<BookmarkReader>(finder);
        expect(updated.readOnly, !access.state.isEditable);
        expect(updated.controller, same(reader.controller));
        expect(tester.state(finder), same(state));
      }
      access.change(ShareAccessLevel.fullAccess, locked: true);
      await _pumpReader(tester);
      expect(tester.widget<BookmarkReader>(finder).readOnly, isTrue);
      access.change(ShareAccessLevel.fullAccess);
      await _pumpReader(tester);
      expect(tester.widget<BookmarkReader>(finder).readOnly, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(access.isClosed, isFalse);
      expect(ambient.isClosed, isFalse);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _closeAccessBloc(tester, access);
      await _closeAccessBloc(tester, ambient);
    }
  });

  _test(
      'page preview carries the source bloc across the navigator without owning it',
      (tester) async {
    final access = _AccessBloc(
      ViewPB(id: 'source-document'),
      ShareAccessLevel.readOnly,
    );
    final routes = _Routes();
    late BuildContext source;
    try {
      await _pumpApp(
        tester,
        _app(
          BlocProvider<PageAccessLevelBloc>.value(
            value: access,
            child: Builder(
              builder: (context) {
                source = context;
                return const SizedBox();
              },
            ),
          ),
          routes: routes,
        ),
      );
      unawaited(
        openBookmarkPagePreview(
          context: source,
          url: 'https://bookmark-permissions.invalid/article',
          title: 'Saved article',
        ),
      );
      final content = _dialogContent(routes.dialog, source);
      expect(content, isA<BlocProvider<PageAccessLevelBloc>>());
      final provider = content as BlocProvider<PageAccessLevelBloc>;
      late PageAccessLevelBloc observed;
      late bool readOnly;
      // A new home on the same Navigator would retain the queued preview.
      // Remove that navigator before it ever builds the IO-owning dialog.
      await tester.pumpWidget(const SizedBox.shrink());
      // Mount the returned provider with a probe in place of its IO-owning
      // private link reader. This checks the real handoff, not disk/WebView IO.
      await _pumpApp(
        tester,
        _app(
          MultiBlocProvider(
            providers: [provider],
            child: Builder(
              builder: (context) {
                observed = context.watch<PageAccessLevelBloc>();
                readOnly = !observed.state.isEditable;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(observed, same(access));
      expect(readOnly, isTrue);
      access.change(ShareAccessLevel.fullAccess);
      await _pumpReader(tester);
      expect(readOnly, isFalse);
      access.change(ShareAccessLevel.fullAccess, locked: true);
      await _pumpReader(tester);
      expect(readOnly, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(access.isClosed, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _closeAccessBloc(tester, access);
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      timeout: const Timeout(Duration(seconds: 30)),
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

enum _Surface { grid, feed, shelf, timeline }

Widget _surface(_Surface surface, CollectionViewContext collection) =>
    switch (surface) {
      _Surface.grid => BookmarkGridView(collection: collection),
      _Surface.feed => BookmarkFeedView(collection: collection),
      _Surface.shelf => BookmarkShelfView(collection: collection),
      _Surface.timeline => BookmarkTimelineView(collection: collection),
    };

VoidCallback _openCallback(WidgetTester tester, _Surface surface) {
  if (surface == _Surface.grid || surface == _Surface.shelf) {
    return tester.widget<BookmarkCard>(find.byType(BookmarkCard)).onOpen;
  }
  return tester
      .widget<GestureDetector>(
        find.byWidgetPredicate(
          (widget) =>
              widget is GestureDetector &&
              widget.onTap != null &&
              widget.onSecondaryTapDown != null,
        ),
      )
      .onTap!;
}

Widget _dialogContent(RawDialogRoute<void> route, BuildContext context) {
  Widget content = route.buildPage(
    context,
    const AlwaysStoppedAnimation<double>(1),
    const AlwaysStoppedAnimation<double>(0),
  );
  while (true) {
    if (content is Semantics) {
      content = content.child!;
    } else if (content is DisplayFeatureSubScreen) {
      content = content.child;
    } else if (content is ListenableBuilder) {
      content = content.builder(context, content.child);
    } else if (content is StreamBuilder<PageAccessLevelState>) {
      content = content.builder(
        context,
        const AsyncSnapshot<PageAccessLevelState>.nothing(),
      );
    } else {
      return content;
    }
  }
}

void _expectHandoff(
  BookmarkReader reader,
  BookmarkEntry entry,
  BookmarkController controller, {
  required bool readOnly,
}) {
  expect(reader.readOnly, readOnly);
  expect(reader.canEdit, isNotNull);
  expect(reader.entryId, entry.id);
  expect(reader.controller, same(controller));
  expect(reader.standalone, isFalse);
  expect(reader.webPageBuilder, isNull);
  expect(reader.offlinePreviewBuilder, isNull);
  expect(controller.state.activeId, entry.id);
  expect(controller.entryFor(entry.id), same(entry));
}

Widget _app(
  Widget child, {
  String appearance = 'paper',
  _Routes? routes,
}) =>
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      startLocale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: vividIconTestTheme(appearance),
          themeAnimationDuration: Duration.zero,
          navigatorObservers: [if (routes != null) routes],
          home: Scaffold(key: _localizedHomeKey, body: child),
        ),
      ),
    );

class _Translations extends AssetLoader {
  const _Translations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

Finder _readerKey(String suffix) =>
    find.byKey(ValueKey('bookmark-reader-$suffix'));

Finder get _readerQuery =>
    find.byKey(const ValueKey('bookmark-permission-query'));

BookmarkAction _readerAction(WidgetTester tester, IconData icon) =>
    tester.widget<BookmarkAction>(
      find.byWidgetPredicate(
        (widget) => widget is BookmarkAction && widget.icon == icon,
      ),
    );

Future<void> _pumpApp(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  // The preloaded translations still complete asynchronously. Localizations
  // mounts the Navigator/home on a subsequent frame, not in pumpWidget itself.
  await _pumpReader(tester);
  expect(
    find.byKey(_localizedHomeKey),
    findsOneWidget,
    reason: 'The localized home must mount before using its context/widgets.',
  );
}

Future<void> _pumpReader(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpReaderTransition(WidgetTester tester) async {
  await _pumpReader(tester);
  // Complete the owned transition, not every ticker in the website/fields.
  await tester.pump(BookmarkMetrics.reveal + const Duration(milliseconds: 1));
  await tester.pump();
}

Future<void> _closeAccessBloc(WidgetTester tester, _AccessBloc bloc) async {
  var completed = false;
  final closing = bloc.close().then<void>((_) => completed = true);
  // Observe the actual close Future in its test zone. A cancelled subscription
  // can involve a cached real-zone Future, so yield there without awaiting a
  // fake-zone close inside runAsync (which would prevent the next pump).
  for (var frame = 0; frame < 10 && !completed; frame++) {
    await tester.runAsync(() async {});
    await tester.pump();
  }
  expect(
    completed,
    isTrue,
    reason: 'The borrowed access bloc must finish closing during teardown.',
  );
  await closing;
}

Future<void> _closeReader(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4), kind: PointerDeviceKind.mouse);
  await _pumpReaderTransition(tester);
  expect(find.byType(BookmarkReader), findsNothing);
}

class _ModalFixture {
  _ModalFixture() {
    controller = _ReaderController(service)..setViews([source.bookmark]);
  }

  final source = _CollectionFixture();
  final service = _ReaderService();
  final snapshots = _ReaderSnapshots();
  final ownerVisible = ValueNotifier(true);
  late final _ReaderController controller;
  late BuildContext owner;

  Future<void> mount(
    WidgetTester tester, {
    bool readOnly = false,
    bool withAccess = true,
    PageAccessLevelBloc? access,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _pumpApp(
      tester,
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: ownerVisible,
          builder: (_, visible, __) {
            if (!visible) return const SizedBox.shrink();
            final child = Builder(
              builder: (context) {
                owner = context;
                return const SizedBox.expand();
              },
            );
            return withAccess
                ? BlocProvider<PageAccessLevelBloc>.value(
                    value: access ?? source.access,
                    child: child,
                  )
                : child;
          },
        ),
      ),
    );
    unawaited(
      openBookmarkReader(
        context: owner,
        entry: controller.entries.single,
        controller: controller,
        collection: source.collection,
        readOnly: readOnly,
        snapshots: snapshots,
        webPageBuilder: _readerProbe,
      ),
    );
    await _pumpReaderTransition(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final gate = controller.refreshGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await _pumpReader(tester);
    controller.dispose();
    ownerVisible.dispose();
    await source.dispose(tester);
  }
}

class _ReaderController extends BookmarkController {
  _ReaderController(BookmarkService service) : super(service: service);

  final refreshes = <String>[];
  Completer<void>? refreshGate;

  @override
  Future<void> refresh(
    BookmarkEntry entry, {
    bool snapshot = false,
    bool force = true,
  }) async {
    refreshes.add(entry.id);
    await refreshGate?.future;
  }
}

class _ReaderService extends BookmarkService {
  final writes = <BookmarkMetadata>[];

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required BookmarkMetadata metadata,
  }) async {
    writes.add(metadata);
    return FlowyResult.success(
      ViewPB.fromBuffer(view.writeToBuffer())
        ..extra = metadata.mergeIntoExtra(view.extra),
    );
  }
}

class _ReaderSnapshots extends BookmarkSnapshotStore {
  final reads = <String?>[];

  @override
  Future<BookmarkSnapshot?> read(String? directoryPath) {
    reads.add(directoryPath);
    return Future.value();
  }
}

Widget _readerProbe(BuildContext context) => const _ReaderProbe();

class _ReaderProbe extends StatefulWidget {
  const _ReaderProbe();

  @override
  State<_ReaderProbe> createState() => _ReaderProbeState();
}

class _ReaderProbeState extends State<_ReaderProbe> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: TextField(
          key: const ValueKey('bookmark-permission-query'),
          controller: query,
        ),
      );
}

class _CollectionFixture {
  _CollectionFixture() {
    explorer = _ReaderExplorerController(
      root: view,
      repository: _Repository(bookmark),
    );
    access = _AccessBloc(view, ShareAccessLevel.fullAccess);
    collection = CollectionViewContext(
      collectionView: view,
      metadata: const CollectionMetadata(kind: CollectionKind.bookmark),
      definition: CollectionViewDefinition(
        id: 'permission-test',
        labelKey: 'permission-test',
        icon: Icons.bookmark_outline,
        builder: (_, __) => const SizedBox(),
      ),
      explorer: explorer,
      onOpen: opened.add,
      onOpenView: openedViews.add,
      onStateChanged: (key, state) => persisted.add((key, state)),
    );
  }

  final view = ViewPB(
    id: 'bookmark-library',
    name: 'Library',
    extra: CollectionMetadata.newExtra(CollectionKind.bookmark),
  );
  final bookmark = ViewPB(
    id: 'saved-link',
    parentViewId: 'bookmark-library',
    name: 'Saved article',
    extra: const BookmarkMetadata(
      url: 'https://bookmark-permissions.invalid/article',
      title: 'Saved article',
      readState: BookmarkReadState.reading,
    ).mergeIntoExtra(''),
  );
  final opened = <ViewPB>[];
  final openedViews = <String>[];
  final persisted = <(String, Map<String, dynamic>)>[];
  late final _ReaderExplorerController explorer;
  late final _AccessBloc access;
  late final CollectionViewContext collection;

  void lock(bool locked) => explorer.updateView(
        ViewPB.fromBuffer(view.writeToBuffer())..isLocked = locked,
      );

  Future<void> dispose(WidgetTester tester) async {
    explorer.dispose();
    await _closeAccessBloc(tester, access);
  }
}

class _ReaderExplorerController extends WorkspaceExplorerController {
  _ReaderExplorerController({
    required super.root,
    required super.repository,
  }) : super(listenForUpdates: false);

  bool get hasRegisteredListeners => hasListeners;
}

class _AccessBloc extends Cubit<PageAccessLevelState>
    implements PageAccessLevelBloc {
  _AccessBloc(this.view, ShareAccessLevel level)
      : super(
          PageAccessLevelState.initial(view).copyWith(
            accessLevel: level,
            isLoadingLockStatus: false,
          ),
        );

  @override
  final ViewPB view;

  void change(ShareAccessLevel level, {bool locked = false}) => emit(
        state.copyWith(
          view: ViewPB.fromBuffer(state.view.writeToBuffer())
            ..isLocked = locked,
          accessLevel: level,
          isLocked: locked,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository extends Fake implements WorkspaceItemRepository {
  _Repository(this.bookmark);

  final ViewPB bookmark;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) async =>
      FlowyResult.success(id == bookmark.parentViewId ? [bookmark] : []);
}

class _Notifier extends Fake implements ViewPluginNotifier {
  _Notifier(this.view);

  @override
  final ViewPB view;
}

class _ViewInfoBloc extends Fake implements ViewInfoBloc {}

class _MemoryKeyValue extends Fake implements KeyValueStorage {
  @override
  Future<void> set(String key, String value) async {}
}

class _Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  RawDialogRoute<void> get dialog =>
      pushed.whereType<RawDialogRoute<void>>().last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}
