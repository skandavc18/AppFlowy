import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart'
    show workspacePhotoRenderer;
import 'package:appflowy/shared/document_viewer/file_action_band.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens one external object with the viewer AppFlowy already has for it.
///
/// This is the rule the whole integration turns on: a OneDrive PDF opens in the
/// PDF viewer, a Box markdown file in the markdown viewer, a Drive picture in
/// the image viewer. There is no separate viewer for any service, because a
/// file is a file once its bytes are on disk.
Future<void> showExternalFile(
  BuildContext context, {
  required ProviderController controller,
  required ProviderNode node,
  List<ProviderNode> siblings = const <ProviderNode>[],
  OcrService? ocrService,
}) =>
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: node.name,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondary) {
        final viewer = _ExternalFileViewer(
          controller: controller,
          node: node,
          siblings: siblings.where((sibling) => !sibling.isFolder).toList(),
          ocrService: ocrService,
        );
        // A modal owns its own Find fallback, including focused header tools.
        return ContextualFindScope(findInControls: true, child: viewer);
      },
      transitionBuilder: (context, animation, secondary, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );

class _ExternalFileViewer extends StatefulWidget {
  const _ExternalFileViewer({
    required this.controller,
    required this.node,
    required this.siblings,
    this.ocrService,
  });

  final ProviderController controller;
  final ProviderNode node;
  final List<ProviderNode> siblings;
  final OcrService? ocrService;

  @override
  State<_ExternalFileViewer> createState() => _ExternalFileViewerState();
}

class _ExternalFileViewerState extends State<_ExternalFileViewer> {
  late ProviderNode node;
  String? path;
  bool loading = true;
  bool failed = false;
  int _generation = 0;
  bool _closing = false;
  ModalRoute<dynamic>? _route;
  StandaloneFileChromeController _chrome = StandaloneFileChromeController();
  Widget? _renderer;
  late bool Function() _canRead;

  @override
  void initState() {
    super.initState();
    node = widget.node;
    unawaited(_fetch());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    // Refresh palette-dependent widgets, not their keys, loaded state or IO.
    _renderer = null;
  }

  @override
  void didUpdateWidget(covariant _ExternalFileViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.node, widget.node)) {
      node = widget.node;
      unawaited(_fetch());
    } else if (oldWidget.ocrService != widget.ocrService) {
      _renderer = null;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _closing = true;
    _chrome.dispose();
    super.dispose();
  }

  bool _isCurrent(
    ProviderController controller,
    ProviderNode requestedNode,
    CollectionSource source,
    int generation,
  ) =>
      mounted &&
      !_closing &&
      _route?.isActive != false &&
      generation == _generation &&
      identical(widget.controller, controller) &&
      identical(node, requestedNode) &&
      identical(controller.source, source);

  Future<void> _fetch() async {
    if (!mounted || _closing) return;
    final controller = widget.controller;
    final requestedNode = node;
    final source = controller.source;
    final generation = ++_generation;
    bool current() => _isCurrent(controller, requestedNode, source, generation);
    _canRead = () => current() && !loading && !failed && path != null;
    setState(() {
      loading = true;
      failed = false;
      path = null;
      _renderer = null;
      // A retired renderer may still have a queued header publication. It
      // must never publish into the next file's chrome, even for the same id.
      _chrome.dispose();
      _chrome = StandaloneFileChromeController();
    });
    String? resolved;
    try {
      resolved = await controller.materialize(requestedNode);
    } catch (_) {
      // Show only the friendly current-file error; exceptions may contain
      // signed provider URLs. Neither expose nor log them from this host.
    }
    if (!current()) return;
    setState(() {
      path = resolved == null || resolved.isEmpty ? null : resolved;
      loading = false;
      failed = path == null;
    });
  }

  int get _index =>
      widget.siblings.indexWhere((sibling) => sibling.id == node.id);

  bool get _hasPrevious => _index > 0;
  bool get _hasNext => _index >= 0 && _index < widget.siblings.length - 1;

  void _step(int delta) {
    if (!mounted || _closing || _route?.isCurrent != true || _index < 0) return;
    final next = _index + delta;
    if (next < 0 || next >= widget.siblings.length) {
      return;
    }
    node = widget.siblings[next];
    unawaited(_fetch());
  }

  void _close() {
    if (!mounted || _closing || _route?.isCurrent != true) return;
    _closing = true;
    ++_generation;
    Navigator.of(context).pop();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || _closing || _route?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isAltPressed ||
        keys.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null ||
        !focused.mounted ||
        focused.widget is EditableText ||
        focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    // This is a bubbling handler, not an ancestor Shortcuts override. Native
    // text-entry shortcuts and renderer-local navigation get first refusal.
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _hasPrevious) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && _hasNext) {
      _step(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).shortestSide < 600 ? 12 : 44,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ColoredBox(
                key: const ValueKey('external-file-canvas'),
                color: palette.background,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Close belongs to this route, outside both the title
                    // sliver and the horizontal toolbar overflow viewport.
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        key: const ValueKey('external-file-close'),
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: _close,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: palette.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: StandaloneFileScope(
                        canvas: palette.background,
                        rendererName: providerFileNameFor(node),
                        displayName: node.name,
                        chrome: _chrome,
                        canEdit: () => false,
                        canRead: _canRead,
                        editable: false,
                        available: _canRead(),
                        child: StandaloneFilePage(
                          key: ObjectKey(_chrome),
                          nativeBodyGestures:
                              node.kind == ProviderNodeKind.image ||
                                  imgExtensionRegex
                                      .hasMatch(providerFileNameFor(node)),
                          header: ValueListenableBuilder<StandaloneFileHeader>(
                            valueListenable: _chrome,
                            builder: (context, controls, _) =>
                                _header(palette, controls),
                          ),
                          // Do not put this inside the chrome builder:
                          // publication must never rebuild its publisher.
                          body: _body(palette),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(
    FolderExplorerPalette palette,
    StandaloneFileHeader controls,
  ) =>
      Padding(
        key: const ValueKey('external-file-header'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Provider objects have no workspace ViewPB/cover envelope. Keep
            // their real identity rather than fabricating a decorated view.
            Text(
              key: const ValueKey('external-file-title'),
              node.name,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 24,
                fontVariations: const [FontVariation.weight(580)],
              ),
            ),
            const SizedBox(height: 8),
            FileActionBand(
              key: const ValueKey('external-file-actions'),
              responsive: controls.responsiveToolbar ||
                  (controls.toolbar == null && controls.toolbarBuilder == null),
              builder: (context) {
                final nativeActions = _nativeActions(context, palette);
                final builder = controls.toolbarBuilder;
                if (builder != null) return builder(context, nativeActions);
                return Wrap(
                  alignment: fileActionRunAlignment(context),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (controls.leading != null) controls.leading!,
                    if (controls.toolbar != null) controls.toolbar!,
                    ...controls.actions,
                    nativeActions,
                  ],
                );
              },
            ),
          ],
        ),
      );

  Widget _nativeActions(BuildContext context, FolderExplorerPalette palette) =>
      Wrap(
        key: const ValueKey('external-file-native-actions'),
        alignment: fileActionRunAlignment(context),
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('external-file-previous'),
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            onPressed: _hasPrevious ? () => _step(-1) : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            color: palette.textSecondary,
          ),
          IconButton(
            key: const ValueKey('external-file-next'),
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            onPressed: _hasNext ? () => _step(1) : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            color: palette.textSecondary,
          ),
          if ((node.webUrl ?? '').isNotEmpty)
            IconButton(
              key: const ValueKey('external-file-open-source'),
              tooltip: LocaleKeys.providers_openInSource.tr(),
              onPressed: _sourceAction(node, widget.controller, _generation),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              color: palette.textSecondary,
              splashRadius: 16,
            ),
        ],
      );
  VoidCallback _sourceAction(
    ProviderNode openedNode,
    ProviderController controller,
    int generation,
  ) {
    final source = controller.source;
    return () {
      if (!_isCurrent(controller, openedNode, source, generation) ||
          _route?.isCurrent != true) {
        return;
      }
      final uri = Uri.tryParse(openedNode.webUrl ?? '');
      if (uri != null) {
        unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
      }
    };
  }

  Widget _body(FolderExplorerPalette palette) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (failed || path == null) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 26, color: palette.textMuted),
              const SizedBox(height: 12),
              Text(
                LocaleKeys.providers_cannotOpen.tr(),
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => unawaited(_fetch()),
                child: Text(LocaleKeys.providers_tryAgain.tr()),
              ),
            ],
          ),
        ),
      );
    }

    return _renderer ??= externalFileRenderer(
      node: node,
      path: path!,
      palette: palette,
      bare: false,
      ocrService: widget.ocrService,
      isAvailable: _canRead,
    );
  }
}

/// Picks the renderer for one materialised object.
///
/// Shared with the page embed, so an embedded Drive PDF and a Drive PDF opened
/// from a collection are literally the same viewer.
Widget externalFileRenderer({
  required ProviderNode node,
  required String path,
  required FolderExplorerPalette palette,
  bool bare = true,
  OcrService? ocrService,
  bool Function()? isAvailable,
}) {
  final file = File(path);
  // A service names a file whatever a person typed, and every viewer picks
  // itself from the name, so the declared type supplies the extension.
  final name = providerFileNameFor(node);

  if (imgExtensionRegex.hasMatch(name) || node.kind == ProviderNodeKind.image) {
    return _ExternalImageStage(
      key: ValueKey((node.id, path, node.name)),
      node: node,
      file: file,
      palette: palette,
      ocrService: ocrService,
      isAvailable: isAvailable,
      wholePage: !bare,
    );
  }

  if (node.kind == ProviderNodeKind.video ||
      node.kind == ProviderNodeKind.audio) {
    return Center(
      child: FileMediaPlayer(
        key: ValueKey('external-media-${node.id}'),
        url: path,
        name: name,
        kind: node.kind == ProviderNodeKind.video
            ? FileMediaKind.video
            : FileMediaKind.audio,
      ),
    );
  }

  final kind = filePreviewKindFromName(name);
  if (kind == FilePreviewKind.pdf) {
    return PdfPreview(
      key: ValueKey('external-pdf-${node.id}'),
      file: file,
      name: name,
      bare: bare,
      editable: false,
      canReadFile: isAvailable,
      metadata: const {},
      onMetadataChanged: (_) {},
    );
  }
  if (isOfficeFile(name)) {
    return OfficeDocumentView(
      key: ValueKey('external-office-${node.id}'),
      file: file,
      name: name,
      source: path,
      editable: false,
      fallbackBuilder: (context) => _Unsupported(node: node, palette: palette),
    );
  }
  if (kind == null) {
    return _Unsupported(node: node, palette: palette);
  }
  Widget preview({double? height, bool sourceText = false}) => FilePreview(
        key: ValueKey('external-file-${node.id}'),
        file: file,
        name: name,
        kind: kind,
        bare: bare,
        editable: false,
        height: height,
        framed: bare,
        metadata: sourceText ? const {filePreviewEditModeKey: true} : const {},
        onMetadataChanged: (_) {},
      );
  if (bare) return preview();
  return LayoutBuilder(
    builder: (context, constraints) => preview(
      height: constraints.maxHeight,
      sourceText: kind == FilePreviewKind.text &&
          StandaloneFileScope.forName(context, name) != null,
    ),
  );
}

/// Uses the provider's already materialised display file, never its download
/// URL or thumbnail URL (and never workspace credentials).
class _ExternalImageStage extends StatefulWidget {
  const _ExternalImageStage({
    super.key,
    required this.node,
    required this.file,
    required this.palette,
    this.ocrService,
    this.isAvailable,
    this.wholePage = false,
  });

  final ProviderNode node;
  final File file;
  final FolderExplorerPalette palette;
  final OcrService? ocrService;
  final bool Function()? isAvailable;
  final bool wholePage;

  @override
  State<_ExternalImageStage> createState() => _ExternalImageStageState();
}

class _ExternalImageStageState extends State<_ExternalImageStage> {
  @override
  Widget build(BuildContext context) {
    if (widget.wholePage) {
      // The dialog owns the current-source/read-only scope and renderer cache.
      // Reuse its workspace counterpart's controls and native fitted pan;
      // never download again or lend an outer file's chrome to a bare embed.
      return workspacePhotoRenderer(
        file: widget.file,
        name: providerFileNameFor(widget.node),
        ocrService: widget.ocrService,
      );
    }
    final id = widget.node.id;
    final path = widget.file.path;
    return ImageOcrFindRegion(
      source: ImageEditorSource(url: path, type: CustomImageType.local),
      name: widget.node.name,
      service: widget.ocrService,
      isAvailable: () =>
          mounted &&
          widget.node.id == id &&
          widget.file.path == path &&
          (widget.isAvailable?.call() ?? true) &&
          TickerMode.of(context) &&
          ModalRoute.of(context)?.isActive != false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: InteractiveViewer(
            maxScale: 6,
            child: Image.file(
              widget.file,
              fit: BoxFit.scaleDown,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image_rounded,
                size: 28,
                color: widget.palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.node, required this.palette});

  final ProviderNode node;
  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_rounded,
              size: 30,
              color: palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              node.name,
              style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Text(
              LocaleKeys.providers_noViewer.tr(),
              style: TextStyle(color: palette.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
}
