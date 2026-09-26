import 'dart:async';

import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

const _note = DashboardWidgetSpec(
  id: 'access-note',
  type: 'text',
  placement: DashboardPlacement(columnSpan: 12),
  settings: {'text': 'Saved words'},
);
const _document = DashboardDocument(
  subtitle: 'Saved description',
  sections: [
    DashboardSection(id: 'access-section', widgets: [_note]),
  ],
  variables: [
    DashboardVariable(
      key: 'kept',
      label: 'Kept',
      kind: DashboardVariableKind.text,
      defaultValue: 'initial',
    ),
    DashboardVariable(
      key: 'removed',
      label: 'Removed',
      kind: DashboardVariableKind.toggle,
    ),
  ],
);

void main() {
  group('dashboard access is session state, not document data', () {
    test('locking clears editing affordances without changing content', () {
      final controller = _controller(mode: DashboardMode.focus);
      controller.configure(_note.id);
      controller.setMode(DashboardMode.focus);
      controller.openModal(_note.id);
      controller.setValue('kept', 'a session choice');
      final state = controller.state;
      final saved = DashboardMetadata(document: controller.document)
          .mergeIntoExtra('{"other_metadata":true}');
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.isReadOnly, isFalse);
      expect(controller.isEditable, isTrue);
      expect(controller.selectedWidgetId, _note.id);
      expect(controller.configuringWidgetId, _note.id);

      final timers = _timersDuring(() => controller.setReadOnly(true));

      expect(controller.isReadOnly, isTrue);
      expect(controller.isEditable, isFalse);
      expect(controller.selectedWidgetId, isNull);
      expect(controller.configuringWidgetId, isNull);
      expect(controller.modalWidgetId, _note.id);
      expect(controller.mode, DashboardMode.focus);
      expect(controller.document, same(_document));
      expect(controller.state, same(state));
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      expect(notifications, 1);
      expect(timers, isEmpty);
      expect(
        DashboardMetadata(document: controller.document)
            .mergeIntoExtra('{"other_metadata":true}'),
        saved,
        reason: 'Access must never become persisted dashboard metadata.',
      );

      controller.setReadOnly(true);
      expect(notifications, 1, reason: 'Adopting identical access is a no-op.');
      controller.setReadOnly(false);
      expect(notifications, 2);
      expect(controller.isEditable, isTrue);
      expect(controller.selectedWidgetId, isNull);
      expect(controller.configuringWidgetId, isNull);
      expect(controller.modalWidgetId, _note.id);
      controller.setReadOnly(false);
      expect(notifications, 2);
    });

    test('notify false adopts both transitions before a page builds', () {
      final controller = _controller();
      controller.configure(_note.id);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setReadOnly(true, notify: false);
      expect(controller.isReadOnly, isTrue);
      expect(controller.isEditable, isFalse);
      expect(controller.selectedWidgetId, isNull);
      expect(controller.configuringWidgetId, isNull);
      expect(notifications, 0);

      // A later identical call must not emit a deferred notification either.
      controller.setReadOnly(true);
      expect(notifications, 0);
      controller.setReadOnly(false, notify: false);
      expect(controller.isReadOnly, isFalse);
      expect(controller.isEditable, isTrue);
      expect(notifications, 0);
      controller.configure(_note.id);
      expect(controller.configuringWidgetId, _note.id);
      expect(notifications, 1);
    });

    for (final mode in DashboardMode.values) {
      test('${mode.name}: access and presentation independently gate editing',
          () {
        final controller = _controller(mode: mode);
        expect(controller.isEditable, mode != DashboardMode.presentation);

        controller.setReadOnly(true);
        expect(controller.isEditable, isFalse);
        expect(controller.mode, mode);
        controller.setReadOnly(false);
        expect(controller.mode, mode);
        expect(controller.isEditable, mode != DashboardMode.presentation);

        controller.setReadOnly(true);
        for (final next in DashboardMode.values) {
          controller.setMode(next);
          expect(controller.isReadOnly, isTrue);
          expect(controller.isEditable, isFalse);
        }
      });
    }

    test('read-only still permits transient reading controls without a write',
        () {
      final controller = _controller()..setReadOnly(true);
      final timers = _timersDuring(() {
        controller.setValue('kept', 'filter text');
        controller.toggleValue('removed');
        controller.refresh();
        controller.openModal(_note.id);
      });
      expect(controller.state.text('kept'), 'filter text');
      expect(controller.state.flag('removed'), isTrue);
      expect(controller.refreshToken, 1);
      expect(controller.modalWidgetId, _note.id);
      expect(controller.document, same(_document));
      expect(controller.canUndo, isFalse);
      expect(timers, isEmpty);

      expect(
        _timersDuring(() {
          controller.resetState();
          controller.openModal(null);
        }),
        isEmpty,
      );
      expect(
        controller.state,
        DashboardStateValues.initial(_document.variables),
      );
      expect(controller.modalWidgetId, isNull);
      expect(controller.isReadOnly, isTrue);
    });
  });

  group('read-only document mutation guards', () {
    test(
        'edit, replace, undo, redo and configure neither mutate nor queue writes',
        () async {
      final controller = _controller();
      controller.edit((document) => document.copyWith(subtitle: 'First edit'));
      controller.edit((document) => document.copyWith(subtitle: 'Second edit'));
      controller.undo();
      await controller.flush();
      controller.setMode(DashboardMode.focus);
      controller.setReadOnly(true);
      final before = controller.document;
      final state = controller.state;
      var notifications = 0;
      var changeCalls = 0;
      controller.addListener(() => notifications++);
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isTrue);

      final timers = _timersDuring(() {
        for (final transient in [false, true]) {
          controller.edit(
            (document) {
              changeCalls++;
              return document.withoutWidget(_note.id);
            },
            transient: transient,
          );
        }
        controller.replace(const DashboardDocument());
        controller.replace(const DashboardDocument(), remember: false);
        controller.undo();
        controller.redo();
        controller.configure(_note.id);
      });

      expect(
        changeCalls,
        0,
        reason: 'Reject before invoking a change callback.',
      );
      expect(controller.document, same(before));
      expect(controller.state, same(state));
      expect(controller.mode, DashboardMode.focus);
      expect(controller.selectedWidgetId, isNull);
      expect(controller.configuringWidgetId, isNull);
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isTrue);
      expect(notifications, 0);
      expect(
        timers,
        isEmpty,
        reason: 'A refused edit must not debounce a write.',
      );
      await controller.flush();
      expect(controller.document, same(before));
      expect(notifications, 0);
    });

    test('unlock restores both existing history branches, not a new checkpoint',
        () async {
      final controller = _controller();
      final first = _document.copyWith(subtitle: 'First edit');
      final second = _document.copyWith(subtitle: 'Second edit');
      controller.replace(first);
      controller.replace(second);
      controller.undo();
      await controller.flush();

      controller.setReadOnly(true);
      controller.undo();
      controller.redo();
      controller.replace(const DashboardDocument());
      expect(controller.document, same(first));
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isTrue);

      controller.setReadOnly(false);
      controller.redo();
      expect(controller.document, same(second));
      expect(controller.canRedo, isFalse);
      controller.undo();
      expect(controller.document, same(first));
      controller.undo();
      expect(controller.document, same(_document));
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.document, same(first));
      controller.redo();
      expect(controller.document, same(second));

      controller.configure(_note.id);
      controller.edit(
        (document) =>
            document.withWidget(_note.withSettings({'text': 'Allowed'})),
      );
      expect(controller.configuringWidgetId, _note.id);
      expect(
        controller.document.widgetById(_note.id)!.setting('text'),
        'Allowed',
      );
      controller.undo();
      expect(controller.document, same(second));
    });

    test(
        'locking during transient changes blocks the next frame, keeps one undo',
        () {
      final controller = _controller();
      controller.edit((document) => document.copyWith(subtitle: 'Before drag'));
      for (final row in [1, 2, 3]) {
        controller.edit(
          (document) => document.withWidget(
            _note.copyWith(placement: _note.placement.copyWith(row: row)),
          ),
          transient: true,
        );
      }
      final landed = controller.document;
      controller.setReadOnly(true);
      var called = false;
      expect(
        _timersDuring(() {
          controller.edit(
            (document) {
              called = true;
              return document.withoutWidget(_note.id);
            },
            transient: true,
          );
        }),
        isEmpty,
      );
      expect(called, isFalse);
      expect(controller.document, same(landed));
      expect(controller.document.widgetById(_note.id)!.placement.row, 3);
      controller.setReadOnly(false);
      controller.undo();
      expect(controller.document, same(_document));
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.document, same(landed));
      expect(controller.canRedo, isFalse);
    });
  });

  group('remote adoption while read-only', () {
    test('clean remote documents still arrive and reconcile session variables',
        () {
      final controller = _controller()..setValue('kept', 'local selection');
      controller.setValue('removed', true);
      controller.setReadOnly(true);
      final incoming = _document.copyWith(
        subtitle: 'Remote description',
        variables: const [
          DashboardVariable(
            key: 'kept',
            label: 'Renamed remotely',
            kind: DashboardVariableKind.text,
            defaultValue: 'remote default',
          ),
          DashboardVariable(
            key: 'added',
            label: 'Added remotely',
            kind: DashboardVariableKind.number,
            defaultValue: 23,
          ),
        ],
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(
        _timersDuring(() => controller.adoptFromView(_view(incoming))),
        isEmpty,
      );
      expect(controller.document, incoming);
      expect(controller.state.text('kept'), 'local selection');
      expect(controller.state['removed'], isNull);
      expect(controller.state['added'], 23);
      expect(controller.isReadOnly, isTrue);
      expect(controller.isEditable, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
      expect(notifications, 1);

      controller.adoptFromView(_view(incoming));
      expect(notifications, 1, reason: 'An identical echo does not notify.');
      final newer = incoming.copyWith(subtitle: 'Another remote change');
      controller.adoptFromView(_view(newer));
      expect(controller.document, newer);
      expect(
        notifications,
        2,
        reason: 'Adoption must not mark the page dirty.',
      );
    });

    test('foreign and non-dashboard views cannot replace a read-only document',
        () {
      final controller = _controller()..setReadOnly(true);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final timers = _timersDuring(() {
        controller.adoptFromView(
          _view(_document.copyWith(subtitle: 'Other page'))
            ..id = 'another-view',
        );
        controller.adoptFromView(ViewPB(extra: '{"other_metadata":true}'));
      });
      expect(controller.document, same(_document));
      expect(controller.isReadOnly, isTrue);
      expect(notifications, 0);
      expect(timers, isEmpty);
    });

    test('locking does not let a stale echo overwrite an already accepted edit',
        () async {
      final controller = _controller();
      final local = _document.copyWith(subtitle: 'Accepted before locking');
      final remote = _document.copyWith(subtitle: 'Remote after flush');
      controller.replace(local);
      controller.setReadOnly(true);
      controller.adoptFromView(_view(remote));
      expect(controller.document, same(local));

      // Empty viewId exercises the real no-backend flush, not a mock write.
      await controller.flush();
      controller.adoptFromView(_view(remote));
      expect(controller.document, remote);
      expect(controller.isReadOnly, isTrue);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(controller.document, remote);

      controller.setReadOnly(false);
      controller.undo();
      expect(controller.document, same(_document));
      controller.redo();
      expect(controller.document, remote);
    });
  });
}

DashboardController _controller({DashboardMode? mode}) {
  final controller = DashboardController(
    viewId: '',
    document: _document,
    mode: mode,
    persistDebounce: const Duration(days: 1),
  );
  // These are plain tests, not widget tests with a pre-teardown timer check.
  addTearDown(controller.dispose);
  return controller;
}

ViewPB _view(DashboardDocument document) => ViewPB.fromBuffer(
      ViewPB(
        layout: ViewLayoutPB.Document,
        extra: DashboardMetadata(document: document).mergeIntoExtra(''),
      ).writeToBuffer(),
    );

/// Observe the production debounce without replacing the controller, calling
/// native dispatch, waiting on a real timer, or adding a fake_async dependency.
List<Duration> _timersDuring(void Function() action) {
  final timers = <Duration>[];
  runZoned<void>(
    action,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        timers.add(duration);
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );
  return timers;
}
