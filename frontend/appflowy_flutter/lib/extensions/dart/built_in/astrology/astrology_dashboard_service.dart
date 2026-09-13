import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/templates/template_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';

/// The only IO boundary used by [AstrologyDashboardService].
///
/// All methods throw on failure; no null/success-shaped fallbacks are allowed.
/// createView creates ONE fresh view and returns its backend-assigned id, so
/// the service can track it before attempting the next operation. readView
/// reads current metadata; childViews lists direct, non-trashed children.
/// updateView need not return children (the service explicitly re-reads).
/// deleteView moves a view to Trash, never permanently deletes it.
/// buildEvents is for a NEW Grid only and must build AND verify its six fields,
/// primary field and planet choices before completing successfully.
abstract interface class AstrologyDashboardRepository {
  Future<ViewPB> createView({
    required String parentViewId,
    required String name,
    required ViewLayoutPB layoutType,
  });

  Future<ViewPB> readView(String viewId);

  Future<ViewPB> updateView({
    required String viewId,
    required String name,
    required String extra,
  });

  Future<void> deleteView(String viewId);

  Future<List<ViewPB>> childViews(String parentViewId);

  Future<void> buildEvents(String viewId);
}

/// Uses the same view/database services as the rest of the application. No
/// widget scope, provider, global person store or separate notes store is used.
class BackendAstrologyDashboardRepository
    implements AstrologyDashboardRepository {
  const BackendAstrologyDashboardRepository();

  @override
  Future<ViewPB> createView({
    required String parentViewId,
    required String name,
    required ViewLayoutPB layoutType,
  }) =>
      _value(
        ViewBackendService.createView(
          parentViewId: parentViewId,
          name: name,
          layoutType: layoutType,
        ),
        'Create astrology view',
      );

  @override
  Future<ViewPB> readView(String viewId) =>
      _value(ViewBackendService.getView(viewId), 'Read view $viewId');

  @override
  Future<ViewPB> updateView({
    required String viewId,
    required String name,
    required String extra,
  }) =>
      _value(
        ViewBackendService.updateView(
          viewId: viewId,
          name: name,
          extra: extra,
        ),
        'Save horoscope $viewId',
      );

  @override
  Future<void> deleteView(String viewId) => _value(
        ViewBackendService.deleteView(viewId: viewId),
        'Move unfinished view $viewId to Trash',
      );

  @override
  Future<List<ViewPB>> childViews(String parentViewId) => _value(
        ViewBackendService.getChildViews(viewId: parentViewId),
        'Read children of $parentViewId',
      );

  @override
  Future<void> buildEvents(String viewId) async {
    await TemplateService.buildTable(
      viewId: viewId,
      table: astrologyLifeEventsTable,
    );

    // buildTable deliberately logs and continues on individual failures.
    // Awaiting it is NOT proof that the requested database was built.
    final fields = await _value(
      FieldBackendService.getFields(viewId: viewId),
      'Verify life-events fields for $viewId',
    );
    final primary = await _value(
      FieldBackendService.getPrimaryField(viewId: viewId),
      'Verify life-events primary field for $viewId',
    );
    verifyEventsSchema(fields: fields, primary: primary);
  }

  /// Pure read-back validation, also usable by repository test doubles.
  /// Field order and getFields' isPrimary flags are not ownership evidence;
  /// the separately read primary field's id is authoritative.
  static void verifyEventsSchema({
    required List<FieldPB> fields,
    required FieldPB primary,
  }) {
    final columns = astrologyLifeEventsTable.columns;
    if (fields.length != columns.length ||
        fields.any((field) => field.id.isEmpty) ||
        fields.map((field) => field.id).toSet().length != fields.length) {
      throw StateError('The life-events table does not have all six fields.');
    }
    for (final column in columns) {
      final matches =
          fields.where((field) => field.name == column.name).toList();
      if (matches.length != 1 || matches.single.fieldType != column.type) {
        throw StateError(
            'The life-events field "${column.name}" is incorrect.');
      }
      final field = matches.single;
      if (column == columns.first &&
          (primary.id != field.id ||
              primary.name != column.name ||
              primary.fieldType != column.type)) {
        throw StateError('Event name must be the primary RichText field.');
      }
      if (column.type == FieldType.SingleSelect) {
        final options =
            SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData).options;
        final labels = options.map((option) => option.name).toList();
        if (!const ListEquality<String>().equals(labels, column.options) ||
            options.any((option) => option.id.isEmpty) ||
            options.map((option) => option.id).toSet().length !=
                options.length) {
          throw StateError(
            'The life-events field "${column.name}" needs all nine planet choices.',
          );
        }
      }
    }
  }

  static Future<T> _value<T>(
    Future<FlowyResult<T, FlowyError>> operation,
    String description,
  ) async {
    final result = await operation;
    return result.fold(
      (value) => value,
      (error) => throw StateError('$description: ${error.msg}'),
    );
  }
}

/// A failed NEW save, including any cleanup that could not be confirmed.
/// Callers must show the failure, not open the unfinished person as saved.
class AstrologyDashboardSaveException implements Exception {
  const AstrologyDashboardSaveException({
    required this.cause,
    required this.createdViewIds,
    required this.cleanupFailures,
  });

  final Object cause;
  final List<String> createdViewIds;
  final Map<String, Object> cleanupFailures;

  @override
  String toString() {
    if (cleanupFailures.isNotEmpty) {
      return 'The horoscope could not be saved: $cause. '
          'Cleanup could not be confirmed for views '
          '${cleanupFailures.keys.join(', ')}. '
          'Check the Astrology library and Trash to recover or remove these '
          'unfinished views before saving again. Cleanup errors: $cleanupFailures';
    }
    return 'The horoscope could not be saved: $cause.'
        '${createdViewIds.isEmpty ? '' : ' Newly created views were moved to Trash.'}';
  }
}

/// Persists the hierarchy library dashboard -> person dashboard -> events Grid.
///
/// Construction is inert. UI/template previews must not save and can pass an
/// empty id to [people] without IO. Registration and rendering belong to the
/// extension's UI, not to this service.
///
/// The backend has no transaction spanning these views. Reported new-save
/// failures get best-effort rollback; a process exit or lost create response
/// can still require manual recovery of unfinished views in the library.
class AstrologyDashboardService {
  AstrologyDashboardService({AstrologyDashboardRepository? repository})
      : _repository = repository ?? const BackendAstrologyDashboardRepository();

  static final instance = AstrologyDashboardService();

  final AstrologyDashboardRepository _repository;

  /// A new person always gets a fresh dashboard and its OWN events database.
  /// [document] applies only to an existing person: pass the live controller
  /// document to retain unsaved layout edits, or omit it to read current storage.
  /// Existing events must remain bound; a missing/rebound table is reported
  /// rather than rebuilt, because rebuilding could erase someone's notes.
  Future<ViewPB> savePerson({
    required String libraryViewId,
    required AstrologyInput input,
    String? existingViewId,
    DashboardDocument? document,
  }) async {
    // Validate before even reading the backend, much less creating a view.
    _validateInput(input);
    if (libraryViewId.trim().isEmpty) {
      throw ArgumentError.value(
        libraryViewId,
        'libraryViewId',
        'Save the library first.',
      );
    }
    if (existingViewId != null &&
        (existingViewId.trim().isEmpty || existingViewId == libraryViewId)) {
      throw ArgumentError.value(
        existingViewId,
        'existingViewId',
        'Choose a person, not the library.',
      );
    }
    final profile = input.copyWith(name: input.name.trim());
    final library = await _read(libraryViewId);
    final libraryDocument = _astrologyDocument(library);
    if (libraryDocument == null || !isAstrologyLibrary(libraryDocument)) {
      throw StateError(
          'The destination is not an Astrology dashboard library.');
    }

    if (existingViewId != null) {
      return _updatePerson(
        libraryViewId: libraryViewId,
        viewId: existingViewId,
        input: profile,
        document: document,
      );
    }

    final created = <String>[];
    try {
      // Do not publish a dashboard envelope until its database is ready.
      final person = await _repository.createView(
        parentViewId: libraryViewId,
        name: profile.name,
        layoutType: ViewLayoutPB.Document,
      );
      _trackCreated(person, created, libraryViewId);
      _requireLayout(person, ViewLayoutPB.Document);
      await _requireChild(person, libraryViewId);

      final events = await _repository.createView(
        parentViewId: person.id,
        name: 'Life events',
        layoutType: ViewLayoutPB.Grid,
      );
      _trackCreated(events, created, libraryViewId);
      _requireLayout(events, ViewLayoutPB.Grid);
      await _requireChild(events, person.id);
      await _repository.buildEvents(events.id);

      final savedDocument = buildAstrologyDashboard(
        input: profile,
        library: false,
        libraryId: libraryViewId,
        eventsViewId: events.id,
      );
      // Creating/building the Grid may have changed the parent's extra. Never
      // merge into the original create response or fall back after a read error.
      final current = await _read(person.id);
      _requireLayout(current, ViewLayoutPB.Document);
      await _requireChild(current, libraryViewId);
      await _repository.updateView(
        viewId: person.id,
        name: profile.name,
        extra: DashboardMetadata(document: savedDocument)
            .mergeIntoExtra(current.extra),
      );
      return await _confirmedPerson(
        person.id,
        libraryViewId,
        profile.name,
        savedDocument,
      );
    } catch (error, stackTrace) {
      final cleanupFailures = <String, Object>{};
      // Only ids created by THIS call, children first. No permanent deletion,
      // and a failed child cleanup must not prevent trying the parent cleanup.
      for (final id in created.reversed) {
        try {
          await _repository.deleteView(id);
        } catch (cleanupError) {
          cleanupFailures[id] = cleanupError;
        }
      }
      Error.throwWithStackTrace(
        AstrologyDashboardSaveException(
          cause: error,
          createdViewIds: List.unmodifiable(created),
          cleanupFailures: Map.unmodifiable(cleanupFailures),
        ),
        stackTrace,
      );
    }
  }

  /// Enumerates actual immediate children; moving/trashing a person therefore
  /// changes this list without synchronizing a second catalogue.
  Future<List<ViewPB>> people(String libraryViewId) async {
    if (libraryViewId.trim().isEmpty) {
      return const [];
    }
    final children = await _repository.childViews(libraryViewId);
    final people = <ViewPB>[];
    for (final child in children) {
      final document = _astrologyDocument(child);
      if (child.id != libraryViewId &&
          document != null &&
          !isAstrologyLibrary(document)) {
        people.add(child);
      }
    }
    return people;
  }

  Future<ViewPB> _updatePerson({
    required String libraryViewId,
    required String viewId,
    required AstrologyInput input,
    required DashboardDocument? document,
  }) async {
    final person = await _read(viewId);
    await _requireChild(person, libraryViewId);
    final stored = _requirePersonDocument(person);
    final eventsId = astrologyEventsViewId(stored);
    _requireExistingEvents(document ?? stored, eventsId);

    final events = await _read(eventsId);
    _requireLayout(events, ViewLayoutPB.Grid);
    await _requireChild(events, viewId);

    // Re-read AFTER checking the table. Omitted live documents must use the
    // latest layout too, not just the latest cover/other metadata.
    final current = await _read(viewId);
    await _requireChild(current, libraryViewId);
    final currentDocument = _requirePersonDocument(current);
    _requireExistingEvents(currentDocument, eventsId);
    final base = document ?? currentDocument;
    _requireExistingEvents(base, eventsId);
    var next = withAstrologyInput(base, input);
    final card = next.allWidgets.firstWhere(
      (widget) => widget.type == astrologyInputWidgetType,
    );
    // The real hierarchy wins over a copied library_id after a workspace move.
    next = next.withWidget(card.withSettings({'library_id': libraryViewId}));
    await _repository.updateView(
      viewId: viewId,
      name: input.name,
      extra: DashboardMetadata(document: next).mergeIntoExtra(current.extra),
    );
    // No cleanup/rebuild of existing views, even if this confirmation fails.
    return _confirmedPerson(viewId, libraryViewId, input.name, next);
  }

  Future<ViewPB> _confirmedPerson(
    String viewId,
    String libraryViewId,
    String name,
    DashboardDocument expected,
  ) async {
    final refreshed = await _read(viewId);
    await _requireChild(refreshed, libraryViewId);
    final document = _requirePersonDocument(refreshed);
    if (refreshed.name != name ||
        !const DeepCollectionEquality().equals(
          document.toJson(),
          expected.toJson(),
        )) {
      throw StateError(
        'The saved horoscope could not be confirmed. Reload before retrying.',
      );
    }
    return refreshed;
  }

  Future<ViewPB> _read(String viewId) async {
    final view = await _repository.readView(viewId);
    if (view.id != viewId) {
      throw StateError('The backend returned a different view for $viewId.');
    }
    return view;
  }

  Future<void> _requireChild(ViewPB view, String parentViewId) async {
    if (view.id.isEmpty || view.id == parentViewId) {
      throw StateError(
          'A horoscope and its container must be different views.');
    }
    if (view.parentViewId.isNotEmpty) {
      if (view.parentViewId != parentViewId) {
        throw StateError('View ${view.id} is not a child of $parentViewId.');
      }
      return;
    }
    // Some partial PBs omit the parent. Never trust the profile's library_id
    // as proof: ask the actual parent for its direct children instead.
    final children = await _repository.childViews(parentViewId);
    if (!children.any(
      (child) =>
          child.id == view.id &&
          (child.parentViewId.isEmpty || child.parentViewId == parentViewId),
    )) {
      throw StateError('View ${view.id} is not a child of $parentViewId.');
    }
  }

  static DashboardDocument? _astrologyDocument(ViewPB view) {
    if (!view.isDashboard) {
      return null;
    }
    final document = view.dashboard!.document;
    return document.allWidgets.any(
      (widget) => widget.type == astrologyInputWidgetType,
    )
        ? document
        : null;
  }

  static DashboardDocument _requirePersonDocument(ViewPB view) {
    final document = _astrologyDocument(view);
    if (document == null || isAstrologyLibrary(document)) {
      throw StateError('View ${view.id} is not a saved Astrology person.');
    }
    return document;
  }

  static void _requireExistingEvents(DashboardDocument document, String id) {
    if (id.isEmpty ||
        isAstrologyLibrary(document) ||
        !document.allWidgets.any(
          (widget) => widget.type == astrologyInputWidgetType,
        ) ||
        astrologyEventsViewId(document) != id) {
      throw StateError(
        'Keep this person\'s existing Life events table bound before saving. '
        'The table and its notes have not been rebuilt or cleared.',
      );
    }
  }

  static void _trackCreated(
    ViewPB view,
    List<String> created,
    String libraryViewId,
  ) {
    // Even a malformed create response must never put the existing library
    // or a duplicate parent id on the rollback list.
    if (view.id.trim().isEmpty ||
        view.id == libraryViewId ||
        created.contains(view.id)) {
      throw StateError('The backend did not return a fresh astrology view id.');
    }
    created.add(view.id);
  }

  static void _requireLayout(ViewPB view, ViewLayoutPB layout) {
    if (view.id.isEmpty || view.layout != layout) {
      throw StateError('The astrology view has an invalid id or layout.');
    }
  }

  static void _validateInput(AstrologyInput input) {
    if (input.name.trim().isEmpty) {
      throw const FormatException('Enter a name before saving a horoscope.');
    }
    if (input.utc == null || !input.utc!.isUtc) {
      throw const FormatException(
          'Choose a fixed UTC birth time before saving.');
    }
    final place = input.place;
    if (place == null || place.name.trim().isEmpty) {
      throw const FormatException('Choose a birth place before saving.');
    }
    input.validate();
  }
}
