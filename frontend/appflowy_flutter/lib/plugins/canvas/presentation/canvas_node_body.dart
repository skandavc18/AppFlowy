import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_view_resolver.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/drawing/drawing_block_component.dart';
import 'package:appflowy/shared/drawing/excalidraw_scene.dart';
import 'package:appflowy/shared/mermaid/mermaid_view.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What a card holds, drawn.
///
/// Nothing here knows about dragging, selection or the camera — the board owns
/// all of that. A body is handed a box and fills it.
class CanvasNodeBody extends StatelessWidget {
  const CanvasNodeBody({
    super.key,
    required this.node,
    required this.palette,
    required this.resolver,
    required this.editable,
    required this.editing,
    required this.onTextChanged,
    required this.onEditingFinished,
    required this.onOpen,
  });

  final CanvasNode node;
  final CanvasPalette palette;
  final CanvasViewResolver resolver;

  /// False on a read-only canvas and inside a collapsed frame.
  final bool editable;

  /// Whether this card's text is open for typing right now.
  final bool editing;

  final ValueChanged<String> onTextChanged;
  final VoidCallback onEditingFinished;

  /// Open the workspace object this card points at.
  final VoidCallback onOpen;

  /// Choose what this card should point at, for a card that points nowhere.

  @override
  Widget build(BuildContext context) {
    switch (node.kind) {
      case CanvasNodeKind.text:
        return _CanvasTextBody(
          node: node,
          palette: palette,
          editable: editable,
          editing: editing,
          onChanged: onTextChanged,
          onFinished: onEditingFinished,
        );
      case CanvasNodeKind.code:
        return _CanvasCodeBody(
          node: node,
          palette: palette,
          editable: editable,
          editing: editing,
          onChanged: onTextChanged,
          onFinished: onEditingFinished,
        );
      case CanvasNodeKind.diagram:
        return _CanvasDiagramBody(
          node: node,
          palette: palette,
          editable: editable,
          editing: editing,
          onChanged: onTextChanged,
          onFinished: onEditingFinished,
        );
      case CanvasNodeKind.image:
        return _CanvasImageBody(node: node, palette: palette);
      case CanvasNodeKind.web:
      case CanvasNodeKind.bookmark:
        return _CanvasLinkBody(
          node: node,
          palette: palette,
          onOpen: onOpen,
        );
      case CanvasNodeKind.page:
      case CanvasNodeKind.database:
      case CanvasNodeKind.file:
      case CanvasNodeKind.canvas:
        return _CanvasReferenceBody(
          node: node,
          palette: palette,
          resolver: resolver,
          onOpen: onOpen,
        );
    }
  }
}

/// A text card. The whole point of the canvas is that this is one double click
/// away, so it opens for typing as soon as it is made.
class _CanvasTextBody extends StatefulWidget {
  const _CanvasTextBody({
    required this.node,
    required this.palette,
    required this.editable,
    required this.editing,
    required this.onChanged,
    required this.onFinished,
  });

  final CanvasNode node;
  final CanvasPalette palette;
  final bool editable;
  final bool editing;
  final ValueChanged<String> onChanged;
  final VoidCallback onFinished;

  @override
  State<_CanvasTextBody> createState() => _CanvasTextBodyState();
}

class _CanvasTextBodyState extends State<_CanvasTextBody> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.node.text);
  final FocusNode _focus = FocusNode(debugLabel: 'canvas_text_card');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    if (widget.editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claimFocus());
    }
  }

  @override
  void didUpdateWidget(covariant _CanvasTextBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Never overwrite what somebody is in the middle of typing; adopt only
    // when the change came from elsewhere (an undo, a collaborator).
    if (!widget.editing && widget.node.text != _controller.text) {
      _controller.text = widget.node.text;
    }
    if (widget.editing && !oldWidget.editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claimFocus());
    }
  }

  void _claimFocus() {
    if (mounted && !_focus.hasFocus) {
      _focus.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus && widget.editing) {
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final style = TextStyle(
      fontSize: 14,
      height: 1.45,
      color: palette.textPrimary,
      letterSpacing: -0.05,
    );

    if (!widget.editing) {
      final text = widget.node.text.trim();
      return Align(
        alignment: Alignment.topLeft,
        child: text.isEmpty
            ? Text(
                LocaleKeys.canvas_card_textHint.tr(),
                style: style.copyWith(color: palette.textMuted),
              )
            : Text(text, style: style),
      );
    }

    // The editing keys have to be restated right around the field: on a canvas
    // the surface above it binds Delete, Escape and the arrows for itself.
    return TextEntryShortcuts(
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        maxLines: null,
        expands: true,
        readOnly: !widget.editable,
        textAlignVertical: TextAlignVertical.top,
        style: style,
        cursorColor: palette.accent,
        cursorWidth: 1.6,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          isCollapsed: true,
          filled: false,
          hoverColor: Colors.transparent,
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          hintText: LocaleKeys.canvas_card_textHint.tr(),
          hintStyle: style.copyWith(color: palette.textMuted),
        ),
      ),
    );
  }
}

/// A code card: highlighted when it is being read, plain when it is being
/// written, because a highlighter running on every keystroke is what makes a
/// hand-rolled code field feel slow.
class _CanvasCodeBody extends StatefulWidget {
  const _CanvasCodeBody({
    required this.node,
    required this.palette,
    required this.editable,
    required this.editing,
    required this.onChanged,
    required this.onFinished,
  });

  final CanvasNode node;
  final CanvasPalette palette;
  final bool editable;
  final bool editing;
  final ValueChanged<String> onChanged;
  final VoidCallback onFinished;

  @override
  State<_CanvasCodeBody> createState() => _CanvasCodeBodyState();
}

class _CanvasCodeBodyState extends State<_CanvasCodeBody> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.node.text);
  final FocusNode _focus = FocusNode(debugLabel: 'canvas_code_card');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _CanvasCodeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.editing && widget.node.text != _controller.text) {
      _controller.text = widget.node.text;
    }
    if (widget.editing && !oldWidget.editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focus.hasFocus) {
          _focus.requestFocus();
        }
      });
    }
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus && widget.editing) {
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final language = widget.node.stringData(canvasCodeLanguageKey) ?? 'text';
    final style = TextStyle(
      fontFamily: 'RobotoMono',
      fontFamilyFallback: const ['JetBrains Mono', 'Consolas', 'monospace'],
      fontSize: 12.5,
      height: 1.5,
      color: palette.textPrimary,
    );

    final header = Row(
      children: [
        Text(
          language,
          style:
              canvasLabelStyle(palette, size: 10.5, color: palette.textMuted),
        ),
      ],
    );

    final body = widget.editing
        ? TextEntryShortcuts(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              maxLines: null,
              expands: true,
              readOnly: !widget.editable,
              textAlignVertical: TextAlignVertical.top,
              style: style,
              cursorColor: palette.accent,
              onChanged: widget.onChanged,
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                hoverColor: Colors.transparent,
                border: InputBorder.none,
              ),
            ),
          )
        : SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: RichText(
                text: buildSyntaxHighlightedTextSpan(
                  code: widget.node.text,
                  language: language,
                  brightness:
                      palette.isDark ? Brightness.dark : Brightness.light,
                  style: style,
                  isPaper: palette.isPaper,
                ),
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: CanvasMetrics.space1),
        Expanded(child: body),
      ],
    );
  }
}

/// A drawn figure, of either sort.
///
/// Mermaid renders natively — there is no browser anywhere in this path — and
/// a hand-drawn scene is painted from the same model the drawing block uses,
/// so neither one costs a platform view on the canvas.
class _CanvasDiagramBody extends StatelessWidget {
  const _CanvasDiagramBody({
    required this.node,
    required this.palette,
    required this.editable,
    required this.editing,
    required this.onChanged,
    required this.onFinished,
  });

  final CanvasNode node;
  final CanvasPalette palette;
  final bool editable;
  final bool editing;
  final ValueChanged<String> onChanged;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    switch (node.diagramKind) {
      case null:
        return _CanvasPlaceholder(
          palette: palette,
          icon: Icons.account_tree_rounded,
          label: LocaleKeys.canvas_diagram_choose.tr(),
        );
      case CanvasDiagramKind.drawing:
        final scene = DrawScene.decode(node.text);
        if (scene == null || scene.isEmpty) {
          return _CanvasPlaceholder(
            palette: palette,
            icon: Icons.draw_rounded,
            label: LocaleKeys.canvas_diagram_drawingEmpty.tr(),
          );
        }
        return DrawScenePreview(
          scene: scene,
          padding: const EdgeInsets.all(2),
        );
      case CanvasDiagramKind.mermaid:
        if (editing) {
          return _CanvasSourceField(
            node: node,
            palette: palette,
            editable: editable,
            onChanged: onChanged,
            onFinished: onFinished,
            hint: LocaleKeys.canvas_diagram_mermaidHint.tr(),
          );
        }
        final source = node.text.trim();
        if (source.isEmpty) {
          return _CanvasPlaceholder(
            palette: palette,
            icon: Icons.account_tree_rounded,
            label: LocaleKeys.canvas_diagram_mermaidHint.tr(),
          );
        }
        return MermaidView(
          render: renderMermaid(context, source),
          interactive: false,
          padding: const EdgeInsets.all(4),
        );
    }
  }
}

/// A plain monospaced field for the text a diagram is written as.
class _CanvasSourceField extends StatefulWidget {
  const _CanvasSourceField({
    required this.node,
    required this.palette,
    required this.editable,
    required this.onChanged,
    required this.onFinished,
    required this.hint,
  });

  final CanvasNode node;
  final CanvasPalette palette;
  final bool editable;
  final ValueChanged<String> onChanged;
  final VoidCallback onFinished;
  final String hint;

  @override
  State<_CanvasSourceField> createState() => _CanvasSourceFieldState();
}

class _CanvasSourceFieldState extends State<_CanvasSourceField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.node.text);
  final FocusNode _focus = FocusNode(debugLabel: 'canvas_diagram_source');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) {
        _focus.requestFocus();
      }
    });
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final style = TextStyle(
      fontFamily: 'RobotoMono',
      fontFamilyFallback: const ['JetBrains Mono', 'Consolas', 'monospace'],
      fontSize: 12.5,
      height: 1.5,
      color: palette.textPrimary,
    );
    return TextEntryShortcuts(
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        maxLines: null,
        expands: true,
        readOnly: !widget.editable,
        textAlignVertical: TextAlignVertical.top,
        style: style,
        cursorColor: palette.accent,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          isCollapsed: true,
          filled: false,
          hoverColor: Colors.transparent,
          border: InputBorder.none,
          hintText: widget.hint,
          hintStyle: style.copyWith(color: palette.textMuted),
        ),
      ),
    );
  }
}

class _CanvasImageBody extends StatelessWidget {
  const _CanvasImageBody({
    required this.node,
    required this.palette,
  });

  final CanvasNode node;
  final CanvasPalette palette;

  @override
  Widget build(BuildContext context) {
    final source = node.url.trim();
    if (source.isEmpty) {
      return _CanvasPlaceholder(
        palette: palette,
        icon: Icons.image_rounded,
        label: LocaleKeys.canvas_image_choose.tr(),
      );
    }
    final remote =
        source.startsWith('http://') || source.startsWith('https://');
    Widget broken() => _CanvasPlaceholder(
          palette: palette,
          icon: Icons.broken_image_rounded,
          label: LocaleKeys.canvas_card_missing.tr(),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(CanvasMetrics.cardRadius - 4),
      // `contain`, so the whole picture is visible. The card is shaped to the
      // picture when it is chosen, and can be resized by hand afterwards —
      // cropping the content to fit the box is never what was meant.
      child: remote
          ? Image.network(
              source,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => broken(),
            )
          : Image.file(
              File(source),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => broken(),
            ),
    );
  }
}

/// A saved link or a web page.
///
/// Deliberately NOT a live web view: churning a platform view inside a surface
/// that is dragged and resized is the documented Windows renderer crash path,
/// and a canvas is nothing but dragging and resizing. The card opens the page
/// in a browser instead, which is what somebody wants from a spatial note
/// anyway.
class _CanvasLinkBody extends StatelessWidget {
  const _CanvasLinkBody({
    required this.node,
    required this.palette,
    required this.onOpen,
  });

  final CanvasNode node;
  final CanvasPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final address = node.url.trim();
    if (address.isEmpty) {
      return _CanvasPlaceholder(
        palette: palette,
        icon: Icons.link_rounded,
        label: LocaleKeys.canvas_card_addUrl.tr(),
      );
    }

    final uri = Uri.tryParse(address);
    final host = uri?.host ?? address;
    final title = node.title.trim().isNotEmpty ? node.title.trim() : host;
    final preview = node.stringData('preview');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview != null)
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                preview,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          )
        else
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                node.text.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: canvasLabelStyle(palette, size: 12.5),
              ),
            ),
          ),
        const SizedBox(height: CanvasMetrics.space2),
        Row(
          children: [
            _Favicon(host: host, palette: palette),
            const SizedBox(width: CanvasMetrics.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: canvasLabelStyle(
                      palette,
                      size: 13,
                      weight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: canvasLabelStyle(
                      palette,
                      size: 11,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A favicon, with the site's initial as a coloured tile while it loads and if
/// it never arrives. A spinner on every card would be worse than no picture.
class _Favicon extends StatelessWidget {
  const _Favicon({required this.host, required this.palette});

  final String host;
  final CanvasPalette palette;

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      var hash = 0;
      for (final unit in host.codeUnits) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }
      final colour = CanvasPalette.accents[hash % CanvasPalette.accents.length];
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.center,
        child: Text(
          host.isEmpty ? '?' : host.substring(0, 1).toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: colour,
          ),
        ),
      );
    }

    if (host.isEmpty) {
      return fallback();
    }
    return SizedBox(
      width: 20,
      height: 20,
      child: Image.network(
        'https://$host/favicon.ico',
        width: 20,
        height: 20,
        errorBuilder: (_, __, ___) => fallback(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback(),
      ),
    );
  }
}

/// A card standing for something that lives in the workspace: a page, a
/// database, a file, another canvas.
class _CanvasReferenceBody extends StatelessWidget {
  const _CanvasReferenceBody({
    required this.node,
    required this.palette,
    required this.resolver,
    required this.onOpen,
  });

  final CanvasNode node;
  final CanvasPalette palette;
  final CanvasViewResolver resolver;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final reference = node.reference;
    if (reference.isEmpty) {
      return _CanvasPlaceholder(
        palette: palette,
        icon: _iconFor(node.kind),
        label: LocaleKeys.canvas_card_chooseObject.tr(),
      );
    }

    resolver.request(reference);
    return ListenableBuilder(
      listenable: resolver,
      builder: (context, _) {
        final view = resolver.peek(reference);
        if (view == null) {
          return resolver.isMissing(reference)
              ? _CanvasPlaceholder(
                  palette: palette,
                  icon: Icons.help_outline_rounded,
                  label: LocaleKeys.canvas_card_missing.tr(),
                )
              : const _CanvasLoading();
        }
        return _CanvasObjectCard(
          view: view,
          node: node,
          palette: palette,
          onOpen: onOpen,
        );
      },
    );
  }
}

class _CanvasObjectCard extends StatelessWidget {
  const _CanvasObjectCard({
    required this.view,
    required this.node,
    required this.palette,
    required this.onOpen,
  });

  final ViewPB view;
  final CanvasNode node;
  final CanvasPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final title = view.name.trim().isEmpty
        ? LocaleKeys.canvas_node_untitled.tr()
        : view.name.trim();
    final subtitle = _subtitleFor(node.kind, view);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Center(
                child: view.isWorkspaceItem
                    ? WorkspaceItemIcon.fromView(view: view)
                    : Icon(
                        _iconFor(node.kind),
                        size: 18,
                        color: palette.accentAt(node.color),
                      ),
              ),
            ),
            const SizedBox(width: CanvasMetrics.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: canvasLabelStyle(
                      palette,
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: canvasLabelStyle(
                        palette,
                        size: 11,
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (node.text.trim().isNotEmpty) ...[
          const SizedBox(height: CanvasMetrics.space2),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                node.text.trim(),
                overflow: TextOverflow.fade,
                style: canvasLabelStyle(palette, size: 12.5),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _subtitleFor(CanvasNodeKind kind, ViewPB view) {
    switch (kind) {
      case CanvasNodeKind.canvas:
        return LocaleKeys.canvas_name.tr();
      case CanvasNodeKind.database:
        return switch (view.layout) {
          ViewLayoutPB.Grid => LocaleKeys.grid_menuName.tr(),
          ViewLayoutPB.Board => LocaleKeys.board_menuName.tr(),
          ViewLayoutPB.Calendar => LocaleKeys.calendar_menuName.tr(),
          _ => LocaleKeys.canvas_node_database.tr(),
        };
      case CanvasNodeKind.file:
        final extension = view.name.contains('.')
            ? view.name.split('.').last.toUpperCase()
            : '';
        return extension.isEmpty ? LocaleKeys.canvas_node_file.tr() : extension;
      case CanvasNodeKind.page:
      case CanvasNodeKind.text:
      case CanvasNodeKind.web:
      case CanvasNodeKind.bookmark:
      case CanvasNodeKind.image:
      case CanvasNodeKind.code:
      case CanvasNodeKind.diagram:
        return '';
    }
  }
}

class _CanvasLoading extends StatelessWidget {
  const _CanvasLoading();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// What a card shows before it has been told what it holds.
///
/// It draws an affordance but never takes the pointer: the card's own gesture
/// layer covers the whole body, so a tap here would never arrive. Clicking an
/// unconfigured card is handled by the board.
class _CanvasPlaceholder extends StatelessWidget {
  const _CanvasPlaceholder({
    required this.palette,
    required this.icon,
    required this.label,
  });

  final CanvasPalette palette;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: palette.textMuted),
          const SizedBox(height: CanvasMetrics.space1),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: canvasLabelStyle(
                palette,
                size: 11.5,
                color: palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(CanvasNodeKind kind) => switch (kind) {
      CanvasNodeKind.text => Icons.notes_rounded,
      CanvasNodeKind.page => Icons.description_rounded,
      CanvasNodeKind.database => Icons.table_chart_rounded,
      CanvasNodeKind.file => Icons.insert_drive_file_rounded,
      CanvasNodeKind.web => Icons.public_rounded,
      CanvasNodeKind.canvas => Icons.dashboard_customize_rounded,
      CanvasNodeKind.bookmark => Icons.bookmark_rounded,
      CanvasNodeKind.image => Icons.image_rounded,
      CanvasNodeKind.code => Icons.code_rounded,
      CanvasNodeKind.diagram => Icons.account_tree_rounded,
    };

/// The glyph and the words a card kind is known by, shared by the toolbar, the
/// add menu and the "change type" menu so a kind cannot be named two ways.
IconData canvasNodeIcon(CanvasNodeKind kind) => _iconFor(kind);

String canvasNodeLabel(CanvasNodeKind kind) => switch (kind) {
      CanvasNodeKind.text => LocaleKeys.canvas_node_text.tr(),
      CanvasNodeKind.page => LocaleKeys.canvas_node_page.tr(),
      CanvasNodeKind.database => LocaleKeys.canvas_node_database.tr(),
      CanvasNodeKind.file => LocaleKeys.canvas_node_file.tr(),
      CanvasNodeKind.web => LocaleKeys.canvas_node_web.tr(),
      CanvasNodeKind.canvas => LocaleKeys.canvas_node_canvas.tr(),
      CanvasNodeKind.bookmark => LocaleKeys.canvas_node_bookmark.tr(),
      CanvasNodeKind.image => LocaleKeys.canvas_node_image.tr(),
      CanvasNodeKind.code => LocaleKeys.canvas_node_code.tr(),
      CanvasNodeKind.diagram => LocaleKeys.canvas_node_diagram.tr(),
    };

/// Which card kind an address or a workspace object should become.
CanvasNodeKind canvasKindForUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return CanvasNodeKind.text;
  }
  final lower = trimmed.toLowerCase();
  if (imgExtensionRegex.hasMatch(lower)) {
    return CanvasNodeKind.image;
  }
  return CanvasNodeKind.bookmark;
}
