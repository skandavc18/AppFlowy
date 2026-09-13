import 'dart:async';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_chart_panel.dart'
    show AstrologyRuntime;
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_service.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_widgets.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_horoscope_library.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _libraryId = 'horoscope-library';
const _otherLibraryId = 'other-horoscope-library';
const _libraryKey = ValueKey('library-under-test');
const _tableKey = ValueKey('astrology-horoscopes-table');
const _refreshKey = ValueKey('astrology-horoscopes-refresh');
const _errorKey = ValueKey('astrology-horoscopes-error');
const _manualLibrarySpec = DashboardWidgetSpec(
  id: 'manually-inserted-library',
  type: astrologyLibraryWidgetType,
);
const _birthplace = AstrologyPlace(
  name: 'Bengaluru',
  latitude: 12.98,
  longitude: 77.58,
  timeZone: 'Asia/Kolkata',
);
const _newBirthplace = AstrologyPlace(
  name: 'London',
  latitude: 51.51,
  longitude: -0.13,
  timeZone: 'Europe/London',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AstrologyHoroscopeLibrary', () {
    _libraryTest(
      'construction, empty previews and disabled scopes do no IO or listening',
      (tester, harness) async {
        final widget = harness._widget(libraryViewId: '');
        expect(widget.service, same(harness._service));
        expect(harness._repository._requests, isEmpty);
        expect(harness._listeners, isEmpty);
        expect(await harness._service.people(''), isEmpty);
        expect(await harness._service.people('  '), isEmpty);

        for (final scope in const [
          (id: '', enabled: true),
          (id: ' \t ', enabled: true),
          (id: _libraryId, enabled: false),
        ]) {
          await harness._pump(
            tester,
            libraryViewId: scope.id,
            enabled: scope.enabled,
          );
          _expectEmptyPreview(tester);
          await tester.tap(find.byKey(_refreshKey));
          await harness._pump(
            tester,
            libraryViewId: scope.id,
            enabled: scope.enabled,
            refreshToken: 1,
          );
          await tester.pump(const Duration(minutes: 2));
          _expectEmptyPreview(tester);
          expect(harness._repository._requests, isEmpty);
          expect(harness._listeners, isEmpty);
          expect(harness._opened, isEmpty);
        }
        expect(
          find.text('Enable Vedic astrology to read saved horoscopes.'),
          findsOneWidget,
        );
      },
    );

    _libraryTest(
      'one child-list read filters real metadata without per-person reads',
      (tester, harness) async {
        final first = _person('first', name: 'First person');
        final second = _person('second', name: 'Second person');
        final brokenDocument = buildAstrologyDashboard(library: false);
        final inputCard = brokenDocument.allWidgets.first;
        final broken = _dashboardView(
          'broken-profile',
          name: 'Unreadable birth details',
          document: brokenDocument.withWidget(
            inputCard.withSettings(const {'profile': 'not an object'}),
          ),
        );
        final children = List<ViewPB>.unmodifiable([
          _person(_libraryId, name: 'The root must not index itself'),
          ViewPB(id: 'plain-page', parentViewId: _libraryId)..freeze(),
          first,
          _dashboardView(
            'ordinary-dashboard',
            document: DashboardDocument.blank(),
          ),
          _dashboardView('nested-library', document: buildAstrologyDashboard()),
          _dashboardView(
            'grid-with-person-metadata',
            document: first.dashboard!.document,
            layout: ViewLayoutPB.Grid,
          ),
          second,
          broken,
        ]);

        await harness._pump(tester);
        expect(_table(tester).loading, isTrue);
        expect(_refreshButton(tester).onPressed, isNull);
        expect(
          harness._listeners.map((listener) => listener.viewId),
          [_libraryId],
        );
        await harness._succeed(tester, 0, children);

        _expectRows(tester, const ['first', 'second', 'broken-profile']);
        _expectHeaders(tester);
        expect(_cellText(tester, first.id, 'name'), first.name);
        expect(_cellText(tester, first.id, 'date'), '1990-05-15');
        expect(_cellText(tester, first.id, 'time'), '14:50:30');
        expect(_cellText(tester, first.id, 'place'), 'Bengaluru');
        expect(find.text('UTC+05:30 (manual)'), findsNWidgets(2));
        expect(_cellText(tester, broken.id, 'date'), 'Unavailable');
        expect(_cellText(tester, broken.id, 'time'), 'Unavailable');
        expect(_table(tester).error, isNull);
        expect(_table(tester).people.first, same(first));
        expect(() => _table(tester).people.clear(), throwsUnsupportedError);
        expect(
          children,
          hasLength(8),
          reason: 'Filtering must not mutate input.',
        );
        expect(first.childViews, isEmpty);
        expect(harness._repository._requests.single._parentViewId, _libraryId);
        expect(
          harness._listeners.map((listener) => listener.viewId),
          [_libraryId, first.id, second.id, broken.id],
        );

        final parent = harness._listener(_libraryId);
        expect(parent._onViewChildViewsUpdated, isNotNull);
        expect(parent._onViewUpdated, isNull);
        expect(parent._onViewDeleted, isNull);
        expect(parent._onViewMoveToTrash, isNull);
        expect(parent._onViewRestored, isNull);
        for (final person in [first, second, broken]) {
          final listener = harness._listener(person.id);
          expect(listener._startCount, 1);
          expect(listener._stopCount, 0);
          expect(listener._onViewUpdated, isNotNull);
          expect(listener._onViewDeleted, isNotNull);
          expect(listener._onViewMoveToTrash, isNotNull);
          expect(listener._onViewChildViewsUpdated, isNull);
          expect(listener._onViewRestored, isNull);
        }
      },
    );

    _libraryTest(
      'child updates refresh both sidebar renames and saved birth details',
      (tester, harness) async {
        final original = _person('person', name: 'Original name');
        await harness._pump(tester);
        await harness._succeed(tester, 0, [original]);
        final listener = harness._listener(original.id);

        final renamed = _person(original.id, name: 'Renamed in sidebar');
        listener._onViewUpdated!(renamed);
        await harness._succeed(tester, 1, [renamed]);
        expect(_cellText(tester, original.id, 'name'), renamed.name);
        expect(_cellText(tester, original.id, 'date'), '1990-05-15');
        expect(find.text(original.name), findsNothing);

        final updated = _person(
          original.id,
          name: renamed.name,
          input: _birthInput(
            utc: DateTime.utc(2001, 2, 3, 4, 5, 6, 120),
            place: _newBirthplace,
            offsetMinutes: 0,
          ),
        );
        listener._onViewUpdated!(updated);
        await harness._succeed(tester, 2, [updated]);
        expect(_cellText(tester, original.id, 'date'), '2001-02-03');
        expect(_cellText(tester, original.id, 'time'), '04:05:06.12');
        expect(_cellText(tester, original.id, 'place'), 'London');
        expect(find.text('UTC+00:00 (manual)'), findsOneWidget);
        expect(_table(tester).people.single, same(updated));
        expect(harness._listener(original.id), same(listener));
        expect(listener._startCount, 1);
        expect(listener._stopCount, 0);
        expect(harness._listeners, hasLength(2));
        expect(
          harness._repository._requests.map((request) => request._parentViewId),
          [_libraryId, _libraryId, _libraryId],
        );
      },
    );

    _libraryTest(
      'parent membership changes replace rows and retire '
      'only removed listeners',
      (tester, harness) async {
        final removed = _person('removed');
        final retained = _person('retained');
        final added = _person('added');
        await harness._pump(tester);
        await harness._succeed(tester, 0, [removed, retained]);
        final oldOpen = _table(tester).onOpen!;
        final removedRow = _row(tester, removed.id).onSelectChanged!;
        final retainedRow = _row(tester, retained.id).onSelectChanged!;
        final parent = harness._listener(_libraryId);
        final removedListener = harness._listener(removed.id);
        final retainedListener = harness._listener(retained.id);

        parent._onViewChildViewsUpdated!(
          ChildViewUpdatePB(
            parentViewId: _libraryId,
            createChildViews: [added],
            deleteChildViews: [removed.id],
          )..freeze(),
        );
        expect(harness._repository._requests, hasLength(2));
        await harness._succeed(tester, 1, [retained, added]);
        _expectRows(tester, const ['retained', 'added']);
        expect(find.text(removed.name), findsNothing);
        expect(removedListener._stopCount, 1);
        expect(retainedListener._stopCount, 0);
        expect(harness._listener(retained.id), same(retainedListener));
        expect(harness._listener(_libraryId), same(parent));
        expect(harness._listener(added.id)._startCount, 1);
        expect(harness._listeners, hasLength(4));

        oldOpen(removed);
        removedRow(true);
        oldOpen(_person('not-a-child'));
        oldOpen(_person(''));
        expect(harness._opened, isEmpty);
        oldOpen(retained);
        retainedRow(true);
        expect(harness._opened, [same(retained), same(retained)]);
        await tester.tap(_cellFinder(added.id, 'name'));
        expect(harness._opened.last, same(added));
        expect(harness._repository._requests, hasLength(2));
      },
    );

    _libraryTest(
      'child deletion and trash notifications re-read membership '
      'without writes',
      (tester, harness) async {
        final deleted = _person('deleted');
        final trashed = _person('trashed');
        await harness._pump(tester);
        await harness._succeed(tester, 0, [deleted, trashed]);
        final deletedListener = harness._listener(deleted.id);
        final trashedListener = harness._listener(trashed.id);

        deletedListener._onViewDeleted!(FlowyResult.success(deleted));
        await harness._succeed(tester, 1, [trashed]);
        _expectRows(tester, const ['trashed']);
        expect(deletedListener._stopCount, 1);
        expect(trashedListener._stopCount, 0);

        trashedListener._onViewMoveToTrash!(
          FlowyResult.success(DeletedViewPB(viewId: trashed.id)..freeze()),
        );
        await harness._succeed(tester, 2, const []);
        _expectRows(tester, const []);
        expect(trashedListener._stopCount, 1);
        expect(harness._listener(_libraryId)._stopCount, 0);
        expect(find.textContaining('Generate a chart above'), findsOneWidget);
        expect(_refreshButton(tester).onPressed, isNotNull);
      },
    );

    _libraryTest(
      'manual refresh is single-flight and a read error offers a working retry',
      (tester, harness) async {
        final original = _person('original');
        final added = _person('after-retry');
        await harness._pump(tester);
        await harness._succeed(tester, 0, [original]);
        final oldRefresh = _table(tester).onRefresh!;
        await tester.tap(find.byKey(_refreshKey));
        await tester.pump();
        expect(_table(tester).loading, isTrue);
        expect(_refreshButton(tester).onPressed, isNull);
        oldRefresh();
        expect(harness._repository._requests, hasLength(2));
        _expectRows(tester, const ['original']);

        await harness._fail(tester, 1, 'offline');
        expect(_table(tester).loading, isFalse);
        expect(_table(tester).error, contains('offline'));
        expect(find.byKey(_errorKey), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(_refreshButton(tester).onPressed, isNotNull);
        _expectRows(tester, const ['original']);
        expect(harness._listener(original.id)._stopCount, 0);

        await tester.tap(find.byKey(_refreshKey));
        await tester.pump();
        expect(_table(tester).error, isNull);
        expect(_refreshButton(tester).onPressed, isNull);
        expect(harness._repository._requests, hasLength(3));
        await harness._succeed(tester, 2, [original, added]);
        _expectRows(tester, const ['original', 'after-retry']);
        expect(find.byKey(_errorKey), findsNothing);
        expect(find.text('Refresh'), findsOneWidget);
        expect(harness._listeners, hasLength(3));
      },
    );

    _libraryTest(
      'only a changed refreshToken reloads during otherwise identical rebuilds',
      (tester, harness) async {
        final original = _person('person');
        final otherOpened = <ViewPB>[];
        await harness._pump(tester);
        await harness._succeed(tester, 0, [original]);
        final state = tester.state(find.byKey(_libraryKey));
        final personListener = harness._listener(original.id);

        await harness._pump(tester);
        await harness._pump(tester, onOpen: otherOpened.add);
        await tester.pump(const Duration(minutes: 2));
        expect(tester.state(find.byKey(_libraryKey)), same(state));
        expect(harness._repository._requests, hasLength(1));
        await tester.tap(_cellFinder(original.id, 'name'));
        expect(otherOpened, [same(original)]);
        expect(harness._opened, isEmpty);

        await harness._pump(tester, refreshToken: 1, onOpen: otherOpened.add);
        expect(_table(tester).loading, isTrue);
        expect(harness._repository._requests, hasLength(2));
        await harness._pump(tester, refreshToken: 1, onOpen: otherOpened.add);
        expect(harness._repository._requests, hasLength(2));
        final updated = _person(original.id, name: 'Refreshed once');
        await harness._succeed(tester, 1, [updated]);
        await harness._pump(tester, refreshToken: 1, onOpen: otherOpened.add);
        expect(_cellText(tester, original.id, 'name'), updated.name);
        expect(harness._repository._requests, hasLength(2));
        expect(harness._listeners, hasLength(2));
        expect(harness._listener(original.id), same(personListener));
        expect(personListener._startCount, 1);
        expect(personListener._stopCount, 0);
      },
    );

    _libraryTest(
      'a late older success cannot replace the newest data or its listeners',
      (tester, harness) async {
        await harness._pump(tester);
        harness._listener(_libraryId)._notifyChildren();
        expect(harness._repository._requests, hasLength(2));
        final latest = _person('latest');
        await harness._succeed(tester, 1, [latest]);
        final latestListener = harness._listener(latest.id);
        await harness._succeed(tester, 0, [_person('obsolete')]);

        _expectRows(tester, const ['latest']);
        expect(_table(tester).people.single, same(latest));
        expect(_table(tester).loading, isFalse);
        expect(_table(tester).error, isNull);
        expect(
          harness._listeners.map((listener) => listener.viewId),
          [_libraryId, latest.id],
        );
        expect(harness._listener(latest.id), same(latestListener));
        expect(latestListener._stopCount, 0);
      },
    );

    _libraryTest(
      'an older error arriving after newer data is ignored',
      (tester, harness) async {
        await harness._pump(tester);
        await harness._pump(tester, refreshToken: 1);
        expect(harness._repository._requests, hasLength(2));
        final latest = _person('latest');
        await harness._succeed(tester, 1, [latest]);
        await harness._fail(tester, 0, 'obsolete failure');

        _expectRows(tester, const ['latest']);
        expect(_table(tester).error, isNull);
        expect(_table(tester).loading, isFalse);
        expect(find.byKey(_errorKey), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(harness._listeners, hasLength(2));
        await tester.tap(_cellFinder(latest.id, 'name'));
        expect(harness._opened.single, same(latest));
      },
    );

    _libraryTest(
      'an older success cannot clear the latest error; retry can recover',
      (tester, harness) async {
        await harness._pump(tester);
        harness._listener(_libraryId)._notifyChildren();
        await harness._fail(tester, 1, 'latest failure');
        await harness._succeed(tester, 0, [_person('obsolete')]);

        _expectRows(tester, const []);
        expect(_table(tester).error, contains('latest failure'));
        expect(find.text('Retry'), findsOneWidget);
        expect(
          harness._listeners.map((listener) => listener.viewId),
          [_libraryId],
        );
        await tester.tap(find.byKey(_refreshKey));
        await tester.pump();
        expect(harness._repository._requests, hasLength(3));
        await harness._succeed(tester, 2, [_person('recovered')]);
        _expectRows(tester, const ['recovered']);
        expect(find.byKey(_errorKey), findsNothing);
      },
    );

    _libraryTest(
      'scope changes clear immediately and reject every old callback, '
      'even for a moved ID',
      (tester, harness) async {
        final original = _person('moved-person', name: 'Old private profile');
        await harness._pump(tester);
        await harness._succeed(tester, 0, [original]);
        final state = tester.state(find.byKey(_libraryKey));
        final oldOpen = _table(tester).onOpen!;
        final oldRow = _row(tester, original.id).onSelectChanged!;
        final oldRefresh = _table(tester).onRefresh!;
        final oldListeners =
            List<_FakeViewListener>.unmodifiable(harness._listeners);
        oldRefresh();
        harness._listener(_libraryId)._notifyChildren();
        expect(harness._repository._requests, hasLength(3));

        await harness._pump(tester, libraryViewId: _otherLibraryId);
        expect(tester.state(find.byKey(_libraryKey)), same(state));
        _expectRows(tester, const []);
        expect(find.text(original.name), findsNothing);
        expect(_table(tester).loading, isTrue);
        expect(_table(tester).error, isNull);
        expect(
          harness._repository._requests.last._parentViewId,
          _otherLibraryId,
        );
        for (final listener in oldListeners) {
          expect(listener._stopCount, 1);
          listener._fireRetainedCallbacks(original);
        }
        oldOpen(original);
        oldRow(true);
        oldRefresh();
        await tester.pump();
        expect(harness._opened, isEmpty);
        expect(harness._repository._requests, hasLength(4));

        final moved = _person(
          original.id,
          name: 'Current profile in another library',
          parentViewId: _otherLibraryId,
          input: _birthInput(utc: DateTime.utc(2002, 6, 7)),
        );
        await harness._succeed(tester, 3, [moved]);
        await harness
            ._succeed(tester, 1, [_person('stale-old-library-result')]);
        await harness._fail(tester, 2, 'old-library failure');
        _expectRows(tester, [moved.id]);
        expect(_table(tester).people.single, same(moved));
        expect(_table(tester).error, isNull);
        oldOpen(original);
        oldRefresh();
        for (final listener in oldListeners) {
          listener._fireRetainedCallbacks(original);
        }
        expect(harness._opened, isEmpty);
        expect(harness._repository._requests, hasLength(4));
        expect(harness._listeners, hasLength(4));

        await tester.tap(_cellFinder(moved.id, 'name'));
        expect(harness._opened, [same(moved)]);
        // Keep the real DataRow callback, not only the table's scope-bound
        // onOpen. Reading State.widget.onOpen at invocation can bypass scope.
        oldRow(true);
        expect(
          harness._opened,
          [same(moved)],
          reason: 'A queued row action from the previous library must not open '
              'a same-ID record in the new library.',
        );
      },
    );

    _libraryTest(
      'disabling retires listeners and ignores pending data, errors '
      'and callbacks',
      (tester, harness) async {
        final original = _person('person');
        await harness._pump(tester);
        await harness._succeed(tester, 0, [original]);
        final oldOpen = _table(tester).onOpen!;
        final oldRow = _row(tester, original.id).onSelectChanged!;
        final oldRefresh = _table(tester).onRefresh!;
        final oldListeners =
            List<_FakeViewListener>.unmodifiable(harness._listeners);
        oldRefresh();
        harness._listener(_libraryId)._notifyChildren();

        await harness._pump(tester, enabled: false);
        _expectEmptyPreview(tester);
        for (final listener in oldListeners) {
          expect(listener._stopCount, 1);
          listener._fireRetainedCallbacks(original);
        }
        oldOpen(original);
        oldRow(true);
        oldRefresh();
        await harness._fail(tester, 2, 'disabled failure');
        await harness._succeed(tester, 1, [_person('disabled result')]);
        _expectEmptyPreview(tester);
        expect(harness._repository._requests, hasLength(3));
        expect(harness._listeners, hasLength(2));
        expect(harness._opened, isEmpty);

        // Re-enabling creates a fresh scope, rather than reviving stopped
        // listeners or accepting their previously captured closures.
        await harness._pump(tester);
        final fresh = _person(original.id, name: 'Re-enabled profile');
        await harness._succeed(tester, 3, [fresh]);
        oldOpen(original);
        oldRefresh();
        for (final listener in oldListeners) {
          listener._fireRetainedCallbacks(original);
        }
        expect(harness._opened, isEmpty);
        expect(harness._repository._requests, hasLength(4));
        expect(harness._listeners, hasLength(4));
        expect(harness._listener(original.id), isNot(same(oldListeners.last)));
        _expectRows(tester, const ['person']);
      },
    );

    _libraryTest(
      'unmounting stops each listener once and makes pending work harmless',
      (tester, harness) async {
        final original = _person('person');
        await harness._pump(tester);
        await harness._succeed(tester, 0, [original]);
        final oldOpen = _table(tester).onOpen!;
        final oldRow = _row(tester, original.id).onSelectChanged!;
        final oldRefresh = _table(tester).onRefresh!;
        oldRefresh();
        harness._listener(_libraryId)._notifyChildren();
        expect(harness._repository._requests, hasLength(3));

        await _unmount(tester);
        for (final listener in harness._listeners) {
          expect(listener._stopCount, 1);
          listener._fireRetainedCallbacks(original);
        }
        oldOpen(original);
        oldRow(true);
        oldRefresh();
        await harness._succeed(tester, 1, [_person('late result')]);
        await harness._fail(tester, 2, 'late failure');
        await tester.pump(const Duration(minutes: 2));

        expect(find.byType(AstrologyHoroscopeLibrary), findsNothing);
        expect(find.byType(DataTable), findsNothing);
        expect(harness._repository._requests, hasLength(3));
        expect(harness._listeners, hasLength(2));
        expect(harness._opened, isEmpty);
      },
    );

    _libraryTest(
      'same-ID replacements open the fresh ViewPB through old and current rows',
      (tester, harness) async {
        final original = _person('person', name: 'Old profile');
        await harness._pump(tester);
        await harness._succeed(tester, 0, [original]);
        final oldOpen = _table(tester).onOpen!;
        final oldRow = _row(tester, original.id).onSelectChanged!;
        oldRow(true);
        expect(harness._opened, [same(original)]);

        final updated = _person(
          original.id,
          name: 'Fresh profile',
          input: _birthInput(
            utc: DateTime.utc(2003, 4, 5, 6, 7, 8),
            place: _newBirthplace,
            offsetMinutes: 0,
          ),
        );
        harness._listener(original.id)._onViewUpdated!(updated);
        await harness._succeed(tester, 1, [updated]);
        expect(identical(original, updated), isFalse);
        expect(
          original.name,
          'Old profile',
          reason: 'Fixtures are not mutated.',
        );
        expect(_cellText(tester, updated.id, 'date'), '2003-04-05');
        oldOpen(original);
        oldRow(true);
        await tester.tap(_cellFinder(updated.id, 'name'));
        expect(
          harness._opened,
          [same(original), same(updated), same(updated), same(updated)],
        );
        expect(
          astrologyInputFromDashboard(harness._opened.last.dashboard!.document)
              .toJson(),
          astrologyInputFromDashboard(updated.dashboard!.document).toJson(),
        );
        expect(harness._repository._requests, hasLength(2));
      },
    );
  });

  group('registered library definition and dashboard models', () {
    for (final individual in const [false, true]) {
      testWidgets(
        'a manually inserted library widget stays absent on a '
        '${individual ? 'person' : 'blank'} dashboard while runtime is active',
        (tester) async {
          final original = individual
              ? buildAstrologyDashboard(library: false, input: _birthInput())
              : DashboardDocument.blank();
          expect(isAstrologyLibrary(original), isFalse);
          expect(
            original.allWidgets
                .where((spec) => spec.type == astrologyLibraryWidgetType),
            isEmpty,
          );
          final document = original.addWidget(_manualLibrarySpec);
          await _withDefinition(tester, document, (controller) async {
            expect(AstrologyRuntime.active.value, isTrue);
            expect(
              controller.document.widgetById(_manualLibrarySpec.id),
              isNotNull,
            );
            expect(find.byType(AstrologyHoroscopeLibrary), findsNothing);
            expect(find.byType(AstrologyHoroscopeTable), findsNothing);
            expect(find.byType(DataTable), findsNothing);

            controller.select(_manualLibrarySpec.id);
            controller.refresh();
            await tester.pump();
            AstrologyRuntime.active.value = false;
            await tester.pump();
            AstrologyRuntime.active.value = true;
            await tester.pump(const Duration(minutes: 2));
            expect(find.byType(AstrologyHoroscopeLibrary), findsNothing);
            expect(find.byType(DataTable), findsNothing);
            expect(controller.canUndo, isFalse);
            expect(controller.document, same(document));
          });
        },
      );
    }

    testWidgets(
      'the real library preview renders headers with no IO or interactive rows',
      (tester) async {
        await _withDefinition(
          tester,
          buildAstrologyDashboard(),
          (controller) async {
            final widget = tester.widget<AstrologyHoroscopeLibrary>(
              find.byType(AstrologyHoroscopeLibrary),
            );
            expect(AstrologyRuntime.active.value, isTrue);
            expect(widget.enabled, isTrue);
            expect(widget.libraryViewId, isEmpty);
            expect(widget.service, isNull, reason: 'Keep production defaults.');
            expect(widget.listenerFactory, isNull);
            _expectEmptyPreview(tester);
            await tester.tap(find.byKey(_refreshKey));
            controller.refresh();
            await tester.pump(const Duration(minutes: 2));
            _expectEmptyPreview(tester);
            expect(
              tester
                  .widget<AstrologyHoroscopeLibrary>(
                    find.byType(AstrologyHoroscopeLibrary),
                  )
                  .refreshToken,
              controller.refreshToken,
            );
            expect(controller.canUndo, isFalse);
          },
        );
      },
    );

    test(
      'root layout puts the full-width five-row library directly below birth',
      () {
        final document = buildAstrologyDashboard();
        final widgets = document.allWidgets.toList(growable: false);
        expect(isAstrologyLibrary(document), isTrue);
        expect(
          widgets.where((spec) => spec.type == astrologyLibraryWidgetType),
          hasLength(1),
        );
        expect(
          widgets.take(4).map(_layout),
          const [
            (astrologyInputWidgetType, 0, 0, 12, 7),
            (astrologyLibraryWidgetType, 0, 7, 12, 5),
            (astrologyChartWidgetType, 0, 12, 6, 7),
            (astrologyChartWidgetType, 6, 12, 6, 7),
          ],
        );
        final birth = widgets.first.placement;
        final library = widgets[1].placement;
        expect(library.row, birth.row + birth.rowSpan);
        expect(widgets[2].placement.row, library.row + library.rowSpan);
        expect(
          widgets.skip(2).every((spec) => spec.placement.row >= 12),
          isTrue,
        );
        final definition = _libraryDefinition();
        expect(definition.defaultColumnSpan, 12);
        expect(definition.defaultRowSpan, 5);
        expect(definition.requiresScrollActivation, isTrue);
        expect(definition.label(), 'Saved horoscopes');
      },
    );

    test('person layout has no library and retains charts at row seven', () {
      final document = buildAstrologyDashboard(
        library: false,
        libraryId: _libraryId,
        eventsViewId: 'person-events',
        input: _birthInput(),
      );
      expect(isAstrologyLibrary(document), isFalse);
      expect(
        document.allWidgets
            .where((spec) => spec.type == astrologyLibraryWidgetType),
        isEmpty,
      );
      expect(
        document.allWidgets.map(_layout),
        const [
          (astrologyInputWidgetType, 0, 0, 12, 7),
          (astrologyChartWidgetType, 0, 7, 6, 7),
          (astrologyChartWidgetType, 6, 7, 6, 7),
          (astrologyPanchangaWidgetType, 0, 14, 6, 7),
          (astrologyChartWidgetType, 6, 14, 6, 7),
          (astrologyPlacementsWidgetType, 0, 21, 12, 7),
          (astrologyShadbalaWidgetType, 0, 28, 6, 8),
          (astrologyDashaWidgetType, 6, 28, 6, 8),
          (astrologyAshtakavargaWidgetType, 0, 36, 12, 8),
          (astrologyEventsWidgetType, 0, 44, 12, 8),
        ],
      );
      expect(astrologyEventsViewId(document), 'person-events');
    });

    testWidgets(
      'the registered onOpen delegates to the existing TabsBloc.openPlugin',
      (tester) async {
        final tabs = _FakeTabsBloc();
        final person = _person('navigation-target');
        await _withDefinition(
          tester,
          buildAstrologyDashboard(),
          (controller) async {
            final widget = tester.widget<AstrologyHoroscopeLibrary>(
              find.byType(AstrologyHoroscopeLibrary),
            );
            expect(tabs._opened, isEmpty);
            // Inspect the actual registered mapping in a backend-free preview.
            // Live row taps and current-PB identity are exercised above.
            final mappedOpen = widget.onOpen;
            mappedOpen(person);
            expect(tabs._opened, [same(person)]);
            expect(tabs._arguments.single, isEmpty);
            expect(tabs._setLatest, [true]);
            expect(controller.canUndo, isFalse);

            await _unmount(tester);
            mappedOpen(person);
            expect(tabs._opened, [same(person)]);
          },
          tabs: tabs,
        );
      },
    );
  });
}

// Every live instance uses the real service over a repository fake. No Rust
// initialization, extension activation, native notification stream or backend
// singleton is needed. Resolve every outstanding request after unmount even
// when an assertion fails, before flutter_test checks for leaked work.
void _libraryTest(
  String name,
  Future<void> Function(WidgetTester tester, _LibraryHarness harness) body,
) {
  testWidgets(name, (tester) async {
    final harness = _LibraryHarness();
    try {
      await body(tester, harness);
      _expectClean(tester);
    } finally {
      await _unmount(tester);
      for (final request in harness._repository._requests) {
        if (!request._completer.isCompleted) request._succeed(const []);
      }
      await tester.pump();
    }
    expect(
      harness._repository._readViewIds,
      isEmpty,
      reason: 'No per-person IO.',
    );
    expect(
      harness._repository._writes,
      isEmpty,
      reason: 'The index is read-only.',
    );
    for (final listener in harness._listeners) {
      expect(listener._startCount, 1, reason: listener.viewId);
      expect(listener._stopCount, 1, reason: listener.viewId);
    }
    _expectClean(tester);
  });
}

class _LibraryHarness {
  final _repository = _FakeAstrologyDashboardRepository();
  late final _service = AstrologyDashboardService(repository: _repository);
  final _listeners = <_FakeViewListener>[];
  final _opened = <ViewPB>[];
  // Keep the factory identity stable across pumpWidget calls: a newly created
  // closure would cause a rebind, masking refreshToken/rebuild regressions.
  late final ViewListener Function(String) _listenerFactory = _newListener;

  ViewListener _newListener(String viewId) {
    final listener = _FakeViewListener(viewId: viewId);
    _listeners.add(listener);
    return listener;
  }

  _FakeViewListener _listener(String viewId) =>
      _listeners.lastWhere((listener) => listener.viewId == viewId);

  AstrologyHoroscopeLibrary _widget({
    String libraryViewId = _libraryId,
    bool enabled = true,
    int refreshToken = 0,
    ValueChanged<ViewPB>? onOpen,
  }) =>
      AstrologyHoroscopeLibrary(
        key: _libraryKey,
        libraryViewId: libraryViewId,
        enabled: enabled,
        refreshToken: refreshToken,
        onOpen: onOpen ?? _opened.add,
        service: _service,
        listenerFactory: _listenerFactory,
      );

  Future<void> _pump(
    WidgetTester tester, {
    String libraryViewId = _libraryId,
    bool enabled = true,
    int refreshToken = 0,
    ValueChanged<ViewPB>? onOpen,
  }) =>
      tester.pumpWidget(
        _app(
          _widget(
            libraryViewId: libraryViewId,
            enabled: enabled,
            refreshToken: refreshToken,
            onOpen: onOpen,
          ),
        ),
      );

  Future<void> _succeed(
    WidgetTester tester,
    int requestIndex,
    Iterable<ViewPB> children,
  ) async {
    _repository._requests[requestIndex]._succeed(children);
    await tester.pump();
  }

  Future<void> _fail(
    WidgetTester tester,
    int requestIndex,
    String message,
  ) async {
    _repository._requests[requestIndex]._completer
        .completeError(StateError(message));
    await tester.pump();
  }
}

class _PendingChildViews {
  _PendingChildViews(this._parentViewId);

  final String _parentViewId;
  final _completer = Completer<List<ViewPB>>();

  void _succeed(Iterable<ViewPB> children) =>
      _completer.complete(List<ViewPB>.unmodifiable(children));
}

class _FakeAstrologyDashboardRepository
    implements AstrologyDashboardRepository {
  final _requests = <_PendingChildViews>[];
  final _readViewIds = <String>[];
  final _writes = <String>[];

  @override
  Future<List<ViewPB>> childViews(String parentViewId) {
    final request = _PendingChildViews(parentViewId);
    _requests.add(request);
    return request._completer.future;
  }

  @override
  Future<ViewPB> readView(String viewId) {
    _readViewIds.add(viewId);
    throw StateError('Unexpected per-person read: $viewId');
  }

  Never _rejectWrite(String operation) {
    _writes.add(operation);
    throw StateError('The horoscope index must not write: $operation');
  }

  @override
  Future<ViewPB> createView({
    required String parentViewId,
    required String name,
    required ViewLayoutPB layoutType,
  }) =>
      _rejectWrite('create:$parentViewId');

  @override
  Future<ViewPB> updateView({
    required String viewId,
    required String name,
    required String extra,
  }) =>
      _rejectWrite('update:$viewId');

  @override
  Future<void> deleteView(String viewId) => _rejectWrite('delete:$viewId');

  @override
  Future<void> buildEvents(String viewId) =>
      _rejectWrite('buildEvents:$viewId');
}

class _FakeViewListener extends ViewListener {
  _FakeViewListener({required super.viewId});

  int _startCount = 0;
  int _stopCount = 0;
  void Function(UpdateViewNotifiedValue)? _onViewUpdated;
  void Function(ChildViewUpdatePB)? _onViewChildViewsUpdated;
  void Function(DeleteViewNotifyValue)? _onViewDeleted;
  void Function(RestoreViewNotifiedValue)? _onViewRestored;
  void Function(MoveToTrashNotifiedValue)? _onViewMoveToTrash;

  @override
  void start({
    void Function(UpdateViewNotifiedValue)? onViewUpdated,
    void Function(ChildViewUpdatePB)? onViewChildViewsUpdated,
    void Function(DeleteViewNotifyValue)? onViewDeleted,
    void Function(RestoreViewNotifiedValue)? onViewRestored,
    void Function(MoveToTrashNotifiedValue)? onViewMoveToTrash,
  }) {
    _startCount++;
    _onViewUpdated = onViewUpdated;
    _onViewChildViewsUpdated = onViewChildViewsUpdated;
    _onViewDeleted = onViewDeleted;
    _onViewRestored = onViewRestored;
    _onViewMoveToTrash = onViewMoveToTrash;
  }

  @override
  Future<void> stop() async {
    _stopCount++;
    // Deliberately retain callbacks to simulate notifications already queued
    // when stop was called. Never invoke the Rust-backed superclass methods.
  }

  void _notifyChildren() => _onViewChildViewsUpdated!(
        ChildViewUpdatePB(parentViewId: viewId)..freeze(),
      );

  void _fireRetainedCallbacks(ViewPB person) {
    _onViewUpdated?.call(person);
    _onViewChildViewsUpdated?.call(
      ChildViewUpdatePB(parentViewId: viewId)..freeze(),
    );
    _onViewDeleted?.call(FlowyResult.success(person));
    _onViewRestored?.call(FlowyResult.success(person));
    _onViewMoveToTrash?.call(
      FlowyResult.success(DeletedViewPB(viewId: person.id)..freeze()),
    );
  }
}

// Implement, rather than construct/extend, the real bloc so no plugin lookup,
// menu service, event dispatch or native backend is reached by navigation.
class _FakeTabsBloc extends Fake implements TabsBloc {
  final _opened = <ViewPB>[];
  final _arguments = <Map<String, dynamic>>[];
  final _setLatest = <bool>[];

  @override
  void openPlugin(
    ViewPB view, {
    Map<String, dynamic> arguments = const {},
    bool setLatest = true,
  }) {
    _opened.add(view);
    _arguments.add(Map<String, dynamic>.unmodifiable(arguments));
    _setLatest.add(setLatest);
  }
}

DashboardWidgetDefinition _libraryDefinition() => astrologyDashboardWidgets()
    .singleWhere((definition) => definition.type == astrologyLibraryWidgetType);

Future<void> _withDefinition(
  WidgetTester tester,
  DashboardDocument document,
  Future<void> Function(DashboardController controller) body, {
  _FakeTabsBloc? tabs,
}) async {
  final wasActive = AstrologyRuntime.active.value;
  final definition = _libraryDefinition();
  final spec = document.allWidgets.singleWhere(
    (spec) => spec.type == astrologyLibraryWidgetType,
  );
  // Assemble documents BEFORE constructing the controller. No edit/replace
  // means no persistence timer; the empty ID also guards accidental IO when
  // exercising the real builder with its production service/listener defaults.
  final controller = DashboardController(viewId: '', document: document);
  AstrologyRuntime.active.value = true;
  try {
    final content = Builder(
      builder: (context) => definition.builder(
        DashboardWidgetContext(
          context: context,
          controller: controller,
          spec: spec,
          palette: DashboardPalette.of(context),
        ),
      ),
    );
    await tester.pumpWidget(
      _app(
        tabs == null
            ? content
            : Provider<TabsBloc>.value(value: tabs, child: content),
      ),
    );
    expect(controller.viewId, isEmpty);
    expect(controller.document.settings.refreshSeconds, 0);
    await body(controller);
    expect(controller.document, same(document));
    expect(controller.canUndo, isFalse);
    _expectClean(tester);
  } finally {
    await _unmount(tester);
    controller.dispose();
    AstrologyRuntime.active.value = wasActive;
  }
}

AstrologyInput _birthInput({
  DateTime? utc,
  AstrologyPlace place = _birthplace,
  int offsetMinutes = 330,
}) =>
    AstrologyInput(
      name: 'Name stored in birth profile',
      utc: utc ?? DateTime.utc(1990, 5, 15, 9, 20, 30),
      place: place,
      utcOffsetMinutes: offsetMinutes,
    );

ViewPB _person(
  String id, {
  String? name,
  AstrologyInput? input,
  String parentViewId = _libraryId,
}) =>
    _dashboardView(
      id,
      name: name,
      parentViewId: parentViewId,
      document: buildAstrologyDashboard(
        input: input ?? _birthInput(),
        library: false,
        libraryId: parentViewId,
        eventsViewId: '$id-events',
      ),
    );

ViewPB _dashboardView(
  String id, {
  required DashboardDocument document,
  String? name,
  String parentViewId = _libraryId,
  ViewLayoutPB layout = ViewLayoutPB.Document,
}) =>
    ViewPB(
      id: id,
      name: name ?? id,
      parentViewId: parentViewId,
      layout: layout,
      extra: DashboardMetadata(document: document).mergeIntoExtra(''),
    )..freeze();

(String, int, int, int, int) _layout(DashboardWidgetSpec spec) => (
      spec.type,
      spec.placement.column,
      spec.placement.row,
      spec.placement.columnSpan,
      spec.placement.rowSpan,
    );

Widget _app(Widget child) => MaterialApp(
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Center(child: SizedBox(width: 760, height: 500, child: child)),
      ),
    );

AstrologyHoroscopeTable _table(WidgetTester tester) => tester
    .widget<AstrologyHoroscopeTable>(find.byType(AstrologyHoroscopeTable));

DataTable _dataTable(WidgetTester tester) =>
    tester.widget<DataTable>(find.byKey(_tableKey));

DataRow _row(WidgetTester tester, String id) => _dataTable(tester)
    .rows
    .singleWhere((row) => row.key == ValueKey('astrology-horoscope-$id'));

TextButton _refreshButton(WidgetTester tester) =>
    tester.widget<TextButton>(find.byKey(_refreshKey));

Finder _cellFinder(String id, String field) =>
    find.byKey(ValueKey('astrology-horoscope-$id-$field'));

String? _cellText(WidgetTester tester, String id, String field) =>
    tester.widget<Text>(_cellFinder(id, field)).data;

void _expectRows(WidgetTester tester, List<String> ids) {
  expect(_table(tester).people.map((person) => person.id), ids);
  expect(
    _dataTable(tester).rows.map((row) => row.key),
    ids.map((id) => ValueKey('astrology-horoscope-$id')),
  );
  expect(
    find.text(
      '${ids.length} saved ${ids.length == 1 ? 'horoscope' : 'horoscopes'}',
    ),
    findsOneWidget,
  );
}

void _expectHeaders(WidgetTester tester) {
  expect(_dataTable(tester).columns, hasLength(4));
  expect(_dataTable(tester).showCheckboxColumn, isFalse);
  for (final heading in const [
    'Name',
    'Date of birth',
    'Time of birth',
    'Place of birth',
  ]) {
    expect(
      find.descendant(of: find.byKey(_tableKey), matching: find.text(heading)),
      findsOneWidget,
    );
  }
}

void _expectEmptyPreview(WidgetTester tester) {
  _expectHeaders(tester);
  _expectRows(tester, const []);
  expect(_table(tester).loading, isFalse);
  expect(_table(tester).error, isNull);
  expect(_table(tester).onOpen, isNull);
  expect(_table(tester).onRefresh, isNull);
  expect(_refreshButton(tester).onPressed, isNull);
  expect(find.byKey(_errorKey), findsNothing);
}

void _expectClean(WidgetTester tester) {
  expect(find.byType(ErrorWidget), findsNothing);
  expect(
    tester.takeException(),
    isNull,
    reason: 'No framework or native IO error.',
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
