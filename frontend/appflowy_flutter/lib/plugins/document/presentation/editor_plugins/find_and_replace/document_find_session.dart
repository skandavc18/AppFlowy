import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'document_find_content.dart';
import 'document_find_reference_index.dart';
import 'document_find_title.dart';
import 'document_search_highlight.dart';

enum DocumentFindResultKind { delta, title, embedded }

/// A title has no node/path/selection. An embedded result names its real parent
/// block, but is never a writable range in that block's delta.
class DocumentFindResult {
  DocumentFindResult(Node this.node, this.match)
      : path = List<int>.unmodifiable(node.path),
        kind = DocumentFindResultKind.delta,
        sourceId = node.id,
        viewId = null,
        location = '';

  DocumentFindResult.title(this.match)
      : node = null,
        path = null,
        kind = DocumentFindResultKind.title,
        sourceId = 'title',
        viewId = null,
        location = 'Title';

  DocumentFindResult.embedded(
    Node this.node,
    this.match, {
    required this.sourceId,
    required this.location,
    this.viewId,
  })  : path = List<int>.unmodifiable(node.path),
        kind = DocumentFindResultKind.embedded;

  final Node? node;
  final Path? path;
  final RegExpMatch match;
  final DocumentFindResultKind kind;
  final String sourceId;
  final String? viewId;
  final String location;
  bool get isWritable => kind == DocumentFindResultKind.delta;

  Selection? get selection => !isWritable
      ? null
      : Selection.single(
          path: path!,
          startOffset: match.start,
          endOffset: match.end,
        );

  bool sameLocation(DocumentFindResult other) =>
      kind == other.kind &&
      identical(node, other.node) &&
      sourceId == other.sourceId &&
      viewId == other.viewId &&
      match.input == other.match.input &&
      match.start == other.match.start &&
      match.end == other.match.end;
}

/// One editor's find session. Searching and painting never apply transactions.
///
/// Listen to the model, not rendered blocks or the selection: even remote
/// transactions (which bypass transactionStream in the installed editor) notify
/// Nodes. A formatting-only repaint is not another text change.
class DocumentFindSession extends ChangeNotifier {
  DocumentFindSession(
    this.editorState, {
    this.isOwnerActive,
    this.canReplace,
    this.currentView,
    this.documentId,
    this.titleObstruction,
    Stream<ViewPB>? viewChanges,
    DocumentFindReadProvider? referenceProvider,
    this.limits = const DocumentFindLimits(),
    this.readOnlyProjection = false,
  }) {
    if (!editorState.isDisposed) {
      _pageId = documentId ?? currentView?.call()?.id;
      if (!readOnlyProjection) {
        _title = DocumentFindTitle.of(editorState)..addListener(_titleChanged);
        _viewSubscription = viewChanges?.listen((_) => _titleChanged());
      }
      if (!readOnlyProjection && (_pageId?.isNotEmpty ?? false)) {
        _references = DocumentFindReferenceIndex(
          pageId: _pageId!,
          provider: referenceProvider ?? DocumentFindReadProvider.native(),
          isOwnerActive: () => isActive,
          limits: limits,
        )..addListener(_referencesChanged);
      }
      _origin = editorState.selection?.normalized.start;
      editorState.onDispose.addListener(_editorDisposed);
      editorState.editableNotifier.addListener(_permissionsChanged);
      _readDocument();
    }
  }

  final EditorState editorState;
  final bool Function()? isOwnerActive;
  final bool Function()? canReplace;
  final ViewPB? Function()? currentView;

  /// Stable native owner identity, independent of asynchronously loaded metadata.
  final String? documentId;
  final Rect? Function()? titleObstruction;
  final DocumentFindLimits limits;

  /// Independent root-query projection for an authorized mounted embed.
  /// Only mounted native delta nodes participate. The parent paints their real
  /// render objects; this session never borrows a child's query/highlight owner,
  /// changes selection, follows references, or permits Replace.
  final bool readOnlyProjection;
  final Map<Node, _FindNodeWatch> _watches = Map.identity();
  List<Node>? _projectionNodes;
  final Map<Node, _FindSheetWatch> _sheets = Map.identity();
  DocumentFindReferenceIndex? _references;
  DocumentFindTitle? _title;
  StreamSubscription<ViewPB>? _viewSubscription;
  String? _pageId;
  bool _localTruncated = false;
  int _localUnavailable = 0;
  bool _waitingToReveal = false;
  Selection? _asyncSelection;
  int _asyncNavigation = 0;

  String _query = '';
  FindOptions _options = const FindOptions();
  List<DocumentFindResult> _matches = const [];
  int _selectedIndex = -1;
  int _revision = 0;
  int _modelRevision = 0;
  int _navigationRevision = 0;
  int _projectionRevision = -1;
  int _projectionModelRevision = -1;
  bool _invalidPattern = false;
  bool _refreshQueued = false;
  bool _disposed = false;
  bool _busy = false;
  Selection? _ownedSelection;
  Position? _origin;

  String get query => _query;
  FindOptions get options => _options;
  List<DocumentFindResult> get matches => _matches;
  int get selectedIndex => _selectedIndex;
  int get revision => _revision;
  bool get invalidPattern => _invalidPattern;
  bool get busy => _busy;
  bool get loadingReferences => _references?.loading ?? false;
  bool get referencesTimedOut => _references?.timedOut ?? false;
  int get coverageUnknownCount => _references?.coverageUnknown ?? 0;
  bool get truncated => _localTruncated || (_references?.truncated ?? false);
  int get unavailableCount =>
      _localUnavailable + (_references?.unavailable ?? 0);
  bool get hasWritableMatches =>
      !readOnlyProjection && _matches.any((result) => result.isWritable);
  bool get currentIsWritable =>
      !readOnlyProjection && (_current?.isWritable ?? false);
  DocumentFindResult? get current => _current;
  bool get isActive =>
      !_disposed &&
      !editorState.isDisposed &&
      (isOwnerActive?.call() ?? true) &&
      (currentView == null ||
          currentView?.call()?.id == _pageId ||
          (documentId != null && currentView?.call() == null));
  bool get replaceAllowed =>
      !readOnlyProjection &&
      isActive &&
      editorState.editable &&
      (canReplace?.call() ?? true) &&
      currentView?.call()?.isLocked != true;

  @visibleForTesting
  int get debugWatchedNodeCount => _watches.length;

  bool get _hasOwnedSelection =>
      isActive &&
      _ownedSelection != null &&
      editorState.selectionUpdateReason ==
          SelectionUpdateReason.searchHighlight &&
      editorState.selection == _ownedSelection;

  DocumentFindResult? get _current =>
      _selectedIndex >= 0 && _selectedIndex < _matches.length
          ? _matches[_selectedIndex]
          : null;

  void search(String query, FindOptions options) {
    if (!isActive) return;
    if (_query == query && _options == options) {
      // Lazy native blocks can mount without changing the document model.
      // Projection refreshes notify only when membership/query really changes.
      if (readOnlyProjection) _refreshProjection();
      return;
    }
    final incremental = _query.isNotEmpty &&
        (query.startsWith(_query) || _query.startsWith(query));
    _query = query;
    _options = options;
    _revision++;
    _waitingToReveal = true;
    _refresh(
      select: true,
      anchor: editorState.selection?.normalized.start ?? _origin,
      // The bounded content cache is reusable, but native metadata and
      // unversioned imported files still need their existing fresh gates.
      refreshReferences: !incremental || _references?.canRefineQuery != true,
    );
    _asyncSelection = editorState.selection;
    _asyncNavigation = _navigationRevision;
  }

  void navigate({bool previous = false}) {
    if (!isActive || _busy) {
      return;
    }
    // A model edit may have happened before its coalesced refresh has run.
    _refresh();
    if (!isActive || _matches.isEmpty) {
      return;
    }
    _selectedIndex = (_selectedIndex + (previous ? -1 : 1)) % _matches.length;
    _publish(select: true);
  }

  Future<bool> replaceCurrent(String replacement) =>
      _replace(replacement, all: false);

  Future<bool> replaceAll(String replacement) =>
      _replace(replacement, all: true);

  Future<bool> _replace(String replacement, {required bool all}) async {
    if (!replaceAllowed || _busy || _query.isEmpty) {
      return false;
    }
    // Reserve before notifying; a synchronous listener cannot start a second
    // replacement while the first operation is being prepared.
    _busy = true;
    final revision = _revision;
    try {
      _refresh();
      if (!replaceAllowed || revision != _revision || _matches.isEmpty) {
        return false;
      }
      final current = _current;
      final targets = all
          ? _matches.where((result) => result.isWritable).toList()
          : [if (current != null && current.isWritable) current];
      if (targets.isEmpty) return false;
      for (final result in targets) {
        if (!identical(editorState.getNodeAtPath(result.path!), result.node) ||
            result.node!.delta?.toPlainText() != result.match.input) {
          return false;
        }
      }

      final transaction = editorState.transaction;
      Position? next;
      for (final result in targets.reversed) {
        final text = expandReplacement(
          replacement,
          result.match,
          useRegex: _options.useRegex,
        );
        next = Position(
          path: result.path!,
          offset: result.match.start + text.length,
        );
        if (text == result.match.group(0)) {
          continue;
        }
        // Inherit the matched run, not the character preceding the match.
        // Untouched runs remain intact; the editor supplies the inverse delta.
        final attributes = result.node!.delta!
            .slice(result.match.start, result.match.start + 1)
            .first
            .attributes;
        transaction.replaceText(
          result.node!,
          result.match.start,
          result.match.end - result.match.start,
          text,
          attributes: attributes ?? {},
        );
      }

      // Flush the installed editor's compose queue before any asynchronous
      // boundary. Every replacement is part of ONE native transaction.
      final hasChanges = transaction.operations.isNotEmpty;
      if (!replaceAllowed || revision != _revision) {
        return false;
      }
      final navigation = _navigationRevision;
      var modelRevision = _modelRevision;
      var selectNext = _hasOwnedSelection;
      if (hasChanges) {
        final undo = editorState.undoManager.undoStack;
        if (undo.isNonEmpty) {
          undo.last.seal();
        }
        transaction
          ..afterSelection = next == null ? null : Selection.collapsed(next)
          ..selectionExtraInfo = {
            selectionExtraInfoDoNotAttachTextService: true,
          };
        final applied = editorState.apply(
          transaction,
          withUpdateSelection: false,
          skipHistoryDebounce: true,
        );
        // apply mutates synchronously in the installed editor. Leave a valid
        // caret before awaiting its completion, even if Find closes meanwhile.
        // A query/selection changed by an apply listener owns its newer caret.
        if (selectNext &&
            _hasOwnedSelection &&
            revision == _revision &&
            navigation == _navigationRevision) {
          _ownedSelection = transaction.afterSelection;
          _origin = _ownedSelection?.start ?? _origin;
          unawaited(
            editorState.updateSelectionWithReason(
              _ownedSelection,
              reason: SelectionUpdateReason.searchHighlight,
              customSelectionType: SelectionType.inline,
              extraInfo: {
                selectionExtraInfoDisableToolbar: true,
                selectionExtraInfoDoNotAttachTextService: true,
              },
            ),
          );
        } else {
          selectNext = false;
        }
        modelRevision = _modelRevision;
        await applied;
      }
      if (isActive && revision == _revision) {
        // Applying and awaiting can both yield to a newer selection or model
        // edit. Refresh the marks, but never restore Find's old caret then.
        _refresh(
          select: selectNext &&
              _hasOwnedSelection &&
              navigation == _navigationRevision &&
              modelRevision == _modelRevision,
          anchor: all ? null : next,
        );
      }
      return hasChanges;
    } finally {
      _busy = false;
      if (isActive) {
        notifyListeners();
      }
    }
  }

  void _refresh({
    bool select = false,
    Position? anchor,
    bool refreshReferences = false,
  }) {
    if (!isActive) {
      return;
    }
    if (readOnlyProjection) {
      _refreshProjection();
      return;
    }
    final current = _current;
    final keepCurrent = anchor == null && current != null;
    anchor ??= current == null
        ? editorState.selection?.normalized.start
        : current.isWritable
            ? Position(path: current.node!.path, offset: current.match.start)
            : null;
    RegExp? pattern;
    _invalidPattern = false;
    try {
      pattern = buildFindPattern(_query, _options);
    } on FormatException {
      _invalidPattern = true;
    }
    final nodes = _readDocument();
    final roots = <DocumentFindAnchoredReference>[];
    for (final node in nodes) {
      for (final reference in documentFindReferences(node)) {
        roots.add(DocumentFindAnchoredReference(node, reference));
        if (roots.length > limits.maxViews) break;
      }
      if (roots.length > limits.maxViews) break;
    }
    _references?.update(
      roots,
      enabled: pattern != null,
      force: refreshReferences,
      queryRevision: _revision,
    );
    final byNode = <Node, List<DocumentFindExternalText>>{};
    for (final part
        in _references?.texts ?? const <DocumentFindExternalText>[]) {
      byNode.putIfAbsent(part.node, () => []).add(part);
    }
    final title = _title?.text ?? currentView?.call()?.name ?? '';
    _localTruncated = false;
    _localUnavailable =
        pattern != null && roots.isNotEmpty && _references == null ? 1 : 0;
    final results = <DocumentFindResult>[];
    var readableMatches = 0;
    Iterable<RegExpMatch> readableMatchesIn(String text, RegExp pattern) sync* {
      for (final match in pattern.allMatches(text)) {
        if (match.end <= match.start) continue;
        if (readableMatches >= limits.maxEntries) {
          _localTruncated = true;
          break;
        }
        readableMatches++;
        yield match;
      }
    }

    if (pattern != null) {
      final safeTitle = looksSealed(title.trimLeft()) ? '' : title;
      if (safeTitle != title) _localUnavailable++;
      for (final match in matchesOfPattern(safeTitle, pattern)) {
        results.add(DocumentFindResult.title(match));
      }
      for (final node in nodes) {
        final text = node.delta?.toPlainText() ?? '';
        final sealed = looksSealed(text.trimLeft());
        if (sealed) _localUnavailable++;
        for (final match in matchesOfPattern(
          sealed || node.type == 'encrypted_block' ? '' : text,
          pattern,
        )) {
          results.add(DocumentFindResult(node, match));
        }
        final local = documentFindNodeContent(node, limits);
        _localTruncated = _localTruncated || local.truncated;
        if (local.unavailable) _localUnavailable++;
        for (final part in local.texts) {
          for (final match in readableMatchesIn(part.text, pattern)) {
            results.add(
              DocumentFindResult.embedded(
                node,
                match,
                sourceId: part.id,
                location: part.location,
              ),
            );
          }
        }
        final sheet = documentFindSpreadsheetContent(
          node,
          limits,
          liveData: _sheets[node]?.controller.data,
        );
        _localTruncated = _localTruncated || sheet.truncated;
        if (sheet.unavailable) _localUnavailable++;
        for (final part in sheet.texts) {
          for (final match in readableMatchesIn(part.text, pattern)) {
            results.add(
              DocumentFindResult.embedded(
                node,
                match,
                sourceId: part.id,
                location: 'Spreadsheet · ${part.location}',
              ),
            );
          }
        }
        for (final part in byNode[node] ?? const <DocumentFindExternalText>[]) {
          for (final match in readableMatchesIn(part.part.text, pattern)) {
            results.add(
              DocumentFindResult.embedded(
                node,
                match,
                sourceId: part.part.id,
                viewId: part.viewId,
                location: part.part.location,
              ),
            );
          }
        }
      }
    }
    final revealLoaded = _waitingToReveal &&
        _matches.isEmpty &&
        results.isNotEmpty &&
        _asyncNavigation == _navigationRevision &&
        editorState.selection == _asyncSelection;
    _matches = List<DocumentFindResult>.unmodifiable([
      ...results,
    ]);
    final same = keepCurrent
        ? _matches.indexWhere((result) => result.sameLocation(current))
        : -1;
    _selectedIndex = _matches.isEmpty
        ? -1
        : same >= 0
            ? same
            : _indexFrom(anchor);
    if (_matches.isNotEmpty) _waitingToReveal = false;
    _publish(select: select || revealLoaded);
  }

  void _refreshProjection() {
    RegExp? pattern;
    _invalidPattern = false;
    try {
      pattern = buildFindPattern(_query, _options);
    } on FormatException {
      _invalidPattern = true;
    }
    final results = <DocumentFindResult>[];
    var bytes = 0;
    _localTruncated = false;
    for (final node in pattern == null ? const <Node>[] : _readDocument()) {
      if (pattern == null) break;
      final context = node.context;
      final text = _watches[node]?._text;
      if (context == null ||
          !context.mounted ||
          text == null ||
          node.type == 'encrypted_block' ||
          looksSealed(text.trimLeft())) {
        continue;
      }
      if (text.length > limits.maxBytes ||
          (bytes += utf8.encode(text).length) > limits.maxBytes) {
        _localTruncated = true;
        break;
      }
      for (final match in matchesOfPattern(text, pattern)) {
        if (results.length == limits.maxEntries) {
          _localTruncated = true;
          break;
        }
        results.add(DocumentFindResult(node, match));
      }
      if (_localTruncated) break;
    }
    if (_projectionRevision == _revision &&
        _projectionModelRevision == _modelRevision &&
        results.length == _matches.length &&
        List.generate(
          results.length,
          (index) => results[index].sameLocation(_matches[index]),
        ).every((same) => same)) {
      return;
    }
    _projectionRevision = _revision;
    _projectionModelRevision = _modelRevision;
    _matches = List.unmodifiable(results);
    _selectedIndex = results.isEmpty ? -1 : 0;
    notifyListeners();
  }

  int _indexFrom(Position? anchor) {
    if (anchor != null) {
      for (var index = 0; index < _matches.length; index++) {
        final result = _matches[index];
        final path = result.path;
        if (path == null) continue;
        final order = _comparePaths(path, anchor.path);
        if (order > 0 || (order == 0 && result.match.end > anchor.offset)) {
          return index;
        }
      }
    }
    return 0;
  }

  void _publish({bool select = false}) {
    if (!isActive) {
      return;
    }
    if (readOnlyProjection) {
      notifyListeners();
      return;
    }
    final writable = _matches.where((result) => result.isWritable).toList();
    final titles =
        _matches.where((result) => result.kind == DocumentFindResultKind.title);
    DocumentSearchHighlight.instance.update(
      editorState,
      [
        for (final result in writable)
          (
            path: result.path!,
            start: result.match.start,
            end: result.match.end
          ),
      ],
      _current == null ? -1 : writable.indexOf(_current!),
      owner: this,
      titleText: _title?.text ?? currentView?.call()?.name ?? '',
      titleMatches: [
        for (final result in titles)
          TextRange(start: result.match.start, end: result.match.end),
      ],
      currentTitleMatch: _current?.kind == DocumentFindResultKind.title
          ? TextRange(start: _current!.match.start, end: _current!.match.end)
          : null,
    );
    if (_matches.isEmpty) {
      _clearOwnedSelection();
    }
    if (select) {
      _selectCurrent();
    }
    if (isActive) {
      notifyListeners();
    }
  }

  void _selectCurrent() {
    final result = _current;
    if (!isActive || result == null) {
      return;
    }
    if (!result.isWritable) {
      _clearOwnedSelection();
      final navigation = ++_navigationRevision;
      if (result.kind == DocumentFindResultKind.title) {
        // The native service targets the actual header list item, above block 0.
        editorState.scrollService?.jumpToTop();
      } else {
        final path = result.path!;
        if (path.isEmpty ||
            !identical(editorState.getNodeAtPath(path), result.node)) {
          return;
        }
        editorState.scrollService
            ?.jumpTo(path.first + (editorState.showHeader ? 1 : 0));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isActive ||
            navigation != _navigationRevision ||
            _current?.sameLocation(result) != true) {
          return;
        }
        if (result.kind == DocumentFindResultKind.title) {
          _title?.reveal(avoid: titleObstruction?.call());
        } else {
          final context = result.node?.context;
          if (context != null && context.mounted) {
            unawaited(Scrollable.ensureVisible(context, alignment: 0.25));
          }
        }
      });
      return;
    }
    final path = result.path!;
    if (path.isEmpty) return;
    if (!identical(editorState.getNodeAtPath(path), result.node) ||
        result.node!.delta?.toPlainText() != result.match.input) {
      _queueRefresh();
      return;
    }
    final navigation = ++_navigationRevision;
    final modelRevision = _modelRevision;
    editorState.scrollService
        ?.jumpTo(path.first + (editorState.showHeader ? 1 : 0));
    _ownedSelection = result.selection;
    _origin = _ownedSelection!.start;
    // Do not await: the installed editor's searchHighlight selection future
    // never completes. Its actual selection update is synchronous.
    unawaited(
      editorState.updateSelectionWithReason(
        _ownedSelection,
        reason: SelectionUpdateReason.searchHighlight,
        customSelectionType: SelectionType.inline,
        extraInfo: {
          selectionExtraInfoDisableToolbar: true,
          selectionExtraInfoDoNotAttachTextService: true,
        },
      ),
    );
    // jumpTo mounts the top-level block first. Then reveal the real range,
    // including a deeply nested list/callout/table cell or a long paragraph.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isActive ||
          navigation != _navigationRevision ||
          modelRevision != _modelRevision ||
          !_hasOwnedSelection ||
          editorState.selection != result.selection) {
        return;
      }
      // The installed shrink-wrap renderer owns a SingleChildScrollView but
      // does not attach EditorScrollController.scrollController to it.
      // Resolve the mounted node's real viewport instead of animating that
      // unattached controller (for example in a dashboard's read-only editor).
      final nodeContext = result.node?.key.currentContext;
      final nativeScrollable = nodeContext != null &&
              nodeContext.mounted &&
              nodeContext
                      .findAncestorWidgetOfExactType<AppFlowyEditor>()
                      ?.shrinkWrap ==
                  true
          ? Scrollable.maybeOf(nodeContext, axis: Axis.vertical)
          : null;
      final viewport = nativeScrollable == null
          ? editorState.renderBox
          : nativeScrollable.context.findRenderObject() as RenderBox?;
      final scroll = editorState.scrollService;
      final rects = editorState.selectionRects();
      if (viewport == null ||
          !viewport.attached ||
          !viewport.hasSize ||
          (scroll == null && nativeScrollable == null) ||
          rects.isEmpty) {
        return;
      }
      final top = viewport.localToGlobal(Offset.zero).dy + 8;
      final bottom = top + viewport.size.height - 16;
      final rect = rects.first;
      final adjustment = rect.top < top
          ? rect.top - top
          : rect.bottom > bottom
              ? rect.bottom - bottom
              : 0.0;
      if (adjustment != 0) {
        if (nativeScrollable != null) {
          final position = nativeScrollable.position;
          position.jumpTo(
            (position.pixels + adjustment)
                .clamp(position.minScrollExtent, position.maxScrollExtent),
          );
        } else {
          scroll!.scrollTo(scroll.dy + adjustment, duration: Duration.zero);
        }
      }
    });
  }

  List<Node> _readDocument() {
    if (readOnlyProjection && _projectionNodes != null) {
      return _projectionNodes!;
    }
    final nodes = <Node>[];
    void visit(Node node) {
      if (readOnlyProjection && nodes.length >= limits.maxEntries) return;
      nodes.add(node);
      if (node.type == 'encrypted_block') return;
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(editorState.document.root);
    final current = nodes.toSet();
    for (final node in _watches.keys.toList()) {
      if (!current.contains(node)) {
        node.removeListener(_watches.remove(node)!.onChanged);
      }
    }
    for (final node in nodes) {
      final existing = _watches[node];
      if (existing != null) {
        existing.capture();
        continue;
      }
      late final _FindNodeWatch watch;
      watch = _FindNodeWatch(
        node,
        () {
          if (!_disposed && !editorState.isDisposed && watch.capture()) {
            _projectionNodes = null;
            _modelRevision++;
            _waitingToReveal = false;
            _queueRefresh();
          }
        },
        projection: readOnlyProjection,
      );
      _watches[node] = watch;
      node.addListener(watch.onChanged);
    }
    for (final node in _sheets.keys.toList()) {
      if (!current.contains(node)) _sheets.remove(node)!.detach();
    }
    for (final node in nodes
        .where((node) => !readOnlyProjection && node.type == 'spreadsheet')) {
      final controller = _mountedSheet(node);
      if (identical(_sheets[node]?.controller, controller)) continue;
      _sheets.remove(node)?.detach();
      if (controller != null) {
        _sheets[node] = _FindSheetWatch(controller, () {
          _modelRevision++;
          _waitingToReveal = false;
          _queueRefresh();
        });
      }
    }
    if (readOnlyProjection) _projectionNodes = nodes;
    return nodes;
  }

  void _titleChanged() {
    if (_disposed) return;
    _revision++;
    _waitingToReveal = false;
    if (!isActive) {
      _references?.update(const [], enabled: false);
      _matches = const [];
      _selectedIndex = -1;
      DocumentSearchHighlight.instance
          .clear(editorState, owner: this, deferNotification: true);
      notifyListeners();
      return;
    }
    _queueRefresh();
  }

  void _queueRefresh() {
    if (_refreshQueued) {
      return;
    }
    _refreshQueued = true;
    scheduleMicrotask(() {
      _refreshQueued = false;
      if (isActive) {
        // Refresh counts/marks without moving a caret changed by an edit.
        _refresh();
      }
    });
  }

  void _referencesChanged() {
    // Clear protected external snippets synchronously, not in the coalesced
    // model refresh. Local body/title results keep their existing ownership.
    if (_references?.texts.isEmpty == true &&
        _matches.any((hit) => hit.viewId != null)) {
      final previous = _current;
      _matches = List.unmodifiable(_matches.where((hit) => hit.viewId == null));
      _selectedIndex = _matches.isEmpty ? -1 : 0;
      if (previous != null) {
        final same = _matches.indexOf(previous);
        if (same >= 0) _selectedIndex = same;
      }
      notifyListeners();
    }
    _queueRefresh();
  }

  void _permissionsChanged() {
    _revision++;
    if (isActive) {
      notifyListeners();
    }
  }

  void _clearOwnedSelection() {
    final hadOwnedSelection = _ownedSelection != null;
    if (!editorState.isDisposed &&
        _ownedSelection != null &&
        editorState.selectionUpdateReason ==
            SelectionUpdateReason.searchHighlight &&
        editorState.selection == _ownedSelection) {
      editorState.selection = null;
    }
    _ownedSelection = null;
    // A loading reference index can publish several empty snapshots. Those
    // are not navigation and must not cancel the first async match's reveal.
    if (hadOwnedSelection) _navigationRevision++;
  }

  void _editorDisposed() {
    _detach();
    _matches = const [];
    _selectedIndex = -1;
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _detach() {
    _revision++;
    _projectionNodes = null;
    _navigationRevision++;
    _title?.removeListener(_titleChanged);
    unawaited(_viewSubscription?.cancel());
    _viewSubscription = null;
    _references
      ?..removeListener(_referencesChanged)
      ..dispose();
    _references = null;
    for (final sheet in _sheets.values) {
      sheet.detach();
    }
    _sheets.clear();
    for (final watch in _watches.values) {
      watch.node.removeListener(watch.onChanged);
    }
    _watches.clear();
    editorState.onDispose.removeListener(_editorDisposed);
    editorState.editableNotifier.removeListener(_permissionsChanged);
    if (!readOnlyProjection) {
      DocumentSearchHighlight.instance.clear(
        editorState,
        owner: this,
        deferNotification: true,
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _detach();
    _matches = const [];
    _selectedIndex = -1;
    // Closing Find leaves the found text selected. In particular, teardown
    // must not clear a selection belonging to a new session or document click.
    _ownedSelection = null;
    super.dispose();
  }
}

class _FindNodeWatch {
  _FindNodeWatch(this.node, this.onChanged, {this.projection = false}) {
    capture();
  }

  final Node node;
  final VoidCallback onChanged;
  final bool projection;
  String? _text;
  String? _sheet;
  Object? _sourceIdentity;
  List<(String, String)> _scalars = const [];
  List<DocumentFindReference> _references = const [];
  List<Node> _children = const [];

  bool capture() {
    final text = node.delta?.toPlainText();
    final children = node.children;
    final references = projection
        ? const <DocumentFindReference>[]
        : documentFindReferences(node).toList();
    final scalars = projection
        ? const <(String, String)>[]
        : documentFindNodeScalars(node).toList();
    final sourceIdentity = documentFindSourceIdentity(node);
    final sheet = !projection && node.type == 'spreadsheet'
        ? jsonEncode(node.attributes['data'])
        : null;
    final changed = text != _text ||
        sourceIdentity != _sourceIdentity ||
        !listEquals(scalars, _scalars) ||
        !listEquals(children, _children) ||
        sheet != _sheet ||
        !listEquals(references, _references);
    _text = text;
    _sheet = sheet;
    _scalars = scalars;
    _sourceIdentity = sourceIdentity;
    _references = references;
    _children = List.of(children);
    return changed;
  }
}

/// Read a mounted native grid's public controller without changing its state,
/// search, draft, selection or renderer. Unmounted sheets use stored attributes.
SpreadsheetController? _mountedSheet(Node node) {
  final context = node.context;
  if (context is! Element || !context.mounted) return null;
  SpreadsheetController? found;
  var remaining = 1024;
  void visit(Element element) {
    if (found != null || --remaining < 0) return;
    final widget = element.widget;
    if (widget is SpreadsheetGrid) {
      found = widget.controller;
    } else {
      element.visitChildElements(visit);
    }
  }

  visit(context);
  return found;
}

class _FindSheetWatch {
  _FindSheetWatch(this.controller, this.changed)
      : _revision = controller.revision {
    controller.addListener(_onChanged);
  }
  final SpreadsheetController controller;
  final VoidCallback changed;
  int _revision;
  void _onChanged() {
    if (_revision == controller.revision) return;
    _revision = controller.revision;
    changed();
  }

  void detach() => controller.removeListener(_onChanged);
}

int _comparePaths(Path a, Path b) {
  for (var index = 0; index < a.length && index < b.length; index++) {
    final order = a[index].compareTo(b[index]);
    if (order != 0) {
      return order;
    }
  }
  return a.length.compareTo(b.length);
}
