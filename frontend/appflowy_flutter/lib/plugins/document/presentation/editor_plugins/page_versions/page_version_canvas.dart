import 'dart:async';

import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

/// A remembered state of a page, drawn as the page itself.
///
/// A history built out of plain text cannot show what a page held — a picture,
/// a table, an embedded database all read as nothing — so the stored document
/// is rendered read only, and scaled down when it is only a thumbnail.
///
/// ⚠️ It must be given a BOUNDED height. `AppFlowyEditor`'s build root is an
/// `Overlay`, which throws when it is laid out at unbounded height.
class PageVersionCanvas extends StatefulWidget {
  const PageVersionCanvas({
    super.key,
    required this.viewId,
    required this.versionId,
    this.scale = 0.34,
    this.padding = EdgeInsets.zero,
    this.interactive = false,
    this.title = '',
    this.content,
    this.placeholder,
  });

  final String viewId;
  final String versionId;

  /// The writing to draw, when the caller already has it.
  ///
  /// A row's page is kept inside its table's version rather than under a
  /// version of its own, so there is nothing for the store to look up. It is
  /// the STORED form rather than a parsed document on purpose: the same
  /// version hands out the same object, so a rebuild does not throw the
  /// editor away and build another.
  final Map<String, Object?>? content;

  /// How large the writing is drawn against the surface. A thumbnail is a
  /// third of the page; the popup preview is close to full size.
  final double scale;

  final EdgeInsets padding;

  /// Whether the preview may be scrolled. A thumbnail is a button, so it lets
  /// the pointer through instead.
  final bool interactive;

  /// The page's name, drawn above the writing the way the page draws it.
  final String title;

  final Widget? placeholder;

  /// Whether a page can be rendered as itself here. Mobile block builders read
  /// a page style this surface has no business providing.
  static bool get rendersPages => UniversalPlatform.isDesktopOrWeb;

  @override
  State<PageVersionCanvas> createState() => _PageVersionCanvasState();
}

class _PageVersionCanvasState extends State<PageVersionCanvas> {
  EditorState? _editorState;
  bool _read = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  @override
  void didUpdateWidget(PageVersionCanvas old) {
    super.didUpdateWidget(old);
    if (old.versionId != widget.versionId ||
        old.viewId != widget.viewId ||
        old.content != widget.content) {
      _adopt();
    }
  }

  @override
  void dispose() {
    _request++;
    _release();
    super.dispose();
  }

  void _release() {
    _editorState?.dispose();
    _editorState = null;
  }

  void _adopt() {
    final request = ++_request;
    _release();
    _read = false;

    if (!PageVersionCanvas.rendersPages) {
      _read = true;
      return;
    }

    final given = pageVersionDocumentOf(widget.content);
    if (given != null && given.root.children.isNotEmpty) {
      _read = true;
      _editorState = EditorState(document: given)..editable = false;
      return;
    }

    // Nothing was handed down, or what was held nothing — a version of the
    // page in its own right still has it.
    if (widget.versionId.isEmpty) {
      _read = true;
      return;
    }

    unawaited(
      PageVersionService.instance
          .readVersion(widget.viewId, widget.versionId)
          .then((document) {
        if (!mounted || request != _request) {
          return;
        }
        setState(() {
          _read = true;
          if (document != null && document.root.children.isNotEmpty) {
            _editorState = EditorState(document: document)..editable = false;
          }
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = _editorState;
    if (!_read || editorState == null) {
      return widget.placeholder ?? const SizedBox.shrink();
    }

    final page = FocusScope(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: _buildCanvas(context, editorState),
    );
    final body = widget.interactive ? page : IgnorePointer(child: page);

    // ⚠️ Embedded blocks — a folder, a picture, a file, a page preview — read
    // `DocumentBloc` while they BUILD, for the profile a cloud file cannot be
    // fetched without. A preview lives outside the page's own bloc tree, so
    // the open page's bloc is handed down; without it those blocks paint a red
    // "could not find the correct Provider" band.
    final documentBloc = DocumentBloc.findOpen(widget.viewId);
    return documentBloc == null
        ? body
        : BlocProvider<DocumentBloc>.value(value: documentBloc, child: body);
  }

  Widget _buildCanvas(BuildContext context, EditorState editorState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0 || !width.isFinite || !constraints.hasBoundedHeight) {
          return const SizedBox.shrink();
        }
        final scale = widget.scale.clamp(0.1, 1.0);
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
                  header: widget.title.isEmpty
                      ? null
                      : _Title(name: widget.title, width: canvasWidth),
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

class _Title extends StatelessWidget {
  const _Title({required this.name, required this.width});

  final String name;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        EditorStyleCustomizer.documentPadding.left,
        36,
        EditorStyleCustomizer.documentPadding.right,
        12,
      ),
      child: Text(
        name,
        style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
      ),
    );
  }
}
