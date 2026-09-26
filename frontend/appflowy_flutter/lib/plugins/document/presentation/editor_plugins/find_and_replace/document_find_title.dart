import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'document_search_highlight.dart';

/// The existing native title field lends its text/context to Find while mounted.
/// The weak editor key avoids a process-wide cache of document titles.
class DocumentFindTitle extends ChangeNotifier {
  DocumentFindTitle._();
  static final _titles = Expando<DocumentFindTitle>();
  static DocumentFindTitle of(EditorState editor) =>
      _titles[editor] ??= DocumentFindTitle._();

  TextEditingController? _controller;
  BuildContext Function()? _context;
  Object? _owner;
  final _nativeTitleOwners = Set<Object>.identity();
  String? _lastText;
  String? get text =>
      _controller?.text ?? (_nativeTitleOwners.isEmpty ? null : '');

  /// A row's orphan ViewPB.name is not its visible primary-cell title. While
  /// its lazy field is absent, search the body rather than that default name.
  void requireNativeTitle(Object owner) {
    _nativeTitleOwners.add(owner);
    _changed();
  }

  void releaseNativeTitle(Object owner) {
    _nativeTitleOwners.remove(owner);
    _changed();
  }

  void attach(
    TextEditingController controller,
    BuildContext Function() context, {
    Object? owner,
  }) {
    _controller?.removeListener(_changed);
    _controller = controller;
    _context = context;
    _owner = owner;
    controller.addListener(_changed);
    _changed();
  }

  void detach(TextEditingController controller, {Object? owner}) {
    if (!identical(controller, _controller) || !identical(owner, _owner)) {
      return;
    }
    controller.removeListener(_changed);
    _controller = null;
    _context = null;
    _owner = null;
    _changed();
  }

  void _changed() {
    if (text == _lastText) return;
    _lastText = text;
    // A title may mount/dispose while the editor is laying out a lazy header.
    scheduleMicrotask(notifyListeners);
  }

  void reveal({Rect? avoid}) {
    final context = _context?.call();
    if (context != null && context.mounted) {
      var alignment = 0.5;
      final target = context.findRenderObject();
      final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
      if (avoid != null &&
          target is RenderBox &&
          target.hasSize &&
          viewport is RenderBox &&
          viewport.hasSize) {
        final available = viewport.size.height - target.size.height;
        if (available > 0) {
          final top = viewport.localToGlobal(Offset.zero).dy;
          alignment = math
              .max(0.5, (avoid.bottom + 8 - top) / available)
              .clamp(0.0, 1.0);
        }
      }
      unawaited(Scrollable.ensureVisible(context, alignment: alignment));
    }
  }
}

/// Borrows an existing native field without replacing/disposal of its
/// controller or touching text, composing state, selection, focus or saves.
class DocumentFindTitleBinding extends StatefulWidget {
  const DocumentFindTitleBinding({
    super.key,
    required this.editorState,
    required this.controller,
    required this.child,
  });

  final EditorState? editorState;
  final TextEditingController controller;
  final Widget child;

  @override
  State<DocumentFindTitleBinding> createState() =>
      _DocumentFindTitleBindingState();
}

class _DocumentFindTitleBindingState extends State<DocumentFindTitleBinding> {
  final _fieldKey = GlobalKey();
  RenderEditable? _editable;
  _BorrowedTitlePainter? _painter;
  FocusNode? _focus;
  bool _paintQueued = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final editor = widget.editorState;
    if (editor == null || editor.isDisposed) return;
    DocumentFindTitle.of(editor).attach(
      widget.controller,
      () => context,
      owner: this,
    );
  }

  void _detach(DocumentFindTitleBinding widget) {
    _releasePainter();
    final editor = widget.editorState;
    if (editor != null) {
      DocumentFindTitle.of(editor).detach(widget.controller, owner: this);
    }
  }

  @override
  void didUpdateWidget(covariant DocumentFindTitleBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.editorState, widget.editorState) ||
        !identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget);
      _attach();
    }
  }

  @override
  void dispose() {
    _detach(widget);
    super.dispose();
  }

  void _releasePainter() {
    final editable = _editable;
    final painter = _painter;
    if (editable != null &&
        editable.attached &&
        painter != null &&
        identical(editable.painter, painter)) {
      editable.painter = painter.previous;
    }
    _focus?.removeListener(_queuePainter);
    _focus = null;
    _editable = null;
    _painter = null;
    painter?.dispose();
  }

  void _queuePainter() {
    if (!mounted || _paintQueued) return;
    _paintQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paintQueued = false;
      if (!mounted) return;
      final editor = widget.editorState;
      if (editor == null || editor.isDisposed) {
        _releasePainter();
        return;
      }
      EditableTextState? state;
      void visit(Element element) {
        if (state != null) return;
        if (element is StatefulElement && element.state is EditableTextState) {
          final candidate = element.state as EditableTextState;
          if (identical(candidate.widget.controller, widget.controller)) {
            state = candidate;
          }
        } else {
          element.visitChildElements(visit);
        }
      }

      final field = _fieldKey.currentContext;
      if (field is Element) visit(field);
      final editable = state?.renderEditable;
      if (editable == null || !editable.attached) {
        _releasePainter();
        return;
      }
      if (!identical(_editable, editable) ||
          !identical(editable.painter, _painter)) {
        _releasePainter();
        _editable = editable;
        _painter = _BorrowedTitlePainter(editable.painter);
        editable.painter = _painter;
      }
      if (!identical(_focus, state!.widget.focusNode)) {
        _focus?.removeListener(_queuePainter);
        _focus = state!.widget.focusNode..addListener(_queuePainter);
      }
      final text = widget.controller.text;
      _painter!.update(
        text,
        decorateDocumentTitleWithSearchHighlight(
          context,
          editor,
          text,
          TextSpan(text: text),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          DocumentSearchHighlight.instance,
          widget.controller,
        ]),
        builder: (context, child) {
          _queuePainter();
          return child!;
        },
        child: KeyedSubtree(key: _fieldKey, child: widget.child),
      );
}

/// The public title decorator supplies ranges/colors; the actual EditableText
/// supplies their geometry (wrapping, bidi, scale, padding and scroll offset).
/// Preserve the field's existing painter and built-in selection/caret paints.
/// Painting inside the editable keeps decorations from covering the marks.
class _BorrowedTitlePainter extends RenderEditablePainter {
  _BorrowedTitlePainter(this.previous) {
    previous?.addListener(notifyListeners);
  }

  final RenderEditablePainter? previous;
  TextSpan _span = const TextSpan();
  String _text = '';
  bool _disposed = false;

  void update(String text, TextSpan span) {
    _text = text;
    _span = span;
    notifyListeners();
  }

  @override
  void paint(Canvas canvas, Size size, RenderEditable editable) {
    previous?.paint(canvas, size, editable);
    if (_disposed || !editable.hasSize || editable.plainText != _text) return;
    canvas.save();
    canvas.clipRect(Offset.zero & editable.size);
    var offset = 0;
    void paintSpan(TextSpan part, Color? inherited) {
      final color = part.style?.backgroundColor ?? inherited;
      final end = offset + (part.text?.length ?? 0);
      if (color != null && end > offset) {
        for (final rect in editable.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: end),
        )) {
          canvas.drawRect(rect.toRect(), Paint()..color = color);
        }
      }
      offset = end;
      for (final child in part.children ?? const <InlineSpan>[]) {
        if (child is TextSpan) paintSpan(child, color);
      }
    }

    paintSpan(_span, null);
    canvas.restore();
  }

  @override
  bool shouldRepaint(RenderEditablePainter? oldDelegate) => true;

  @override
  void dispose() {
    _disposed = true;
    previous?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Highlighting is paint-only. In particular it never changes selection or
/// notifies controller listeners (which would schedule a title rename).
class DocumentFindTitleController extends TextEditingController {
  DocumentFindTitleController({required this.editorState, super.text});

  final EditorState editorState;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) =>
      decorateDocumentTitleWithSearchHighlight(
        context,
        editorState,
        text,
        super.buildTextSpan(
          context: context,
          style: style,
          withComposing: withComposing,
        ),
      );
}
