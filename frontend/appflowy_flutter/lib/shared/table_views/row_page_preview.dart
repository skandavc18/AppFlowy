import 'dart:async';

import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

/// The whole of a row's page, kept for as long as the application runs.
///
/// A wall of cards would otherwise ask the backend for the same page every
/// time it scrolled past. Forgotten through [RowPageText.forget], so one
/// signal invalidates the transcript and the page alike.
class RowPageDocument {
  const RowPageDocument._();

  static final Map<String, DocumentDataPB?> _read = {};
  static final Map<String, Future<DocumentDataPB?>> _reading = {};

  static bool knows(String documentId) => _read.containsKey(documentId);

  static DocumentDataPB? peek(String documentId) => _read[documentId];

  static Future<DocumentDataPB?> read(String documentId) {
    if (documentId.isEmpty) {
      return Future.value();
    }
    if (_read.containsKey(documentId)) {
      return Future.value(_read[documentId]);
    }
    return _reading[documentId] ??= _load(documentId);
  }

  static Future<DocumentDataPB?> _load(String documentId) async {
    try {
      final result = await DocumentService().getDocument(
        documentId: documentId,
      );
      final data = result.fold<DocumentDataPB?>((data) => data, (_) => null);
      _read[documentId] = data;
      return data;
    } finally {
      _reading.removeWhere((key, _) => key == documentId);
    }
  }

  /// Drops what was read, without raising a signal of its own — the caller is
  /// already answering [RowPageText.revision].
  static void discard([String? documentId]) {
    if (documentId == null) {
      _read.clear();
    } else {
      _read.remove(documentId);
    }
  }
}

/// A row's own page, rendered the way the page itself is.
///
/// A preview built out of plain text cannot show what a page actually holds —
/// an embedded page, a spreadsheet, a table, a picture all read as nothing.
/// This renders the real document, read only and scaled down, so a card shows
/// the page rather than a transcript of it.
///
/// ⚠️ It must be given a BOUNDED height — an [Expanded], a [SizedBox], or
/// [height] below. The editor sizes itself from its box, and with an unbounded
/// one it draws nothing.
class RowPagePreview extends StatefulWidget {
  const RowPagePreview({
    super.key,
    required this.documentId,
    required this.emptyBuilder,
    required this.textBuilder,
    this.scale = 0.78,
    this.height,
    this.padding = EdgeInsets.zero,
    this.interactive = false,
  });

  final String documentId;

  /// Shown when the page has nothing on it.
  final WidgetBuilder emptyBuilder;

  /// Shown where the page cannot be rendered as itself — on mobile, whose
  /// block configuration needs a page style this surface has no business
  /// providing, and when the document could not be read.
  final Widget Function(BuildContext context, String? text) textBuilder;

  /// How large the writing is drawn against the surface.
  final double scale;

  /// The room a rendered page is given. Null fills the box it is handed, and
  /// the empty and transcript states are never stretched to it.
  final double? height;

  /// The measure the page is set on, inside whatever box it is given.
  final EdgeInsets padding;

  /// Whether the page may be scrolled. A card is opened by tapping it, so a
  /// card's preview must let the pointer through instead.
  final bool interactive;

  /// Whether a page can be rendered as itself here.
  static bool get rendersPages => UniversalPlatform.isDesktopOrWeb;

  @override
  State<RowPagePreview> createState() => _RowPagePreviewState();
}

class _RowPagePreviewState extends State<RowPagePreview> {
  EditorState? _editorState;
  bool _read = false;
  bool _unreadable = false;
  int _request = 0;
  int _revision = RowPageText.revision.value;

  @override
  void initState() {
    super.initState();
    RowPageText.onForget.add(RowPageDocument.discard);
    RowPageText.revision.addListener(_onForgotten);
    _adopt();
  }

  @override
  void didUpdateWidget(RowPagePreview old) {
    super.didUpdateWidget(old);
    if (old.documentId != widget.documentId) {
      _adopt();
    }
  }

  @override
  void dispose() {
    RowPageText.revision.removeListener(_onForgotten);
    _request++;
    _release();
    super.dispose();
  }

  void _release() {
    _editorState?.dispose();
    _editorState = null;
  }

  void _onForgotten() {
    if (!mounted || _revision == RowPageText.revision.value) {
      return;
    }
    _revision = RowPageText.revision.value;
    setState(_adopt);
  }

  void _adopt() {
    final request = ++_request;
    _release();
    _read = false;
    _unreadable = false;

    if (!RowPagePreview.rendersPages || widget.documentId.isEmpty) {
      _read = true;
      _unreadable = true;
      return;
    }

    if (RowPageDocument.knows(widget.documentId)) {
      _take(RowPageDocument.peek(widget.documentId));
      return;
    }

    unawaited(
      RowPageDocument.read(widget.documentId).then((data) {
        if (!mounted || request != _request) {
          return;
        }
        setState(() => _take(data));
      }),
    );
  }

  void _take(DocumentDataPB? data) {
    _read = true;
    final document = data?.toDocument();
    if (document == null) {
      // The page could not be read as a document; the transcript is the only
      // thing left to try.
      _unreadable = true;
      return;
    }
    if (_isBlank(document)) {
      return;
    }
    _editorState = EditorState(document: document)..editable = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_read) {
      return const SizedBox.shrink();
    }

    final editorState = _editorState;
    if (editorState == null) {
      return _unreadable ? _buildTranscript() : widget.emptyBuilder(context);
    }

    final page = FocusScope(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: _buildCanvas(context, editorState),
    );
    final body = widget.interactive ? page : IgnorePointer(child: page);
    final height = widget.height;
    return height == null ? body : SizedBox(height: height, child: body);
  }

  Widget _buildTranscript() {
    return RowPageTextView(
      documentId: widget.documentId,
      builder: (context, text) => (text?.trim().isNotEmpty ?? false)
          ? widget.textBuilder(context, text)
          : widget.emptyBuilder(context),
    );
  }

  Widget _buildCanvas(BuildContext context, EditorState editorState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0 || !width.isFinite || !constraints.hasBoundedHeight) {
          return const SizedBox.shrink();
        }
        final scale = widget.scale.clamp(0.2, 1.0);
        final canvasWidth = width / scale;
        final canvasHeight = constraints.maxHeight / scale;
        final styleCustomizer = EditorStyleCustomizer(
          context: context,
          padding: widget.padding,
          width: canvasWidth,
          editorState: editorState,
        );

        return ClipRect(
          child: FittedBox(
            alignment: Alignment.topLeft,
            fit: BoxFit.fill,
            child: SizedBox(
              width: canvasWidth,
              height: canvasHeight,
              // An embedded database asks its host how wide the page is; a
              // preview is the whole measure, so it takes no gutter.
              child: Provider(
                create: (_) => const DatabasePluginWidgetBuilderSize(
                  horizontalPadding: 0,
                ),
                child: AppFlowyEditor(
                  editorState: editorState,
                  editorStyle: styleCustomizer.style().copyWith(
                        cursorColor: Colors.transparent,
                        cursorWidth: 0,
                      ),
                  blockComponentBuilders: buildBlockComponentBuilders(
                    context: context,
                    editorState: editorState,
                    styleCustomizer: styleCustomizer,
                    editable: false,
                    alwaysDistributeSimpleTableColumnWidths: true,
                  ),
                  contextMenuItems: const [],
                  disableSelectionService: true,
                  disableKeyboardService: true,
                  disableAutoScroll: true,
                  editable: false,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Whether a page carries nothing but empty paragraphs.
bool _isBlank(Document document) {
  final children = document.root.children;
  if (children.isEmpty) {
    return true;
  }
  for (final node in children) {
    if (node.type != ParagraphBlockKeys.type || node.children.isNotEmpty) {
      return false;
    }
    if (node.delta?.toPlainText().trim().isNotEmpty ?? false) {
      return false;
    }
  }
  return true;
}
