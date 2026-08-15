import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/drawing/excalidraw_editor_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/custom_link_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/link_parsers/default_parser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block_fullscreen.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/drawing/excalidraw_scene.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/collections/album/image_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Telling a card what it holds.
///
/// Every kind that cannot simply be typed into needs to be asked a question
/// first — which picture, which address, which sort of diagram — and the
/// answers all arrive the same way, so no card is ever a dead end.

/// What a picture card was told.
@immutable
class CanvasImageChoice {
  const CanvasImageChoice({required this.url, this.naturalSize});

  final String url;

  /// The picture's own pixel size, when it could be read without decoding the
  /// whole thing. The card is shaped to match rather than cropping.
  final Size? naturalSize;
}

/// Where a picture should come from.
Future<CanvasImageChoice?> askForCanvasImage(
  BuildContext context, {
  required CanvasPalette palette,
  required Offset globalPosition,
}) async {
  final choice = await showAppMenu<String>(
    context: context,
    globalPosition: globalPosition,
    entries: [
      AppMenuHeader(LocaleKeys.canvas_image_title.tr()),
      AppMenuItem(
        label: LocaleKeys.canvas_image_fromComputer.tr(),
        icon: Icons.upload_rounded,
        value: 'local',
      ),
      AppMenuItem(
        label: LocaleKeys.canvas_image_fromAddress.tr(),
        icon: Icons.link_rounded,
        value: 'url',
      ),
    ],
  );
  if (choice == null || !context.mounted) {
    return null;
  }
  if (choice == 'url') {
    final url = await askForCanvasLink(
      context,
      palette: palette,
      title: LocaleKeys.canvas_image_fromAddress.tr(),
    );
    return url == null ? null : CanvasImageChoice(url: url);
  }
  return pickCanvasImageFile();
}

/// Copy a picture off this computer into the workspace's own storage, so the
/// canvas does not break when the original is moved.
Future<CanvasImageChoice?> pickCanvasImageFile() async {
  final result = await getIt<FilePickerService>().pickFiles(
    dialogTitle: LocaleKeys.canvas_image_fromComputer.tr(),
    type: FileType.image,
  );
  final path = result?.files.firstOrNull?.path;
  if (path == null || path.isEmpty) {
    return null;
  }
  final stored = await saveImageToLocalStorage(path);
  final source = stored ?? path;
  return CanvasImageChoice(
    url: source,
    naturalSize: await readCanvasImageSize(source),
  );
}

/// The pixel size of a local picture, read from its header.
///
/// Only the first few kilobytes are read: a canvas of photographs must not
/// decode forty full-size images to work out how big its cards should be.
Future<Size?> readCanvasImageSize(String path) async {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return null;
  }
  try {
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    final handle = await file.open();
    Uint8List head;
    try {
      head = await handle.read(64 * 1024);
    } finally {
      await handle.close();
    }
    final measured = readImageHeaderSize(head);
    if (measured == null || measured.width < 1 || measured.height < 1) {
      return null;
    }
    return Size(measured.width.toDouble(), measured.height.toDouble());
  } catch (error) {
    Log.warn('Could not measure a picture for a canvas card: $error');
    return null;
  }
}

/// Write a picture from the clipboard into the workspace's own storage.
Future<CanvasImageChoice?> saveCanvasClipboardImage(
  String format,
  Uint8List bytes,
) async {
  try {
    final directory = await getIt<ApplicationDataStorage>().getPath();
    final images = Directory(p.join(directory, 'images'));
    if (!images.existsSync()) {
      await images.create(recursive: true);
    }
    final name = 'canvas_${DateTime.now().millisecondsSinceEpoch}.$format';
    final file = File(p.join(images.path, name));
    await file.writeAsBytes(bytes);
    final measured = readImageHeaderSize(bytes);
    return CanvasImageChoice(
      url: file.path,
      naturalSize: measured == null
          ? null
          : Size(measured.width.toDouble(), measured.height.toDouble()),
    );
  } catch (error) {
    Log.warn('Could not keep a picture pasted onto a canvas: $error');
    return null;
  }
}

/// Ask for an address.
///
/// A link is almost always pasted rather than typed, so there is a button for
/// it as well as the key binding — a button needs no key handling at all.
Future<String?> askForCanvasLink(
  BuildContext context, {
  required CanvasPalette palette,
  String initialValue = '',
  String? title,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _CanvasLinkDialog(
        palette: palette,
        initialValue: initialValue,
        title: title ?? LocaleKeys.canvas_card_addUrl.tr(),
      ),
    );

class _CanvasLinkDialog extends StatefulWidget {
  const _CanvasLinkDialog({
    required this.palette,
    required this.initialValue,
    required this.title,
  });

  final CanvasPalette palette;
  final String initialValue;
  final String title;

  @override
  State<_CanvasLinkDialog> createState() => _CanvasLinkDialogState();
}

class _CanvasLinkDialogState extends State<_CanvasLinkDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        widget.title,
        style: canvasLabelStyle(
          palette,
          size: 15,
          weight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 380,
        // The shared field, so Backspace and Ctrl+V work here exactly as they
        // do in every other dialog, and the paste button comes with it.
        child: ProviderTextField(
          controller: _controller,
          label: LocaleKeys.canvas_card_addUrl.tr(),
          palette: FolderExplorerPalette.of(context),
          autofocus: true,
          showPasteButton: true,
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(LocaleKeys.button_confirm.tr()),
        ),
      ],
    );
  }
}

/// Which sort of diagram. Both are offered, because they are good at opposite
/// things: one is written and laid out for you, the other is drawn by hand.
Future<CanvasDiagramKind?> askForCanvasDiagramKind(
  BuildContext context, {
  required Offset globalPosition,
}) =>
    showAppMenu<CanvasDiagramKind>(
      context: context,
      globalPosition: globalPosition,
      entries: [
        AppMenuHeader(LocaleKeys.canvas_diagram_title.tr()),
        AppMenuItem(
          label: LocaleKeys.canvas_diagram_mermaid.tr(),
          subtitle: LocaleKeys.canvas_diagram_mermaidHint.tr(),
          icon: Icons.account_tree_rounded,
          value: CanvasDiagramKind.mermaid,
        ),
        AppMenuItem(
          label: LocaleKeys.canvas_diagram_drawing.tr(),
          subtitle: canRunExcalidrawEditor
              ? LocaleKeys.canvas_diagram_drawingHint.tr()
              : LocaleKeys.canvas_diagram_drawingUnavailable.tr(),
          icon: Icons.draw_rounded,
          enabled: canRunExcalidrawEditor,
          value: CanvasDiagramKind.drawing,
        ),
      ],
    );

/// Something to start from, so a new diagram is never a blank stare.
const String sampleCanvasMermaid = '''
flowchart LR
  A[Idea] --> B[Plan]
  B --> C[Build]
  C --> D[Ship]''';

/// Open a hand-drawn diagram in the real Excalidraw editor.
///
/// The same route the drawing block uses, so a drawing made on a canvas and a
/// drawing made in a page are the same document opened the same way.
Future<void> openCanvasDrawing(
  BuildContext context, {
  required String scene,
  required bool editable,
  required ValueChanged<String> onSceneChanged,
}) {
  if (!canRunExcalidrawEditor) {
    return Future<void>.value();
  }
  return showVisualBlockFullscreen<void>(
    context: context,
    icon: Icons.draw_rounded,
    title: LocaleKeys.canvas_diagram_drawing.tr(),
    subtitle: LocaleKeys.diagrams_drawing_poweredBy.tr(),
    builder: (_) => _CanvasDrawingStage(
      scene: scene.trim().isEmpty ? DrawScene.empty().encode() : scene,
      editable: editable,
      onSceneChanged: onSceneChanged,
    ),
  );
}

class _CanvasDrawingStage extends StatefulWidget {
  const _CanvasDrawingStage({
    required this.scene,
    required this.editable,
    required this.onSceneChanged,
  });

  final String scene;
  final bool editable;
  final ValueChanged<String> onSceneChanged;

  @override
  State<_CanvasDrawingStage> createState() => _CanvasDrawingStageState();
}

class _CanvasDrawingStageState extends State<_CanvasDrawingStage> {
  final ExcalidrawEditorController _controller = ExcalidrawEditorController();

  @override
  void dispose() {
    // The editor is asked for the scene one last time on the way out: the
    // web side debounces, so the final strokes may not have been reported.
    unawaited(_controller.flush());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcalidrawEditorView(
        scene: widget.scene,
        editable: widget.editable,
        controller: _controller,
        onSceneChanged: widget.onSceneChanged,
      );
}

/// Which language a code card is written in.
Future<String?> askForCanvasCodeLanguage(
  BuildContext context, {
  required Offset globalPosition,
  String? selected,
}) =>
    showAppMenu<String>(
      context: context,
      globalPosition: globalPosition,
      entries: [
        AppMenuHeader(LocaleKeys.canvas_card_language.tr()),
        for (final language in canvasCodeLanguages)
          AppMenuItem(
            label: language,
            selected: normalizeCodeLanguage(selected ?? '') ==
                normalizeCodeLanguage(language),
            value: language,
          ),
      ],
    );

/// The languages offered on a code card. Deliberately short: a canvas card is
/// a note about code, not a source file, and a list of two hundred entries is
/// not a menu anybody reads.
const List<String> canvasCodeLanguages = <String>[
  'text',
  'bash',
  'c',
  'cpp',
  'csharp',
  'css',
  'dart',
  'go',
  'html',
  'java',
  'javascript',
  'json',
  'kotlin',
  'markdown',
  'php',
  'python',
  'ruby',
  'rust',
  'sql',
  'swift',
  'typescript',
  'xml',
  'yaml',
];

/// Read a link's title, description and picture so a saved link looks like the
/// page it points at rather than like a bare address.
///
/// Failure is normal — plenty of sites refuse a plain fetch — so it returns
/// null rather than reporting anything.
Future<LinkInfo?> readCanvasLinkInfo(String url) async {
  final uri = Uri.tryParse(LinkInfoParser.formatUrl(url));
  if (uri == null || !uri.hasScheme) {
    return null;
  }
  try {
    return await DefaultParser().parse(uri);
  } catch (error) {
    Log.warn('Could not read a link put on a canvas: $error');
    return null;
  }
}
