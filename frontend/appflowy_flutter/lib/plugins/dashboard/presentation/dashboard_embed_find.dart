import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/plugins/database/find/database_find_session.dart'
    show databaseFindNativeChanges;
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_session.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/shared/find_replace/text_find.dart'
    show buildFindPattern, matchesOfPattern;
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_find_projection.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    show AppFlowyEditor, EditorState;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dashboard_find.dart';

/// Read-only bridge to already-mounted, renderer-owned native text. It does
/// not open an editor, read file/URL/config payloads, or borrow a child's query.
/// Default previews lend only typed, painted body values, never their title,
/// cover, loading face or the unseen remainder of their target document.
class DashboardFindEmbed extends StatefulWidget {
  const DashboardFindEmbed(
      {super.key,
      required this.dashboard,
      required this.spec,
      required this.child});
  final DashboardController dashboard;
  final DashboardWidgetSpec spec;
  final Widget child;

  static bool supports(DashboardWidgetSpec spec) =>
      const {'page', 'page_link', 'database', 'chart'}.contains(spec.type) &&
      spec.source.viewId.isNotEmpty;

  @override
  State<DashboardFindEmbed> createState() => _DashboardFindEmbedState();
}

class _DashboardFindEmbedState extends State<DashboardFindEmbed>
    implements DashboardFindEmbedDelegate {
  final _key = GlobalKey();
  DashboardFindController? _find;
  DocumentFindReadProvider? _provider;
  StreamSubscription<String>? _changes;
  StreamSubscription<String>? _nativeChanges;
  Timer? _deadline;
  int _generation = 0;
  bool _authorized = false;
  bool _loading = false;
  bool _observing = false;
  bool _failed = false;
  List<SurfaceFindEntry> _entries = const [];
  List<Object?> _stamp = const [];
  Brightness _brightness = Brightness.light;
  Object? _dashboardRevision;
  List<Object> _previewSnapshot = const [];
  FolderGalleryFindViewToken? _allowedView;
  final _documents = <EditorState, DocumentFindSession>{};
  final _entryText = <DashboardEmbedFindId, String>{};
  final _publishedRanges = <(DashboardEmbedFindId, int, int)>{};
  final _validRuns = <(RenderBox, String, int), bool>{};
  final _runUrls = <(RenderBox, String, int), List<RegExpMatch>>{};
  Map<RenderObject, (String, Set<(int, int)>)>? _documentRanges;
  final _documentRuns = <(RenderBox, String, int), Set<(int, int)>?>{};

  void _beginValidation() {
    _validRuns.clear();
    _runUrls.clear();
    _documentRuns.clear();
    _documentRanges = null;
  }

  bool get _supported => DashboardFindEmbed.supports(widget.spec);

  bool get _queryActive =>
      mounted &&
      _supported &&
      _find?.isOpen == true &&
      _find!.query.isNotEmpty &&
      !_find!.queryInvalid;

  @override
  void initState() {
    super.initState();
    widget.dashboard.addListener(_dashboardChanged);
    _dashboardRevision = _revision;
  }

  Object get _revision => (
        widget.dashboard.document,
        widget.dashboard.state,
        widget.dashboard.refreshToken,
        widget.dashboard.isReadOnly
      );

  void _dashboardChanged() {
    if (_dashboardRevision == _revision) return;
    _dashboardRevision = _revision;
    _invalidate();
  }

  void _findChanged() {
    _publishedRanges
      ..clear()
      ..addAll([
        for (final hit in _find?.matches ?? const <SurfaceFindMatch>[])
          if (hit.id is DashboardEmbedFindId &&
              (hit.id as DashboardEmbedFindId).widgetId == widgetId)
            (hit.id as DashboardEmbedFindId, hit.range.start, hit.range.end),
      ]);
    if (!_queryActive &&
        (_provider != null || _authorized || _loading || _failed))
      _invalidate();
    _observe();
  }

  RenderSurfaceFindHighlight? get _render =>
      _key.currentContext?.findRenderObject() as RenderSurfaceFindHighlight?;

  @override
  String get widgetId => widget.spec.id;

  bool get _eligible {
    if (!_queryActive || !databaseFindContextIsActive(context)) return false;
    final location = _find!.locationOf(widgetId);
    final spec = location?.$1;
    final section = location?.$2;
    return _find?.allowsEmbed(this) == true &&
        spec == widget.spec &&
        const {'page', 'page_link', 'database', 'chart'}.contains(spec?.type) &&
        spec!.source.viewId.isNotEmpty &&
        !spec.hidden &&
        !spec.collapsed &&
        section != null &&
        dashboardVisibilityHolds(section.visibleWhen, widget.dashboard.state) &&
        dashboardVisibilityHolds(spec.visibleWhen, widget.dashboard.state) &&
        _render != null &&
        surfaceFindRenderAvailable(_render!);
  }

  @override
  Iterable<SurfaceFindEntry> get entries {
    if (!_authorized || !_eligible || !_snapshotCurrent) return const [];
    _beginValidation();
    return _entries;
  }

  @override
  Rect? get currentRect {
    final render = _render;
    final rect = render?.currentRect;
    return !_authorized ||
            !_eligible ||
            !_snapshotCurrent ||
            render == null ||
            rect == null
        ? null
        : MatrixUtils.transformRect(render.getTransformTo(null), rect);
  }

  @override
  void reveal() {
    if (!_authorized || !_eligible || !_snapshotCurrent) return;
    _render?.revealCurrent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _brightness = Theme.of(context).brightness;
    final controller = SurfaceFindScope.maybeOf(context);
    final next = controller is DashboardFindController ? controller : null;
    if (!identical(_find, next)) {
      _unbind();
      _find = next;
      _find?.addListener(_findChanged);
      if (_supported) _find?.registerEmbed(this, this);
    }
    _observe();
  }

  @override
  void didUpdateWidget(DashboardFindEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dashboard != widget.dashboard) {
      oldWidget.dashboard.removeListener(_dashboardChanged);
      widget.dashboard.addListener(_dashboardChanged);
    }
    if (oldWidget.spec != widget.spec ||
        oldWidget.dashboard != widget.dashboard) {
      _invalidate();
      _find?.unregisterEmbed(this);
      if (_supported) _find?.registerEmbed(this, this);
    }
    _observe();
  }

  void _bindProvider() {
    if (_provider != null) return;
    final provider = _find?.readProvider ?? DocumentFindReadProvider.native();
    _provider = provider;
    provider.accessChanges?.addListener(_invalidate);
    _changes = provider.contentChanges?.listen((_) => _invalidate());
    if (_find?.readProvider == null) {
      _nativeChanges = databaseFindNativeChanges().listen((_) => _invalidate());
    }
  }

  void _invalidate() {
    final hadData = _authorized || _loading || _failed || _entries.isNotEmpty;
    _generation++;
    _deadline?.cancel();
    _provider?.readScheduler.cancel(this);
    _authorized = false;
    _clearDocuments();
    _allowedView = null;
    // didUpdateWidget can invalidate while the child list is being rebuilt.
    // Revoke synchronously, but capture the new renderer snapshot only in
    // _authorize, reached by the existing mounted post-frame observer.
    _previewSnapshot = const [];
    _loading = false;
    _failed = false;
    _entries = const [];
    _entryText.clear();
    _publishedRanges.clear();
    _beginValidation();
    _stamp = const [];
    if (hadData)
      _render?.configure('', const FindOptions(), -1, true, _brightness);
    // Access changes must remove snippets immediately. Build-time changes are
    // deferred only for notification, never for the revoked delegate entries.
    if (hadData) _find?.revokeEmbed(widgetId);
    if (!_queryActive) _unbindProvider();
    _observe();
  }

  void _observe() {
    if (_observing || !_queryActive) return;
    _observing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _observing = false;
      if (!mounted) return;
      if (!_eligible) {
        if (_authorized || _loading || _entries.isNotEmpty) _invalidate();
        _unbindProvider();
        return;
      }
      if (!_snapshotCurrent) _invalidate();
      if (!_authorized && !_loading && !_failed) _authorize();
      if (_authorized) {
        _syncDocuments();
        _collect();
      }
      // Renderer layout/paint, model events and query changes schedule the
      // next observation. Unrelated application frames do not re-index text.
    });
  }

  bool _live(int generation) =>
      generation == _generation && _eligible && _snapshotCurrent;

  bool get _snapshotCurrent => listEquals(_previewSnapshot, _previewTokens());

  List<Object> _previewTokens() {
    SurfaceFindWork.record('snapshotScan');
    final tokens = <Object>[];
    var remaining = const DocumentFindLimits().maxEntries * 8;
    void visit(Element element) {
      SurfaceFindWork.record('snapshotVisit');
      if (--remaining < 0) return;
      final child = element.widget;
      if (child is AppFlowyEditor) {
        tokens
            .add((element, child.editorState, child.editorState.document.root));
        return;
      }
      if (child is DatabaseFindAnchor ||
          child is AppChart ||
          child is SurfaceFindExclude) return;
      if (child is FolderGalleryFindScope) {
        tokens.add((element, child.snapshotToken));
        return;
      }
      element.visitChildElements(visit);
    }

    _key.currentContext?.visitChildElements(visit);
    return tokens;
  }

  Future<ViewPB?> _allowed(String id, int generation) async {
    if (!_live(generation)) return null;
    final result = await _provider!.readView(id);
    if (!_live(generation) || result == null || result.id != id) return null;
    final snapshot = ViewPB.fromBuffer(result.writeToBuffer());
    final allowed = await _provider!.preflight(snapshot);
    return _live(generation) && allowed ? snapshot : null;
  }

  void _authorize() {
    _bindProvider();
    _previewSnapshot = _previewTokens();
    final provider = _provider!;
    final generation = ++_generation;
    final source = widget.spec.source.viewId;
    final owner = widget.dashboard.viewId;
    final document = widget.dashboard.document;
    final revision = widget.dashboard.refreshToken;
    _loading = true;
    _deadline = Timer(provider.deadline, () {
      if (!_live(generation)) return;
      _invalidate();
      _failed = true;
    });
    provider.readScheduler.schedule(this, () => _live(generation), () async {
      try {
        final beforeOwner =
            owner.isEmpty ? null : await _allowed(owner, generation);
        if (!_live(generation) || (owner.isNotEmpty && beforeOwner == null))
          return;
        final before = await _allowed(source, generation);
        if (!_live(generation) ||
            before == null ||
            before.workspaceItem != null ||
            decodeViewExtra(before.extra)
                .containsKey(WorkspaceItemMetadata.envelopeKey) ||
            !const [
              ViewLayoutPB.Document,
              ViewLayoutPB.Grid,
              ViewLayoutPB.Board,
              ViewLayoutPB.Calendar
            ].contains(before.layout)) return;
        // No secondary text I/O: the existing renderer supplies its real draft
        // and visible membership. A second gate rejects revocation/revision
        // changes while authorization was outstanding.
        final after = await _allowed(source, generation);
        final afterOwner =
            owner.isEmpty ? null : await _allowed(owner, generation);
        if (!_live(generation) ||
            !_same(before, after) ||
            (owner.isNotEmpty && !_same(beforeOwner, afterOwner)) ||
            !identical(document, widget.dashboard.document) ||
            revision != widget.dashboard.refreshToken) return;
        _allowedView = folderGalleryFindViewToken(before);
        _authorized = true;
        _syncDocuments();
        _collect();
        if (mounted) setState(() {});
      } on Exception {
        // Permission/transport failures are unavailable coverage, not an empty
        // successful search. Programming Errors remain visible to diagnostics.
        if (_live(generation)) _failed = true;
      } finally {
        if (generation == _generation) {
          _deadline?.cancel();
          _loading = false;
          if (!_authorized) _failed = true;
          _find?.embedChanged();
        }
      }
      // Cancellation never races this Future or releases its scheduler slot.
    });
  }

  bool _same(ViewPB? a, ViewPB? b) =>
      a != null &&
      b != null &&
      a.id == b.id &&
      a.layout == b.layout &&
      a.name == b.name &&
      a.extra == b.extra &&
      a.lastEdited == b.lastEdited;

  void _clearDocuments() {
    for (final session in _documents.values) {
      session.removeListener(_documentChanged);
      session.dispose();
    }
    _documents.clear();
  }

  void _documentChanged() {
    _beginValidation();
    _observe();
    _find?.embedChanged();
  }

  void _syncDocuments() {
    if (widget.spec.type != 'page') return;
    var remaining = const DocumentFindLimits().maxEntries * 8;
    void visit(Element element) {
      if (--remaining < 0) return;
      final child = element.widget;
      if (child is SurfaceFindExclude || child is FolderGalleryFindScope)
        return;
      if (child is AppFlowyEditor) {
        final editor = child.editorState;
        if (editor.isDisposed) return;
        final session = _documents.putIfAbsent(
            editor,
            () => DocumentFindSession(
                  editor,
                  readOnlyProjection: true,
                  isOwnerActive: () =>
                      _authorized && _eligible && _snapshotCurrent,
                )..addListener(_documentChanged));
        session.search(_find!.query, _find!.options);
        return;
      }
      element.visitChildElements(visit);
    }

    _key.currentContext?.visitChildElements(visit);
  }

  bool _documentOwnsMatch(SurfaceFindTextRun run, RegExpMatch match) {
    final owned = _documentRuns.putIfAbsent(
        (run.render, run.text, run.start), () => _rangesForRun(run));
    return owned?.contains((run.start + match.start, run.start + match.end)) ??
        false;
  }

  Set<(int, int)>? _rangesForRun(SurfaceFindTextRun run) {
    final ranges = _documentRanges ??= _indexDocumentRanges();
    for (RenderObject? object = run.render;
        object != null && object != _render;
        object = object.parent) {
      final owned = ranges[object];
      if (owned == null) continue;
      return owned.$1 == run.text || owned.$1 == '${run.text}\n'
          ? owned.$2
          : null;
    }
    return null;
  }

  Map<RenderObject, (String, Set<(int, int)>)> _indexDocumentRanges() {
    final ranges = <RenderObject, (String, Set<(int, int)>)>{};
    for (final entry in _documents.entries) {
      final editor = entry.key;
      final session = entry.value;
      if (!session.isActive ||
          session.query != _find?.query ||
          session.options != _find?.options) continue;
      final roots = <Object, RenderObject?>{};
      for (final result in session.matches) {
        SurfaceFindWork.record('documentMatchCheck');
        final node = result.node!;
        if (!roots.containsKey(node)) {
          final context = node.key.currentContext;
          roots[node] = identical(editor.getNodeAtPath(result.path!), node) &&
                  node.delta?.toPlainText() == result.match.input &&
                  context != null &&
                  context.mounted
              ? context.findRenderObject()
              : null;
        }
        final root = roots[node];
        if (root != null) {
          final owned = ranges.putIfAbsent(
              root, () => (result.match.input, <(int, int)>{}));
          owned.$2.add((result.match.start, result.match.end));
        }
      }
    }
    return ranges;
  }

  Iterable<RenderObject> _roots() {
    _beginValidation();
    if (!_authorized || !_eligible || !_snapshotCurrent) return const [];
    final roots = <RenderObject>[];
    var remaining = const DocumentFindLimits().maxEntries * 8;
    void previewText(Element element) {
      if (--remaining < 0) return;
      final child = element.widget;
      if (child is SurfaceFindExclude ||
          child is AppFlowyEditor ||
          child is DatabaseFindAnchor ||
          child is FolderGalleryFindScope) return;
      if (child is FolderGalleryFindText) {
        final render = element.findRenderObject();
        if (child.enabled &&
            render != null &&
            surfaceFindRenderAvailable(render)) roots.add(render);
        return;
      }
      element.visitChildElements(previewText);
    }

    void visit(Element element) {
      if (--remaining < 0) return;
      final child = element.widget;
      if (child is SurfaceFindExclude) return;
      if (child is FolderGalleryFindScope) {
        if (child.viewToken == _allowedView &&
            const {'page', 'page_link', 'database'}
                .contains(widget.spec.type)) {
          element.visitChildElements(previewText);
        }
        return;
      }
      final owns = (widget.spec.type == 'page' && child is AppFlowyEditor) ||
          (widget.spec.type == 'database' &&
              child is DatabaseFindAnchor &&
              child.enabled &&
              !child.target.isRow &&
              child.target.viewId == widget.spec.source.viewId) ||
          (widget.spec.type == 'chart' && child is AppChart);
      if (owns) {
        final render = element.findRenderObject();
        if (render != null && surfaceFindRenderAvailable(render))
          roots.add(render);
        return;
      }
      element.visitChildElements(visit);
    }

    _key.currentContext?.visitChildElements(visit);
    return roots;
  }

  static final _urls =
      RegExp(r'\b(?:[a-z][a-z0-9+.-]*://|www\.)\S+', caseSensitive: false);

  bool _acceptMatch(SurfaceFindTextRun run, RegExpMatch match) {
    if (!_authorized || !_eligible || !surfaceFindRenderAvailable(run.render))
      return false;
    if (!_validRuns.putIfAbsent(
        (run.render, run.text, run.start), () => _acceptRun(run))) return false;
    final urls = _runUrls.putIfAbsent((run.render, run.text, run.start),
        () => _urls.allMatches(run.text).toList());
    var lo = 0;
    var hi = urls.length;
    while (lo < hi) {
      final middle = (lo + hi) ~/ 2;
      if (urls[middle].end <= match.start) {
        lo = middle + 1;
      } else {
        hi = middle;
      }
    }
    if (lo < urls.length && urls[lo].start < match.end) return false;
    return _acceptRange(run, match);
  }

  bool _acceptRun(SurfaceFindTextRun run) {
    final native = run.render;
    final liveText = native is RenderParagraph
        ? native.text.toPlainText(includeSemanticsLabels: false)
        : (native as RenderEditable)
                .text
                ?.toPlainText(includeSemanticsLabels: false) ??
            '';
    if (run.start + run.text.length > liveText.length ||
        liveText.substring(run.start, run.start + run.text.length) !=
            run.text ||
        looksSealed(run.text.trimLeft())) return false;
    return true;
  }

  bool _acceptRange(SurfaceFindTextRun run, RegExpMatch match) {
    RenderFolderGalleryFindText? projection;
    for (RenderObject? object = run.render;
        object != null && object != _render;
        object = object.parent) {
      if (object is RenderFolderGalleryFindText) {
        projection = object;
        break;
      }
    }
    if (projection == null) {
      // The document session lends node-identity checked root text only.
      // Database/chart native roots retain their own scrolling/reveal.
      return widget.spec.type != 'page' || _documentOwnsMatch(run, match);
    }
    if (!projection.enabled ||
        projection.text != run.text ||
        run.start != 0 ||
        match.start < projection.contentStart ||
        projection.contentStart > run.text.length ||
        looksSealed(run.text.substring(projection.contentStart).trimLeft()))
      return false;

    // RenderParagraph can return just the visible prefix of a long selection.
    // Require every non-whitespace grapheme to have native boxes; this also
    // avoids splitting surrogate pairs/combining sequences at the ellipsis.
    var offset = match.start;
    for (final cluster in match.group(0)!.characters) {
      final end = offset + cluster.length;
      if (cluster.trim().isNotEmpty && run.boxes(offset, end).isEmpty)
        return false;
      offset = end;
    }
    final boxes = run.boxes(match.start, match.end);
    if (boxes.isEmpty) return false;
    final host = _render!;
    var hasVisibleBox = false;
    for (final box in boxes) {
      final actual = MatrixUtils.transformRect(
          run.render.getTransformTo(host), box.toRect());
      if (!actual.isFinite || actual.isEmpty) continue;
      hasVisibleBox = true;
      var visible = actual.intersect(Offset.zero & host.size);
      RenderObject child = run.render;
      for (var parent = child.parent;
          parent != null && child != host;
          parent = child.parent) {
        final clip = parent.describeApproximatePaintClip(child);
        if (clip != null) {
          visible = visible.intersect(
              MatrixUtils.transformRect(parent.getTransformTo(host), clip));
        }
        child = parent;
      }
      if (visible.isEmpty ||
          visible.left > actual.left + 0.1 ||
          visible.top > actual.top + 0.1 ||
          visible.right < actual.right - 0.1 ||
          visible.bottom < actual.bottom - 0.1) return false;
    }
    return hasVisibleBox;
  }

  void _collect() {
    if (!_authorized || !_eligible) return;
    const limits = DocumentFindLimits();
    final entries = <SurfaceFindEntry>[];
    final stamp = <Object?>[];
    RegExp? pattern;
    try {
      pattern = buildFindPattern(_find!.query, _find!.options);
    } on FormatException {
      pattern = null;
    }
    var bytes = 0;
    for (final run in _render?.textRuns ?? const <SurfaceFindTextRun>[]) {
      if (looksSealed(run.text.trimLeft())) continue;
      if (entries.length >= limits.maxEntries ||
          run.text.length > limits.maxBytes ||
          (bytes += utf8.encode(run.text).length) > limits.maxBytes) break;
      final id = DashboardEmbedFindId(widgetId, run.render, run.start);
      entries.add(DashboardEmbedFindEntry(
          id, run.text, (match) => _acceptMatch(run, match)));
      stamp.addAll([id, run.text]);
      if (pattern != null) {
        for (final match in matchesOfPattern(run.text, pattern)) {
          if (_acceptMatch(run, match)) stamp.add((match.start, match.end));
        }
      }
    }
    if (listEquals(stamp, _stamp)) return;
    _entries = entries;
    _entryText
      ..clear()
      ..addEntries(entries.map(
          (entry) => MapEntry(entry.id as DashboardEmbedFindId, entry.text)));
    _stamp = stamp;
    _find?.embedChanged();
  }

  void _unbind() {
    _generation++;
    _entryText.clear();
    _publishedRanges.clear();
    _beginValidation();
    _clearDocuments();
    _deadline?.cancel();
    _unbindProvider();
    _find?.removeListener(_findChanged);
    _find?.unregisterEmbed(this);
    _find = null;
    _authorized = _loading = _failed = false;
    _allowedView = null;
    _previewSnapshot = const [];
    _entries = const [];
    _stamp = const [];
  }

  void _unbindProvider() {
    _provider?.readScheduler.cancel(this);
    _provider?.accessChanges?.removeListener(_invalidate);
    unawaited(_changes?.cancel());
    unawaited(_nativeChanges?.cancel());
    _nativeChanges = null;
    _changes = null;
    _provider = null;
  }

  @override
  void dispose() {
    widget.dashboard.removeListener(_dashboardChanged);
    _unbind();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _find;
    final selected = controller?.current?.id;
    final own =
        selected is DashboardEmbedFindId && selected.widgetId == widgetId;
    final occurrence = !own || controller == null
        ? -1
        : controller.matches
            .take(controller.currentIndex)
            .where((match) =>
                match.id is DashboardEmbedFindId &&
                (match.id as DashboardEmbedFindId).widgetId == widgetId)
            .length;
    return SurfaceFindHighlight(
      key: _key,
      query: _authorized && controller?.isOpen == true ? controller!.query : '',
      options: controller?.options ?? const FindOptions(),
      currentOccurrence: occurrence,
      includeEditable: true,
      contentRoots: _roots,
      onGeometryChanged: _observe,
      canHighlight: (run) =>
          _authorized &&
          _entryText[DashboardEmbedFindId(widgetId, run.render, run.start)] ==
              run.text,
      canHighlightMatch: (run, match) =>
          _acceptMatch(run, match) &&
          _publishedRanges.contains((
            DashboardEmbedFindId(widgetId, run.render, run.start),
            match.start,
            match.end
          )),
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          if (_queryActive) {
            _render?.contentChanged();
            _observe();
          }
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
