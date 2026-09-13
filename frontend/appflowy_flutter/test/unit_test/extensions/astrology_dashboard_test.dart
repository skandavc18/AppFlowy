import 'dart:async';
import 'dart:convert';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_service.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

const _libraryId = 'astrology-library';
const _place = AstrologyPlace(
  name: 'Bengaluru',
  latitude: 12.98,
  longitude: 77.58,
  timeZone: 'Asia/Kolkata',
);

AstrologyInput _input([String name = 'First person']) => AstrologyInput(
      name: name,
      utc: DateTime.utc(1990, 5, 15, 9, 20),
      place: _place,
      utcOffsetMinutes: 330,
      style: IndianChartStyle.south,
      ayanamsa: AstrologyAyanamsa.raman,
      trueNode: true,
      dashaYearDays: 360,
    );

DashboardWidgetSpec _card(DashboardDocument document, String type) =>
    document.allWidgets.firstWhere((widget) => widget.type == type);

void main() {
  group('Astrology dashboard model', () {
    test('the public widget and draft keys are stable', () {
      expect(
        [
          astrologyInputWidgetType,
          astrologyChartWidgetType,
          astrologyDashaWidgetType,
          astrologyShadbalaWidgetType,
          astrologyAshtakavargaWidgetType,
          astrologyPlacementsWidgetType,
          astrologyPanchangaWidgetType,
          astrologyLibraryWidgetType,
          astrologyEventsWidgetType,
          astrologyDraftKey,
        ],
        [
          'ext.astrology.input',
          'ext.astrology.chart',
          'ext.astrology.dasha',
          'ext.astrology.shadbala',
          'ext.astrology.ashtakavarga',
          'ext.astrology.placements',
          'ext.astrology.panchanga',
          'ext.astrology.library',
          'ext.astrology.events',
          'astrology_input_draft',
        ],
      );
    });

    test(
        'one catalogue dashboard requires Astrology but is not extension-owned',
        () {
      final template = astrologyDashboardTemplate();
      expect(template.id, 'vedic_astrology');
      expect(template.label(), 'Astrology dashboard template');
      expect(template.category, TemplateCategory.knowledge);
      expect(template.requires, {'astrology'});
      expect(template.extensionId, isEmpty);
      expect(template.kind, TemplateKind.dashboard);
      expect(template.makesSeveralThings, isFalse);
      expect(template.parts, hasLength(1));
      final part = template.parts.single;
      expect(part.name(), template.label());
      expect(part.blueprint, isA<TemplateDashboard>());
      final document = (part.blueprint as TemplateDashboard).build(const {});
      expect(isAstrologyLibrary(document), isTrue);
      expect(astrologyEventsViewId(document), isEmpty);
      expect(document.allWidgets.every((widget) => !widget.source.isBound),
          isTrue);
      for (final widget in document.allWidgets) {
        expect(template.requires, contains(widget.type.split('.')[1]));
      }
    });

    for (final library in [true, false]) {
      test(
          'the ${library ? 'library' : 'person'} has every requested card in order',
          () {
        final input = _input();
        final document = buildAstrologyDashboard(
          input: input,
          library: library,
          libraryId: _libraryId,
          eventsViewId: 'real-events',
        );
        final widgets = document.allWidgets.toList();
        final row = library ? 12 : 7;
        expect(
          widgets.map(
            (widget) => (
              widget.type,
              widget.placement.column,
              widget.placement.row,
              widget.placement.columnSpan,
              widget.placement.rowSpan,
            ),
          ),
          [
            (astrologyInputWidgetType, 0, 0, 12, 7),
            if (library) (astrologyLibraryWidgetType, 0, 7, 12, 5),
            (astrologyChartWidgetType, 0, row, 6, 7),
            (astrologyChartWidgetType, 6, row, 6, 7),
            (astrologyPanchangaWidgetType, 0, row + 7, 6, 7),
            (astrologyChartWidgetType, 6, row + 7, 6, 7),
            (astrologyPlacementsWidgetType, 0, row + 14, 12, 7),
            (astrologyShadbalaWidgetType, 0, row + 21, 6, 8),
            (astrologyDashaWidgetType, 6, row + 21, 6, 8),
            (astrologyAshtakavargaWidgetType, 0, row + 29, 12, 8),
            (astrologyEventsWidgetType, 0, row + 37, 12, 8),
          ],
        );
        expect(widgets.map((widget) => widget.id).toSet(),
            hasLength(widgets.length));
        expect(document.settings.columns, 0,
            reason: 'Keep responsive columns.');
        expect(document.sections.single.layout, DashboardSectionLayout.free);
        final charts =
            widgets.where((widget) => widget.type == astrologyChartWidgetType);
        expect(charts.map((widget) => widget.integer('division', fallback: 1)),
            [1, 9, 1]);
        expect(charts.map((widget) => widget.flag('transit')),
            [false, false, true]);
        expect(charts.last.settings, {'transit': true});
        expect(
          _card(document, astrologyInputWidgetType).settings,
          {
            'profile': input.toJson(),
            'library': library,
            'library_id': _libraryId
          },
        );
        expect(
          widgets.where((widget) => widget.settings.containsKey('profile')),
          hasLength(1),
        );
        final events = _card(document, astrologyEventsWidgetType);
        expect(events.source.kind, DashboardSourceKind.database);
        expect(events.source.isBound, isTrue);
        expect(astrologyEventsViewId(document), 'real-events');
        _expectNoOverlaps(widgets.map((widget) => widget.placement).toList());

        for (final width in [1400.0, 1000.0, 700.0, 500.0, 320.0]) {
          final columns = dashboardColumnsFor(width);
          final settled = resolveDashboardLayout(
            document.slotsFor(document.sections.single),
            columns: columns,
            compact: false,
          );
          _expectNoOverlaps(settled.map((slot) => slot.placement).toList());
          for (final slot in settled) {
            expect(slot.placement.column, greaterThanOrEqualTo(0));
            expect(slot.placement.endColumn, lessThanOrEqualTo(columns));
            final original = document.widgetById(slot.id)!;
            expect(
              slot.placement.row,
              original.placement.row,
              reason: '${original.title} must not be displaced at $width px.',
            );
          }
          expect(settled.first.placement.columnSpan, columns);
        }
      });
    }

    test('drafts survive layout edits and undo without becoming saved profiles',
        () async {
      final document = buildAstrologyDashboard();
      expect(document.variableFor(astrologyDraftKey)?.initialValue, isNull);
      expect(document.settings.showControlBar, isFalse);
      final controller = DashboardController(
        viewId: '',
        document: document,
        persistDebounce: const Duration(days: 1),
      );
      final draft = _input('Unsaved');
      try {
        controller.setValue(astrologyDraftKey, draft);
        controller
            .edit((current) => current.copyWith(subtitle: 'A layout edit'));
        expect(controller.state[astrologyDraftKey], same(draft));
        controller.undo();
        expect(controller.state[astrologyDraftKey], same(draft));
        controller.redo();
        expect(controller.state[astrologyDraftKey], same(draft));
        expect(astrologyInputFromDashboard(controller.document).utc, isNull);
        expect(jsonEncode(controller.document.toJson()),
            isNot(contains('Unsaved')));
        await controller.flush();
      } finally {
        controller.dispose();
      }
    });

    test('only the first input card changes, wherever it was moved', () {
      final base = _customDocument(
        buildAstrologyDashboard(
          input: _input(),
          library: false,
          libraryId: _libraryId,
          eventsViewId: 'notes-grid',
        ),
      );
      final inputCard = _card(base, astrologyInputWidgetType)
          .withSettings(const {'custom': 'keep this'});
      final withoutInput = base.withoutWidget(inputCard.id);
      final secondInput = inputCard.copyWith(
        id: 'second-input',
        settings: {'profile': _input('Not the shared profile').toJson()},
      );
      final original = withoutInput.copyWith(
        sections: [
          ...withoutInput.sections,
          DashboardSection(
            id: 'moved-input-section',
            title: 'Moved controls',
            collapsed: true,
            showDivider: true,
            widgets: [inputCard, secondInput],
          ),
        ],
      );
      final before = jsonEncode(original.toJson());
      expect(astrologyInputFromDashboard(original).toJson(), _input().toJson());
      final updated = withAstrologyInput(original, _input('Renamed'));
      expect(astrologyInputFromDashboard(updated).name, 'Renamed');
      expect(updated.widgetById(inputCard.id)?.settings['custom'], 'keep this');
      expect(updated.widgetById(secondInput.id), same(secondInput));
      expect(astrologyEventsViewId(updated), 'notes-grid');
      expect(
        updated.toJson(),
        original
            .withWidget(
              inputCard.withSettings({'profile': _input('Renamed').toJson()}),
            )
            .toJson(),
      );
      expect(jsonEncode(original.toJson()), before, reason: 'No mutation.');
    });

    test('library identity comes from the root view, not copied settings', () {
      final root = buildAstrologyDashboard(libraryId: 'stale');
      final person =
          buildAstrologyDashboard(library: false, libraryId: _libraryId);
      expect(astrologyLibraryId(root, 'root-id'), 'root-id');
      expect(astrologyLibraryId(root, ''), isEmpty);
      expect(astrologyLibraryId(person, 'person-id'), _libraryId);
      expect(isAstrologyLibrary(person), isFalse);
      const blank = DashboardDocument();
      expect(isAstrologyLibrary(blank), isFalse);
      expect(astrologyLibraryId(blank, 'ordinary-dashboard'), isEmpty);
      expect(withAstrologyInput(blank, _input()), same(blank));
      expect(astrologyInputFromDashboard(blank).utc, isNull);
    });

    test('malformed profiles do not silently become a transit', () {
      final document = buildAstrologyDashboard();
      final card = _card(document, astrologyInputWidgetType);
      for (final profile in [
        'not an object',
        {'utc': 'not a date'},
        {'version': 99},
      ]) {
        expect(
          () => astrologyInputFromDashboard(
            document.withWidget(card.withSettings({'profile': profile})),
          ),
          throwsFormatException,
        );
      }
    });

    test('only a real database binding on the events card counts as events',
        () {
      var document = buildAstrologyDashboard().addWidget(
        const DashboardWidgetSpec(
          id: 'unrelated-table',
          type: 'database',
          source: DashboardDataSource(
            kind: DashboardSourceKind.database,
            viewId: 'some-other-table',
          ),
        ),
      );
      expect(astrologyEventsViewId(document), isEmpty);
      final card = _card(document, astrologyEventsWidgetType);
      document = document.withWidget(
        card.copyWith(
          source: const DashboardDataSource(
            kind: DashboardSourceKind.page,
            viewId: 'not-a-table',
          ),
        ),
      );
      expect(astrologyEventsViewId(document), isEmpty);
    });
  });

  group('the life-events schema', () {
    test('six typed columns, text primary, nine planet choices, no fake events',
        () {
      expect(astrologyLifeEventsTable.rows, isEmpty);
      expect(
        astrologyLifeEventsTable.columns
            .map((column) => (column.name, column.type)),
        [
          ('Event name', FieldType.RichText),
          ('Date', FieldType.DateTime),
          ('Dasha', FieldType.SingleSelect),
          ('Antardasha', FieldType.SingleSelect),
          ('Pratyantardasha', FieldType.SingleSelect),
          ('Notes', FieldType.RichText),
        ],
      );
      for (final column in astrologyLifeEventsTable.columns.skip(2).take(3)) {
        expect(column.options, VedicBody.values.map((body) => body.label));
      }
    });

    test('read-back uses primary identity and does not assume field-list order',
        () {
      final fields = _eventFields('events');
      final primary = FieldPB()..mergeFromMessage(fields.first);
      for (final field in fields) {
        field.clearIsPrimary();
      }
      expect(
        () => BackendAstrologyDashboardRepository.verifyEventsSchema(
          fields: fields.reversed.toList(),
          primary: primary,
        ),
        returnsNormally,
      );
      expect(
        () => BackendAstrologyDashboardRepository.verifyEventsSchema(
          fields: fields,
          primary: fields.last,
        ),
        throwsStateError,
      );
    });

    test('a missing, misnamed or mistyped field is never accepted', () {
      for (var index = 0; index < 6; index++) {
        for (final defect in ['missing', 'name', 'type']) {
          final fields = _eventFields('events');
          final primary = FieldPB()..mergeFromMessage(fields.first);
          switch (defect) {
            case 'missing':
              fields.removeAt(index);
            case 'name':
              fields[index].name = 'Wrong field';
            case 'type':
              fields[index].fieldType = FieldType.Number;
          }
          expect(
            () => BackendAstrologyDashboardRepository.verifyEventsSchema(
              fields: fields,
              primary: primary,
            ),
            throwsStateError,
            reason: '$defect at field $index must fail verification.',
          );
        }
      }
    });

    test('missing planet options and duplicate field or option ids fail', () {
      for (final defect in ['planet', 'field-id', 'option-id']) {
        final fields = _eventFields('events');
        final primary = FieldPB()..mergeFromMessage(fields.first);
        if (defect == 'field-id') {
          fields.last.id = fields.first.id;
        } else {
          final options =
              SingleSelectTypeOptionPB.fromBuffer(fields[2].typeOptionData);
          if (defect == 'planet') {
            options.options.removeLast();
          } else {
            options.options.last.id = options.options.first.id;
          }
          fields[2].typeOptionData = options.writeToBuffer();
        }
        expect(
          () => BackendAstrologyDashboardRepository.verifyEventsSchema(
            fields: fields,
            primary: primary,
          ),
          throwsStateError,
          reason: defect,
        );
      }
    });
  });

  group('saving real nested horoscopes', () {
    late _FakeAstrologyRepository repository;
    late AstrologyDashboardService service;

    setUp(() {
      repository = _FakeAstrologyRepository()
        ..seed(
          ViewPB(
            id: _libraryId,
            parentViewId: 'workspace',
            name: 'Astrology dashboard template',
            extra:
                DashboardMetadata.newExtra(document: buildAstrologyDashboard()),
          ),
        );
      service = AstrologyDashboardService(repository: repository);
    });

    test('creates person under library and an editable Grid under the person',
        () async {
      final libraryBefore = repository.views[_libraryId]!.extra;
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      final eventsId = astrologyEventsViewId(saved.dashboard!.document);
      expect(saved.parentViewId, _libraryId);
      expect(saved.layout, ViewLayoutPB.Document);
      expect(saved.isDashboard, isTrue);
      expect(isAstrologyLibrary(saved.dashboard!.document), isFalse);
      expect(
          astrologyLibraryId(saved.dashboard!.document, saved.id), _libraryId);
      final events = repository.views[eventsId]!;
      expect(events.parentViewId, saved.id);
      expect(events.layout, ViewLayoutPB.Grid);
      expect(events.isDashboard, isFalse);
      expect(repository.built, [eventsId]);
      expect(repository.rows[eventsId], isEmpty);
      expect(repository.created.map((view) => view.id), [saved.id, eventsId]);
      expect(repository.updated.single.childViews, isEmpty);
      expect(saved.childViews.single.id, eventsId,
          reason: 'Return the fresh read.');
      expect(repository.views[_libraryId]!.extra, libraryBefore);
      expect((await service.people(_libraryId)).single.id, saved.id);
    });

    test('several people have independent view ids, inputs and table bindings',
        () async {
      final first =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      final second = await service.savePerson(
        libraryViewId: _libraryId,
        input: _input('Second person').copyWith(utc: DateTime.utc(2001, 8, 9)),
      );
      final firstEvents = astrologyEventsViewId(first.dashboard!.document);
      final secondEvents = astrologyEventsViewId(second.dashboard!.document);
      expect({first.id, second.id, firstEvents, secondEvents}, hasLength(4));
      expect(repository.views[firstEvents]!.parentViewId, first.id);
      expect(repository.views[secondEvents]!.parentViewId, second.id);
      expect(astrologyInputFromDashboard(first.dashboard!.document).name,
          'First person');
      expect(astrologyInputFromDashboard(second.dashboard!.document).name,
          'Second person');
      repository.rows[firstEvents]!
          .add({'Event name': 'A real note', 'Notes': 'Keep me'});
      expect(repository.rows[secondEvents], isEmpty);
      expect(
        (await service.people(_libraryId)).map((view) => view.id),
        [first.id, second.id],
      );
    });

    test('a new save never reuses another document\'s life-events binding',
        () async {
      final first = await service.savePerson(
        libraryViewId: _libraryId,
        input: _input(),
      );
      final firstEvents = astrologyEventsViewId(first.dashboard!.document);
      repository.rows[firstEvents]!.add({'Notes': 'Only the first person'});
      final second = await service.savePerson(
        libraryViewId: _libraryId,
        input: _input('Second person'),
        document: first.dashboard!.document,
      );
      final secondEvents = astrologyEventsViewId(second.dashboard!.document);
      expect(secondEvents, isNot(firstEvents));
      expect(repository.views[secondEvents]!.parentViewId, second.id);
      expect(repository.rows[secondEvents], isEmpty);
      expect(repository.rows[firstEvents]!.single['Notes'],
          'Only the first person');
    });

    test('saved input and dashboard survive both JSON and protobuf round trips',
        () async {
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      final restored = ViewPB.fromBuffer(saved.writeToBuffer());
      final document = restored.dashboard!.document;
      expect(astrologyInputFromDashboard(document).toJson(), _input().toJson());
      expect(astrologyInputFromDashboard(document).utc!.isUtc, isTrue);
      final decoded = DashboardDocument.fromJson(
        Map<String, Object?>.from(
            jsonDecode(jsonEncode(document.toJson())) as Map),
      );
      expect(decoded.toJson(), document.toJson());
      expect(astrologyEventsViewId(decoded), saved.childViews.single.id);
    });

    test('a pending table build cannot publish a saved dashboard or complete',
        () async {
      final entered = Completer<void>();
      final gate = Completer<void>();
      repository.buildEntered = entered;
      repository.buildGate = gate;
      var completed = false;
      final saving = service
          .savePerson(libraryViewId: _libraryId, input: _input())
          .then((view) {
        completed = true;
        return view;
      });
      try {
        await entered.future;
        expect(completed, isFalse);
        expect(repository.updated, isEmpty);
        expect(repository.views[repository.created.first.id]!.isDashboard,
            isFalse);
        expect(await service.people(_libraryId), isEmpty);
      } finally {
        gate.complete();
      }
      expect((await saving).isDashboard, isTrue);
    });

    test(
        're-reads metadata after table construction before merging the dashboard',
        () async {
      repository.onBuild = (eventsId) {
        final parent = repository.views[eventsId]!.parentViewId;
        repository.views[parent]!.extra =
            '{"cover":{"name":"new cover"},"other":{"keep":42}}';
      };
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      final extra = jsonDecode(saved.extra) as Map;
      expect(extra['cover'], {'name': 'new cover'});
      expect(extra['other'], {'keep': 42});
    });

    for (final passLiveDocument in [true, false]) {
      test(
          'updates retain notes, binding and ${passLiveDocument ? 'live' : 'stored'} layout',
          () async {
        final saved = await service.savePerson(
            libraryViewId: _libraryId, input: _input());
        final eventsId = astrologyEventsViewId(saved.dashboard!.document);
        final notes = repository.rows[eventsId]!
          ..add({
            'Event name': 'Graduation',
            'Date': '2011-06-20',
            'Notes': 'Original notes'
          });
        final live = _customDocument(saved.dashboard!.document);
        if (!passLiveDocument) {
          repository.views[saved.id]!.extra =
              DashboardMetadata(document: live).mergeIntoExtra(saved.extra);
        }
        final tableBefore = repository.views[eventsId]!.writeToBuffer();
        repository.writes.clear();
        final updated = await service.savePerson(
          libraryViewId: _libraryId,
          existingViewId: saved.id,
          input: _input('Renamed person'),
          document: passLiveDocument ? live : null,
        );
        expect(updated.id, saved.id);
        expect(updated.name, 'Renamed person');
        expect(
          updated.dashboard!.document.toJson(),
          withAstrologyInput(live, _input('Renamed person')).toJson(),
        );
        expect(repository.writes, ['update:${saved.id}']);
        expect(repository.created, hasLength(2));
        expect(repository.built, [eventsId]);
        expect(repository.deleted, isEmpty);
        expect(astrologyEventsViewId(updated.dashboard!.document), eventsId);
        expect(repository.rows[eventsId], same(notes));
        expect(notes.single['Notes'], 'Original notes');
        expect(repository.views[eventsId]!.writeToBuffer(), tableBefore);
      });
    }

    test('an omitted live document takes the last read layout and metadata',
        () async {
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      final latest = _customDocument(saved.dashboard!.document);
      var reads = 0;
      repository.onRead = (id) {
        if (id == saved.id && ++reads == 2) {
          repository.views[id]!.extra = DashboardMetadata(document: latest)
              .mergeIntoExtra('{"latest-cover":true}');
        }
      };
      final updated = await service.savePerson(
        libraryViewId: _libraryId,
        existingViewId: saved.id,
        input: _input('New name'),
      );
      expect(updated.dashboard!.document.toJson(),
          withAstrologyInput(latest, _input('New name')).toJson());
      expect(jsonDecode(updated.extra)['latest-cover'], isTrue);
    });

    test(
        'real parent rejects a wrong target even when its profile claims membership',
        () async {
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      repository.move(saved.id, 'another-library');
      repository.writes.clear();
      await expectLater(
        service.savePerson(
          libraryViewId: _libraryId,
          existingViewId: saved.id,
          input: _input('Wrong target'),
          document: saved.dashboard!.document,
        ),
        throwsStateError,
      );
      expect(repository.writes, isEmpty);
      expect(repository.views[saved.id]!.name, saved.name);
      expect(await service.people(_libraryId), isEmpty);
    });

    test('missing parent PBs use the actual child list, never the profile id',
        () async {
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      repository.omitParentFor.add(saved.id);
      repository.calls.clear();
      await service.savePerson(
        libraryViewId: _libraryId,
        existingViewId: saved.id,
        input: _input('Still a member'),
      );
      expect(repository.calls, contains('children:$_libraryId'));
      repository.move(saved.id, 'another-library');
      repository.writes.clear();
      await expectLater(
        service.savePerson(
          libraryViewId: _libraryId,
          existingViewId: saved.id,
          input: _input('Not a member'),
        ),
        throwsStateError,
      );
      expect(repository.writes, isEmpty);
    });

    test('does not rebuild or clear a missing or wrongly rebound events table',
        () async {
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      final document = saved.dashboard!.document;
      final card = _card(document, astrologyEventsWidgetType);
      final eventsId = card.source.viewId;
      repository.rows[eventsId]!.add({'Notes': 'Do not erase'});
      repository.writes.clear();
      for (final edited in [
        document.withoutWidget(card.id),
        document.withWidget(
            card.copyWith(source: card.source.copyWith(viewId: 'other-grid'))),
      ]) {
        await expectLater(
          service.savePerson(
            libraryViewId: _libraryId,
            existingViewId: saved.id,
            input: _input('Rename'),
            document: edited,
          ),
          throwsStateError,
        );
      }
      repository.trashed.add(eventsId);
      await expectLater(
        service.savePerson(
          libraryViewId: _libraryId,
          existingViewId: saved.id,
          input: _input('Rename'),
        ),
        throwsStateError,
      );
      expect(repository.writes, isEmpty);
      expect(repository.rows[eventsId]!.single['Notes'], 'Do not erase');
    });

    test('people filters actual children without a second person catalogue',
        () async {
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      repository.seed(ViewPB(id: 'plain', parentViewId: _libraryId));
      repository.seed(
        ViewPB(
            id: 'dashboard',
            parentViewId: _libraryId,
            extra: DashboardMetadata.newExtra()),
      );
      repository.seed(
        ViewPB(
          id: 'nested-library',
          parentViewId: _libraryId,
          extra:
              DashboardMetadata.newExtra(document: buildAstrologyDashboard()),
        ),
      );
      repository.seed(
        ViewPB(
          id: 'grid-with-wrong-envelope',
          parentViewId: _libraryId,
          layout: ViewLayoutPB.Grid,
          extra: saved.extra,
        ),
      );
      repository.views[saved.id]!.name = 'Renamed in the sidebar';
      repository.calls.clear();
      final people = await service.people(_libraryId);
      expect(people.map((view) => view.id), [saved.id]);
      expect(people.single.name, 'Renamed in the sidebar');
      expect(repository.calls, ['children:$_libraryId']);
      repository.trashed.add(saved.id);
      expect(await service.people(_libraryId), isEmpty);
    });

    test('empty preview scope and service construction do no IO', () async {
      expect(repository.calls, isEmpty);
      expect(await service.people(''), isEmpty);
      expect(await service.people('  '), isEmpty);
      expect(repository.calls, isEmpty);
      await expectLater(
        service.savePerson(libraryViewId: '', input: _input()),
        throwsArgumentError,
      );
      expect(repository.calls, isEmpty);
    });

    test('invalid birth input causes zero backend calls or writes', () async {
      final badInputs = [
        _input('  '),
        _input().copyWith(useCurrentTime: true),
        _input().copyWith(useCurrentLocation: true),
        AstrologyInput(
            name: 'Local time', utc: DateTime(1990, 5, 15), place: _place),
        _input().copyWith(utc: DateTime.utc(1700)),
        _input().copyWith(
          place: const AstrologyPlace(
              name: '', latitude: 0, longitude: 0, timeZone: 'UTC'),
        ),
        _input().copyWith(
          place: const AstrologyPlace(
              name: 'Pole', latitude: 90, longitude: 0, timeZone: 'UTC'),
        ),
        _input().copyWith(
          place: const AstrologyPlace(
              name: 'Invalid',
              latitude: 0,
              longitude: double.nan,
              timeZone: 'UTC'),
        ),
        AstrologyInput(
            name: 'Offset',
            utc: DateTime.utc(1990),
            place: _place,
            utcOffsetMinutes: 841),
        AstrologyInput(
            name: 'Year length',
            utc: DateTime.utc(1990),
            place: _place,
            dashaYearDays: 0),
      ];
      for (final input in badInputs) {
        await expectLater(
          service.savePerson(libraryViewId: _libraryId, input: input),
          throwsFormatException,
        );
      }
      expect(repository.writes, isEmpty);
      expect(repository.calls, isEmpty);
      expect(repository.created, isEmpty);
    });

    test('a plain destination or a library used as a person is rejected',
        () async {
      repository.seed(ViewPB(id: 'ordinary-page'));
      await expectLater(
        service.savePerson(libraryViewId: 'ordinary-page', input: _input()),
        throwsStateError,
      );
      await expectLater(
        service.savePerson(
          libraryViewId: _libraryId,
          existingViewId: _libraryId,
          input: _input(),
        ),
        throwsArgumentError,
      );
      expect(repository.writes, isEmpty);
    });

    for (final failure in [
      'person creation',
      'Grid creation',
      'table build',
      'missing field',
      'wrong field type',
      'metadata re-read',
      'metadata write',
      'silently ignored write',
      'confirmation read',
    ]) {
      test(
          '$failure failure is not reported as saved and trashes only new views',
          () async {
        repository.seed(ViewPB(
            id: 'keep-existing', parentViewId: _libraryId, name: 'Untouched'));
        switch (failure) {
          case 'person creation':
            repository.failCreateLayout = ViewLayoutPB.Document;
          case 'Grid creation':
            repository.failCreateLayout = ViewLayoutPB.Grid;
          case 'table build':
            repository.failBuild = true;
          case 'missing field':
            repository.alterFields = (fields) {
              fields.removeLast();
            };
          case 'wrong field type':
            repository.alterFields = (fields) {
              fields[1].fieldType = FieldType.RichText;
            };
          case 'metadata re-read':
            repository.onBuild = (eventsId) {
              repository.failReads
                  .add(repository.views[eventsId]!.parentViewId);
            };
          case 'metadata write':
            repository.failUpdate = true;
          case 'silently ignored write':
            repository.ignoreUpdate = true;
          case 'confirmation read':
            repository.failReadAfterUpdate = true;
        }
        await expectLater(
          service.savePerson(libraryViewId: _libraryId, input: _input()),
          throwsA(
            isA<AstrologyDashboardSaveException>().having(
              (error) => error.cleanupFailures,
              'cleanup failures',
              isEmpty,
            ),
          ),
        );
        expect(
          repository.deleted,
          repository.created.reversed.map((view) => view.id),
        );
        expect(repository.trashed,
            repository.created.map((view) => view.id).toSet());
        expect(repository.views['keep-existing']!.name, 'Untouched');
        expect(await service.people(_libraryId), isEmpty);
        expect(repository.trashed, isNot(contains(_libraryId)));
        expect(repository.trashed, isNot(contains('keep-existing')));
      });
    }

    test(
        'a malformed create response cannot trash the library or duplicate a rollback',
        () async {
      repository.createResponse = (_, __) => repository.views[_libraryId];
      await expectLater(
        service.savePerson(libraryViewId: _libraryId, input: _input()),
        throwsA(isA<AstrologyDashboardSaveException>()),
      );
      expect(repository.deleted, isEmpty);
      expect(repository.trashed, isEmpty);

      repository.createResponse = (parent, layout) =>
          layout == ViewLayoutPB.Grid ? repository.views[parent] : null;
      await expectLater(
        service.savePerson(libraryViewId: _libraryId, input: _input()),
        throwsA(isA<AstrologyDashboardSaveException>()),
      );
      expect(repository.created, hasLength(1));
      expect(repository.deleted, [repository.created.single.id]);
      expect(repository.trashed, isNot(contains(_libraryId)));
    });

    test(
        'cleanup failures preserve the cause and give recovery ids and guidance',
        () async {
      repository.failBuild = true;
      repository.failDeletes = true;
      await expectLater(
        service.savePerson(libraryViewId: _libraryId, input: _input()),
        throwsA(
          isA<AstrologyDashboardSaveException>()
              .having((error) => error.cause.toString(), 'cause',
                  contains('Table build failed'))
              .having((error) => error.createdViewIds, 'created views',
                  hasLength(2))
              .having((error) => error.cleanupFailures, 'cleanup failures',
                  hasLength(2))
              .having((error) => error.toString(), 'recovery instructions',
                  contains('Trash')),
        ),
      );
      expect(repository.deleted,
          repository.created.reversed.map((view) => view.id));
      expect(repository.trashed, isEmpty);
      expect(repository.updated, isEmpty);
      expect(await service.people(_libraryId), isEmpty,
          reason: 'No partial dashboard published.');
    });

    test(
        'a failed existing-person update never deletes or rebuilds existing data',
        () async {
      final saved =
          await service.savePerson(libraryViewId: _libraryId, input: _input());
      final eventsId = astrologyEventsViewId(saved.dashboard!.document);
      repository.rows[eventsId]!.add({'Notes': 'Existing notes'});
      repository.writes.clear();
      repository.failUpdate = true;
      await expectLater(
        service.savePerson(
          libraryViewId: _libraryId,
          existingViewId: saved.id,
          input: _input('Not saved'),
        ),
        throwsStateError,
      );
      expect(repository.writes, ['update:${saved.id}']);
      expect(repository.views[saved.id]!.extra, saved.extra);
      expect(repository.built, [eventsId]);
      expect(repository.deleted, isEmpty);
      expect(repository.rows[eventsId]!.single['Notes'], 'Existing notes');
    });

    test('failed confirmation of an existing save never rolls back its views',
        () async {
      final saved = await service.savePerson(
        libraryViewId: _libraryId,
        input: _input(),
      );
      final eventsId = astrologyEventsViewId(saved.dashboard!.document);
      repository.rows[eventsId]!.add({'Notes': 'Still present'});
      repository.failReadAfterUpdate = true;
      repository.writes.clear();
      await expectLater(
        service.savePerson(
          libraryViewId: _libraryId,
          existingViewId: saved.id,
          input: _input('Written but not confirmed'),
        ),
        throwsStateError,
      );
      expect(repository.writes, ['update:${saved.id}']);
      expect(repository.deleted, isEmpty);
      expect(repository.trashed, isEmpty);
      expect(repository.built, [eventsId]);
      expect(repository.rows[eventsId]!.single['Notes'], 'Still present');
    });
  });
}

void _expectNoOverlaps(List<DashboardPlacement> placements) {
  for (var i = 0; i < placements.length; i++) {
    for (var j = i + 1; j < placements.length; j++) {
      expect(placements[i].overlaps(placements[j]), isFalse,
          reason: '$i overlaps $j');
    }
  }
}

DashboardDocument _customDocument(DashboardDocument original) {
  final chart = _card(original, astrologyChartWidgetType);
  final events = _card(original, astrologyEventsWidgetType);
  return original
      .withWidget(
        chart.copyWith(
          placement: const DashboardPlacement(
              column: 7, row: 50, columnSpan: 5, rowSpan: 9),
          accent: DashboardAccent.teal,
          title: 'My own chart title',
          hidden: true,
          settings: {...chart.settings, 'custom-chart-option': true},
        ),
      )
      .withWidget(
        events.copyWith(
          source: events.source.copyWith(
            sortField: 'Date',
            sortDescending: true,
            filters: const [
              DashboardFilter(
                  field: 'Notes', operator: 'contains', value: 'important')
            ],
          ),
          settings: const {'custom-events-option': 'keep'},
        ),
      )
      .addWidget(
        const DashboardWidgetSpec(
          id: 'my-unrelated-note',
          type: 'sticky_note',
          placement: DashboardPlacement(row: 64, columnSpan: 12, rowSpan: 3),
          title: 'Personal writing',
          settings: {'text': 'Never replace this note.'},
          actions: [
            DashboardAction(
                kind: DashboardActionKind.openPage, target: 'another-page')
          ],
        ),
      )
      .withVariable(
        const DashboardVariable(
            key: 'my-filter',
            label: 'My filter',
            kind: DashboardVariableKind.text),
      )
      .copyWith(
        subtitle: 'My custom layout',
        icon: '✦',
        settings: original.settings
            .copyWith(density: DashboardDensity.compact, reduceMotion: true),
      );
}

List<FieldPB> _eventFields(String viewId) {
  final fields = <FieldPB>[];
  final columns = astrologyLifeEventsTable.columns;
  for (var index = 0; index < columns.length; index++) {
    final column = columns[index];
    fields.add(
      FieldPB(
        id: '$viewId-field-$index',
        name: column.name,
        fieldType: column.type,
        isPrimary: index == 0,
        typeOptionData: column.type == FieldType.SingleSelect
            ? SingleSelectTypeOptionPB(
                options: [
                  for (final label in column.options)
                    SelectOptionPB(id: '$viewId-$index-$label', name: label),
                ],
              ).writeToBuffer()
            : null,
      ),
    );
  }
  return fields;
}

/// In-memory implementation of the documented repository IO contract. Every
/// read is a fresh PB, update responses omit children, and delete is reversible
/// Trash. Rows exist only here to detect unwanted rebuilds/notes loss in tests.
class _FakeAstrologyRepository implements AstrologyDashboardRepository {
  final views = <String, ViewPB>{};
  final children = <String, List<String>>{};
  final rows = <String, List<Map<String, String>>>{};
  final schemas = <String, List<FieldPB>>{};
  final calls = <String>[];
  final writes = <String>[];
  final created = <ViewPB>[];
  final updated = <ViewPB>[];
  final deleted = <String>[];
  final built = <String>[];
  final trashed = <String>{};
  final omitParentFor = <String>{};
  final failReads = <String>{};

  ViewLayoutPB? failCreateLayout;
  bool failBuild = false;
  bool failUpdate = false;
  bool ignoreUpdate = false;
  bool failReadAfterUpdate = false;
  bool failDeletes = false;
  ViewPB? Function(String, ViewLayoutPB)? createResponse;
  void Function(List<FieldPB>)? alterFields;
  void Function(String)? onBuild;
  void Function(String)? onRead;
  Completer<void>? buildEntered;
  Completer<void>? buildGate;
  int _nextId = 0;

  void seed(ViewPB view) {
    views[view.id] = ViewPB()..mergeFromMessage(view);
    children.putIfAbsent(view.parentViewId, () => []).add(view.id);
  }

  void move(String viewId, String parentViewId) {
    final view = views[viewId]!;
    children[view.parentViewId]?.remove(viewId);
    view.parentViewId = parentViewId;
    children.putIfAbsent(parentViewId, () => []).add(viewId);
  }

  void _write(String call) {
    calls.add(call);
    writes.add(call);
  }

  ViewPB _snapshot(String viewId) {
    final stored = views[viewId];
    if (stored == null || trashed.contains(viewId)) {
      throw StateError('View $viewId is missing or in Trash.');
    }
    final view = ViewPB()..mergeFromMessage(stored);
    view.childViews.clear();
    for (final id in children[viewId] ?? const <String>[]) {
      if (!trashed.contains(id)) {
        view.childViews.add(ViewPB()..mergeFromMessage(views[id]!));
      }
    }
    if (omitParentFor.contains(viewId)) {
      view.clearParentViewId();
    }
    return view;
  }

  @override
  Future<ViewPB> createView({
    required String parentViewId,
    required String name,
    required ViewLayoutPB layoutType,
  }) async {
    _write('create:$layoutType:$parentViewId');
    if (failCreateLayout == layoutType) {
      throw StateError('View creation failed.');
    }
    _snapshot(parentViewId);
    final response = createResponse?.call(parentViewId, layoutType);
    if (response != null) {
      return ViewPB()..mergeFromMessage(response);
    }
    final view = ViewPB(
      id: 'created-${++_nextId}',
      parentViewId: parentViewId,
      name: name,
      layout: layoutType,
      extra: '{"cover":{"created":true}}',
    );
    seed(view);
    created.add(ViewPB()..mergeFromMessage(view));
    return _snapshot(view.id);
  }

  @override
  Future<ViewPB> readView(String viewId) async {
    calls.add('read:$viewId');
    onRead?.call(viewId);
    if (failReads.contains(viewId)) {
      throw StateError('View read failed.');
    }
    return _snapshot(viewId);
  }

  @override
  Future<ViewPB> updateView({
    required String viewId,
    required String name,
    required String extra,
  }) async {
    _write('update:$viewId');
    if (failUpdate) {
      throw StateError('View update failed.');
    }
    _snapshot(viewId);
    if (!ignoreUpdate) {
      views[viewId]!
        ..name = name
        ..extra = extra;
    }
    if (failReadAfterUpdate) {
      failReads.add(viewId);
    }
    final response = ViewPB()..mergeFromMessage(views[viewId]!);
    response.childViews.clear();
    updated.add(response);
    return response;
  }

  @override
  Future<void> deleteView(String viewId) async {
    _write('delete:$viewId');
    deleted.add(viewId);
    if (failDeletes) {
      throw StateError('Trash operation failed for $viewId.');
    }
    void trashTree(String id) {
      trashed.add(id);
      for (final child in children[id] ?? const <String>[]) {
        trashTree(child);
      }
    }

    trashTree(viewId);
  }

  @override
  Future<List<ViewPB>> childViews(String parentViewId) async {
    calls.add('children:$parentViewId');
    _snapshot(parentViewId);
    return [
      for (final id in children[parentViewId] ?? const <String>[])
        if (!trashed.contains(id)) _snapshot(id),
    ];
  }

  @override
  Future<void> buildEvents(String viewId) async {
    _write('build:$viewId');
    built.add(viewId);
    expect(_snapshot(viewId).layout, ViewLayoutPB.Grid);
    buildEntered?.complete();
    final gate = buildGate;
    if (gate != null) {
      await gate.future;
    }
    if (failBuild) {
      throw StateError('Table build failed.');
    }
    final fields = _eventFields(viewId);
    final primary = FieldPB()..mergeFromMessage(fields.first);
    schemas[viewId] = fields;
    rows[viewId] = [];
    alterFields?.call(fields);
    BackendAstrologyDashboardRepository.verifyEventsSchema(
        fields: fields, primary: primary);
    onBuild?.call(viewId);
  }
}
