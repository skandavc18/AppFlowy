import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/ai_writer_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/callout/callout_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/inline_math_equation/inline_math_equation.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_page_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/toggle/toggle_block_component.dart';
import 'package:appflowy/shared/spell_check/spell_check.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';

/// The blocks whose text is meant to be read by a person.
///
/// Everything else — code, embeds, files, databases, previews — is left alone,
/// which is why the checker walks the document rather than the rendered page.
final Set<String> spellCheckedBlockTypes = {
  ParagraphBlockKeys.type,
  HeadingBlockKeys.type,
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  TodoListBlockKeys.type,
  QuoteBlockKeys.type,
  CalloutBlockKeys.type,
  ToggleListBlockKeys.type,
};

/// Inline attributes that mean "this is not prose".
final Set<String> _opaqueAttributes = {
  AppFlowyRichTextKeys.code,
  AppFlowyRichTextKeys.href,
  AppFlowyRichTextKeys.autoComplete,
  MentionBlockKeys.mention,
  InlineMathEquationKeys.formula,
  AiWriterBlockKeys.suggestion,
};

/// How long the writer has to stop before their words are read.
const Duration spellCheckDebounce = Duration(milliseconds: 400);

/// How many blocks are read before the frame is given back.
const int _blocksPerSlice = 40;

class _BlockIssues {
  const _BlockIssues(this.text, this.issues);

  final String text;
  final List<SpellCheckResult> issues;
}

/// Reads one open page and remembers what is wrong with it.
///
/// The rules it follows: never touch the document, never move the caret, and
/// never do the expensive work — finding replacements — until somebody asks.
class DocumentSpellCheckController extends ChangeNotifier {
  DocumentSpellCheckController({
    required this.editorState,
    required this.viewId,
  });

  final EditorState editorState;
  final String viewId;

  final Map<String, _BlockIssues> _blocks = {};
  final Set<String> _dirty = {};

  StreamSubscription<EditorTransactionValue>? _transactions;
  Timer? _debounce;
  bool _sweepQueued = false;
  bool _running = false;
  bool _disposed = false;

  bool get isEnabled =>
      SpellCheckPageSettings.instance.isEnabledFor(viewId) &&
      SpellCheckService.instance.isReady;

  bool get checksGrammar =>
      isEnabled && SpellCheckSettings.instance.grammarEnabled;

  /// Starts reading. Loading the language and the first pass both happen off
  /// the first frame, so opening a page is not slowed down by either.
  Future<void> start() async {
    _transactions = editorState.transactionStream.listen(_onTransaction);
    SpellCheckSettings.instance.addListener(_onRulesChanged);
    SpellCheckPageSettings.instance.addListener(_onRulesChanged);
    DictionaryService.instance.addListener(_onRulesChanged);
    IgnoreRules.instance.addListener(_onRulesChanged);

    await SpellCheckSettings.instance.ensureLoaded();
    if (_disposed) {
      return;
    }
    if (!SpellCheckPageSettings.instance.isEnabledFor(viewId)) {
      return;
    }
    await SpellCheckService.instance.prepare();
    if (_disposed) {
      return;
    }
    _scheduleSweep();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_transactions?.cancel());
    SpellCheckSettings.instance.removeListener(_onRulesChanged);
    SpellCheckPageSettings.instance.removeListener(_onRulesChanged);
    DictionaryService.instance.removeListener(_onRulesChanged);
    IgnoreRules.instance.removeListener(_onRulesChanged);
    _blocks.clear();
    super.dispose();
  }

  /// What is wrong in one block, in the block's own character offsets.
  List<SpellCheckResult> issuesOf(Node node) =>
      _blocks[node.id]?.issues ?? const [];

  /// The mistake under a caret, if there is one.
  SpellCheckResult? issueAt(Node node, int offset) {
    for (final issue in issuesOf(node)) {
      if (issue.contains(offset)) {
        return issue;
      }
    }
    return null;
  }

  bool get hasIssues => _blocks.values.any((block) => block.issues.isNotEmpty);

  void _onTransaction(EditorTransactionValue event) {
    if (event.$1 != TransactionTime.after || !isEnabled) {
      return;
    }
    for (final operation in event.$2.operations) {
      final node = editorState.getNodeAtPath(operation.path);
      if (node != null) {
        _markDirty(node);
      }
      // A delete leaves nothing at the path, so its neighbour and its parent
      // are read again instead.
      final parent = operation.path.length > 1
          ? editorState.getNodeAtPath(operation.path.sublist(0, operation.path.length - 1))
          : null;
      if (parent != null) {
        _markDirty(parent);
      }
    }
    _scheduleRun();
  }

  void _markDirty(Node node) {
    if (spellCheckedBlockTypes.contains(node.type)) {
      _dirty.add(node.id);
    }
    for (final child in node.children) {
      _markDirty(child);
    }
  }

  /// A change to the dictionary, the settings or the ignore list changes the
  /// answer for the whole page, so everything is read again.
  void _onRulesChanged() {
    if (_disposed) {
      return;
    }
    if (!isEnabled) {
      _clearAll();
      return;
    }
    unawaited(_prepareThenSweep());
  }

  Future<void> _prepareThenSweep() async {
    if (!SpellCheckService.instance.isReady) {
      await SpellCheckService.instance.prepare();
      if (_disposed) {
        return;
      }
    }
    _scheduleSweep();
  }

  void _clearAll() {
    if (_blocks.isEmpty) {
      return;
    }
    final touched = _blocks.keys.toList();
    _blocks.clear();
    _dirty.clear();
    for (final id in touched) {
      _nodeWithId(id)?.notify();
    }
    notifyListeners();
  }

  void _scheduleSweep() {
    _sweepQueued = true;
    _scheduleRun();
  }

  void _scheduleRun() {
    _debounce?.cancel();
    _debounce = Timer(spellCheckDebounce, () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_disposed || _running) {
      return;
    }
    if (!isEnabled) {
      _clearAll();
      return;
    }
    _running = true;
    try {
      final nodes = _sweepQueued
          ? _allTextNodes()
          : [
              for (final id in _dirty)
                if (_nodeWithId(id) case final node?) node,
            ];
      final live = _sweepQueued ? nodes.map((n) => n.id).toSet() : null;
      _sweepQueued = false;
      _dirty.clear();

      if (live != null) {
        // A block that has gone must not keep its marks.
        _blocks.removeWhere((id, _) => !live.contains(id));
      }

      var checked = 0;
      for (final node in nodes) {
        if (_disposed) {
          return;
        }
        _check(node);
        if (++checked % _blocksPerSlice == 0) {
          // Long pages are read a slice at a time so typing never waits.
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (!_disposed) {
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }

  void _check(Node node) {
    final delta = node.delta;
    if (delta == null || !spellCheckedBlockTypes.contains(node.type)) {
      return;
    }
    final text = delta.toPlainText();
    final previous = _blocks[node.id];
    final excluded = _opaqueRanges(delta);

    final issues = <SpellCheckResult>[
      ...SpellCheckService.instance.check(text, excluded: excluded),
      if (checksGrammar)
        ...GrammarCheckService.instance.check(text, excluded: excluded),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final kept = <SpellCheckResult>[];
    for (final issue in issues) {
      if (_isIgnored(issue, node.id)) {
        continue;
      }
      // A spelling and a grammar note over the same words would draw two
      // squiggles; the spelling is the more certain of the two.
      if (kept.any((other) => other.overlaps(issue.start, issue.end))) {
        continue;
      }
      kept.add(issue);
    }

    final changed = previous == null ||
        previous.text != text ||
        !listEquals(previous.issues, kept);
    _blocks[node.id] = _BlockIssues(text, kept);
    if (changed) {
      node.notify();
    }
  }

  bool _isIgnored(SpellCheckResult issue, String blockId) {
    if (IgnoreRules.instance.covers(issue, blockId)) {
      return true;
    }
    if (issue.kind.isSpelling &&
        SpellCheckPageSettings.instance.isIgnoredOnPage(viewId, issue.text)) {
      return true;
    }
    return false;
  }

  List<ExcludedRange> _opaqueRanges(Delta delta) {
    final ranges = <ExcludedRange>[];
    var offset = 0;
    for (final operation in delta) {
      final length = operation.length;
      if (operation is TextInsert) {
        final attributes = operation.attributes;
        if (attributes != null &&
            _opaqueAttributes.any(attributes.containsKey)) {
          ranges.add(ExcludedRange(offset, offset + length));
        }
      }
      offset += length;
    }
    return mergeExcludedRanges(ranges);
  }

  List<Node> _allTextNodes() {
    final nodes = <Node>[];
    void walk(Node node) {
      if (node.delta != null && spellCheckedBlockTypes.contains(node.type)) {
        nodes.add(node);
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final child in editorState.document.root.children) {
      walk(child);
    }
    return nodes;
  }

  Node? _nodeWithId(String id) {
    Node? search(Node node) {
      if (node.id == id) {
        return node;
      }
      for (final child in node.children) {
        final found = search(child);
        if (found != null) {
          return found;
        }
      }
      return null;
    }

    for (final child in editorState.document.root.children) {
      final found = search(child);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Reads one block again straight away, used after a correction is accepted
  /// so the squiggle goes as the word changes.
  void recheck(Node node) {
    if (!isEnabled) {
      return;
    }
    _check(node);
    notifyListeners();
  }
}

/// The controller reading each open page.
///
/// The editor's span decorator is handed a node and a style, never a page, so
/// the controllers are looked up by the editor they belong to.
abstract final class DocumentSpellCheck {
  static final Map<EditorState, DocumentSpellCheckController> _controllers = {};

  static DocumentSpellCheckController? of(EditorState? editorState) =>
      editorState == null ? null : _controllers[editorState];

  static DocumentSpellCheckController attach({
    required EditorState editorState,
    required String viewId,
  }) {
    final existing = _controllers[editorState];
    if (existing != null) {
      return existing;
    }
    final controller = DocumentSpellCheckController(
      editorState: editorState,
      viewId: viewId,
    );
    _controllers[editorState] = controller;
    unawaited(controller.start());
    return controller;
  }

  static void detach(EditorState editorState) =>
      _controllers.remove(editorState)?.dispose();
}
