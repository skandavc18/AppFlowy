// The notebook viewer and editor.
//
// A notebook is not a document that happens to hold code: it is a list of
// cells that are written, run and re-run one at a time, each keeping the
// variables the ones before it made. So it gets its own surface rather than
// the plain preview every other file type shares — cells can be added, moved,
// changed between code and prose, run on their own, and their output is shown
// the way the notebook recorded it.

import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../code_block_chrome.dart';
import 'notebook_document.dart';
import 'notebook_kernel.dart';
import 'notebook_markup.dart';

/// How many lines of printed output are shown before the rest is folded away.
const int notebookOutputPreviewLines = 120;

class NotebookView extends StatefulWidget {
  const NotebookView({
    super.key,
    required this.file,
    required this.name,
    required this.source,
    this.editable = true,
    this.toolbarTrailing,
  });

  final File file;
  final String name;

  /// The `.ipynb` text, already read from disk.
  final String source;

  /// Whether cells can be edited and the file written back.
  final bool editable;

  final Widget? toolbarTrailing;

  @override
  State<NotebookView> createState() => _NotebookViewState();
}

class _NotebookViewState extends State<NotebookView> {
  NotebookDocument? _document;
  String? _parseError;
  NotebookKernel? _kernel;

  final Map<String, _CellEditor> _editors = {};
  final ScrollController _scroll = ScrollController();

  String? _runningCellId;
  bool _runningAll = false;
  String? _selectedCellId;
  Timer? _saveTimer;
  Timer? _outputFlush;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NotebookView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.source != widget.source) {
      _flushSave();
      _load();
    }
  }

  @override
  void dispose() {
    _flushSave();
    _saveTimer?.cancel();
    _outputFlush?.cancel();
    for (final editor in _editors.values) {
      editor.dispose();
    }
    _editors.clear();
    _kernel?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    try {
      final document = NotebookDocument.parse(widget.source);
      _kernel?.dispose();
      _document = document;
      _parseError = null;
      _kernel = NotebookKernel(
        language: document.language,
        workingDirectory: p.dirname(widget.file.path),
      )..addListener(_onKernelChanged);
    } on NotebookFormatException catch (error) {
      _document = null;
      _parseError = error.message;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onKernelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  NotebookDocument get _doc => _document!;

  _CellEditor _editorFor(NotebookCell cell, String language) =>
      _editors.putIfAbsent(
        cell.id,
        () => _CellEditor(
          controller: NotebookCodeController(
            text: cell.source,
            language: cell.isCode ? language : 'markdown',
          ),
        ),
      );

  // ---------------------------------------------------------------- editing

  void _updateSource(String cellId, String source) {
    final index = _doc.indexOfCell(cellId);
    if (index < 0) {
      return;
    }
    // No rebuild on a keystroke: the field already shows the text, and
    // repainting every cell of a long notebook per character is what makes an
    // editor feel heavy.
    _document =
        _doc.withCell(index, _doc.cells[index].copyWith(source: source));
    _scheduleSave();
  }

  void _mutate(NotebookDocument next) {
    setState(() => _document = next);
    _scheduleSave();
  }

  void _insertCell(int index, NotebookCellType type) {
    final cell = NotebookCell.blank(type);
    _mutate(_doc.withCellInserted(index, cell));
    setState(() => _selectedCellId = cell.id);
    if (type != NotebookCellType.code) {
      _editorFor(cell, _doc.language).editingSource = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editors[cell.id]?.focus.requestFocus();
    });
  }

  void _removeCell(String cellId) {
    final index = _doc.indexOfCell(cellId);
    if (index < 0) {
      return;
    }
    _retire(_editors.remove(cellId));
    final next = _doc.withCellRemoved(index);
    _mutate(
      next.cells.isEmpty
          ? next.withCellInserted(0, NotebookCell.blank(NotebookCellType.code))
          : next,
    );
  }

  /// Lets go of a cell's controller only once the field that was using it has
  /// been taken down, or the text field detaches from a disposed controller.
  void _retire(_CellEditor? editor) {
    if (editor == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => editor.dispose());
  }

  void _duplicateCell(String cellId) {
    final index = _doc.indexOfCell(cellId);
    if (index < 0) {
      return;
    }
    final source = _doc.cells[index];
    _mutate(
      _doc.withCellInserted(
        index + 1,
        NotebookCell(
          id: newNotebookCellId(),
          type: source.type,
          source: source.source,
          metadata: source.metadata,
          attachments: source.attachments,
        ),
      ),
    );
  }

  void _changeCellType(String cellId, NotebookCellType type) {
    final index = _doc.indexOfCell(cellId);
    if (index < 0 || _doc.cells[index].type == type) {
      return;
    }
    final cell = _doc.cells[index];
    _retire(_editors.remove(cellId));
    _mutate(
      _doc.withCell(
        index,
        cell.copyWith(
          type: type,
          outputs: const [],
          clearExecutionCount: true,
        ),
      ),
    );
  }

  void _clearOutputs(String cellId) {
    final index = _doc.indexOfCell(cellId);
    if (index < 0) {
      return;
    }
    _mutate(
      _doc.withCell(
        index,
        _doc.cells[index]
            .copyWith(outputs: const [], clearExecutionCount: true),
      ),
    );
  }

  void _clearAllOutputs() {
    _mutate(
      _doc.copyWith(
        cells: [
          for (final cell in _doc.cells)
            cell.isCode
                ? cell.copyWith(outputs: const [], clearExecutionCount: true)
                : cell,
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- saving

  void _scheduleSave() {
    if (!widget.editable) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _write);
  }

  void _write() {
    _saveTimer = null;
    final document = _document;
    if (document == null || !widget.editable) {
      return;
    }
    try {
      widget.file.writeAsStringSync(document.encode(), flush: true);
    } on FileSystemException catch (error, stackTrace) {
      Log.error('Failed to save the notebook', error, stackTrace);
    }
  }

  /// Commits a pending edit before the view goes away.
  void _flushSave() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _write();
    }
  }

  // ---------------------------------------------------------------- running

  Future<bool> _runCell(String cellId, {bool advance = false}) async {
    final index = _doc.indexOfCell(cellId);
    if (index < 0) {
      return false;
    }
    final editor = _editors[cellId];
    final cell = _doc.cells[index];

    if (!cell.isCode) {
      setState(() => editor?.editingSource = false);
      if (advance) {
        _selectNext(index);
      }
      return true;
    }

    final kernel = _kernel;
    if (kernel == null || !kernel.canRun) {
      return false;
    }
    if (_runningCellId != null) {
      return false;
    }

    final code = editor?.controller.text ?? cell.source;
    setState(() {
      _runningCellId = cellId;
      _selectedCellId = cellId;
      _document = _doc.withCell(
        index,
        cell.copyWith(
          source: code,
          outputs: const [],
          clearExecutionCount: true,
        ),
      );
    });

    final collected = <NotebookOutput>[];
    final execution = await kernel.execute(
      code,
      onOutput: (output) => _appendOutput(cellId, collected, output),
    );

    if (!mounted) {
      return !execution.failed;
    }
    _outputFlush?.cancel();
    _outputFlush = null;
    if (execution.notice.isNotEmpty) {
      _appendOutput(
        cellId,
        collected,
        NotebookOutput.stream(
          name: 'stderr',
          text: '${execution.notice}\n',
        ),
      );
    }
    final finalIndex = _doc.indexOfCell(cellId);
    setState(() {
      _runningCellId = null;
      if (finalIndex >= 0) {
        _document = _doc.withCell(
          finalIndex,
          _doc.cells[finalIndex].copyWith(
            outputs: List.of(collected),
            executionCount: execution.executionCount,
          ),
        );
      }
    });
    _scheduleSave();

    if (advance && !execution.failed) {
      _selectNext(finalIndex);
    }
    return !execution.failed;
  }

  /// Adds one output, merging printed text into the run that precedes it.
  ///
  /// A loop that prints thousands of lines sends thousands of messages, so the
  /// screen is brought up to date on a beat rather than per message.
  void _appendOutput(
    String cellId,
    List<NotebookOutput> collected,
    NotebookOutput output,
  ) {
    if (output.kind == NotebookOutputKind.stream &&
        collected.isNotEmpty &&
        collected.last.kind == NotebookOutputKind.stream &&
        collected.last.name == output.name) {
      collected[collected.length - 1] = collected.last.appendText(output.text);
    } else {
      collected.add(output);
    }
    if (_outputFlush?.isActive ?? false) {
      return;
    }
    _outputFlush = Timer(
      const Duration(milliseconds: 80),
      () => _showOutputs(cellId, collected),
    );
  }

  void _showOutputs(String cellId, List<NotebookOutput> collected) {
    _outputFlush = null;
    final index = _doc.indexOfCell(cellId);
    if (index < 0 || !mounted) {
      return;
    }
    setState(() {
      _document = _doc.withCell(
        index,
        _doc.cells[index].copyWith(outputs: List.of(collected)),
      );
    });
  }

  void _selectNext(int index) {
    if (index < 0) {
      return;
    }
    if (index + 1 >= _doc.cells.length) {
      if (widget.editable) {
        _insertCell(_doc.cells.length, NotebookCellType.code);
      }
      return;
    }
    final next = _doc.cells[index + 1];
    setState(() => _selectedCellId = next.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editors[next.id]?.focus.requestFocus();
    });
  }

  Future<void> _runAll({bool restart = false}) async {
    if (_runningAll || _runningCellId != null) {
      return;
    }
    setState(() => _runningAll = true);
    if (restart) {
      await _kernel?.restart();
    }
    for (final cell in List.of(_doc.cells)) {
      if (!mounted || !_runningAll) {
        break;
      }
      if (!cell.isCode || cell.source.trim().isEmpty) {
        continue;
      }
      final ok = await _runCell(cell.id);
      if (!ok) {
        break;
      }
    }
    if (mounted) {
      setState(() => _runningAll = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _runningAll = false);
    await _kernel?.interrupt();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final palette = CodeBlockPalette.resolve(context);
    final error = _parseError;
    if (error != null) {
      return _NotebookMessage(palette: palette, message: error);
    }
    final document = _document;
    if (document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final kernel = _kernel!;

    return ColoredBox(
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NotebookToolbar(
            palette: palette,
            name: widget.name,
            document: document,
            kernel: kernel,
            editable: widget.editable,
            running: _runningCellId != null || _runningAll,
            onRunAll: () => unawaited(_runAll()),
            onRestartAndRun: () => unawaited(_runAll(restart: true)),
            onStop: () => unawaited(_stop()),
            onRestart: () => unawaited(_kernel!.restart()),
            onClearOutputs: _clearAllOutputs,
            onAddCell: (type) => _insertCell(document.cells.length, type),
            trailing: widget.toolbarTrailing,
          ),
          if (kernel.blockedReason.isNotEmpty)
            _NotebookNotice(palette: palette, message: kernel.blockedReason),
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 10, 18, 60),
                itemCount: document.cells.length + 1,
                itemBuilder: (context, index) {
                  if (index == document.cells.length) {
                    return _NotebookInsertStrip(
                      palette: palette,
                      visible: widget.editable,
                      alwaysVisible: true,
                      onInsert: (type) => _insertCell(index, type),
                    );
                  }
                  final cell = document.cells[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (index > 0)
                        _NotebookInsertStrip(
                          palette: palette,
                          visible: widget.editable,
                          onInsert: (type) => _insertCell(index, type),
                        ),
                      _NotebookCellView(
                        key: ValueKey(cell.id),
                        cell: cell,
                        editor: _editorFor(cell, document.language),
                        palette: palette,
                        language: document.language,
                        editable: widget.editable,
                        canRun: kernel.canRun,
                        running: _runningCellId == cell.id,
                        selected: _selectedCellId == cell.id,
                        baseDirectory: p.dirname(widget.file.path),
                        awaitingInput:
                            _runningCellId == cell.id && kernel.awaitingInput,
                        inputPrompt: kernel.inputPrompt,
                        onInputSubmitted: kernel.provideInput,
                        onSelected: () =>
                            setState(() => _selectedCellId = cell.id),
                        onSourceChanged: (value) =>
                            _updateSource(cell.id, value),
                        onRun: ({bool advance = false}) =>
                            unawaited(_runCell(cell.id, advance: advance)),
                        onStop: () => unawaited(_stop()),
                        onMove: (delta) => _mutate(
                          _doc.withCellMoved(_doc.indexOfCell(cell.id), delta),
                        ),
                        onDuplicate: () => _duplicateCell(cell.id),
                        onDelete: () => _removeCell(cell.id),
                        onChangeType: (type) => _changeCellType(cell.id, type),
                        onClearOutput: () => _clearOutputs(cell.id),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything one cell needs to be edited, kept out of the document so the
/// caret and the scroll position survive a rebuild.
class _CellEditor {
  _CellEditor({required this.controller});

  final NotebookCodeController controller;
  final FocusNode focus = FocusNode();

  /// Whether a prose cell is showing its markdown instead of its rendering.
  bool editingSource = false;

  /// Whether a long output is folded.
  bool outputExpanded = false;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

/// A code field that paints its own syntax highlighting.
class NotebookCodeController extends TextEditingController {
  NotebookCodeController({required super.text, required String language})
      : language = normalizeCodeLanguage(language);

  String language;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) =>
      buildSyntaxHighlightedTextSpan(
        code: text,
        language: language,
        brightness: Theme.of(context).brightness,
        isPaper: PaperTheme.isEnabled(context),
        style: style,
      );
}

// ------------------------------------------------------------------ chrome

class _NotebookToolbar extends StatelessWidget {
  const _NotebookToolbar({
    required this.palette,
    required this.name,
    required this.document,
    required this.kernel,
    required this.editable,
    required this.running,
    required this.onRunAll,
    required this.onRestartAndRun,
    required this.onStop,
    required this.onRestart,
    required this.onClearOutputs,
    required this.onAddCell,
    this.trailing,
  });

  final CodeBlockPalette palette;
  final String name;
  final NotebookDocument document;
  final NotebookKernel kernel;
  final bool editable;
  final bool running;
  final VoidCallback onRunAll;
  final VoidCallback onRestartAndRun;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onClearOutputs;
  final ValueChanged<NotebookCellType> onAddCell;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: palette.header,
      child: Row(
        children: [
          Icon(Icons.menu_book_rounded, size: 15, color: palette.textSecondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: codeUiTextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _KernelStatus(palette: palette, kernel: kernel),
          const Flexible(child: SizedBox(width: 14)),
          if (running)
            CodeToolbarButton(
              palette: palette,
              tooltip: 'Stop the running cell',
              icon: Icons.stop_rounded,
              label: 'Stop',
              foregroundColor: palette.error,
              onPressed: onStop,
            )
          else
            CodeToolbarButton(
              palette: palette,
              tooltip: 'Run every cell in order',
              icon: Icons.play_arrow_rounded,
              label: 'Run all',
              foregroundColor: kernel.canRun ? palette.accent : null,
              onPressed: kernel.canRun ? onRunAll : null,
            ),
          if (editable) ...[
            CodeToolbarButton(
              palette: palette,
              tooltip: 'Add a code cell',
              icon: Icons.add_rounded,
              onPressed: () => onAddCell(NotebookCellType.code),
            ),
          ],
          CodeHeaderDivider(palette: palette),
          Builder(
            builder: (context) => CodeToolbarButton(
              palette: palette,
              tooltip: 'Notebook actions',
              icon: Icons.more_horiz_rounded,
              onPressed: () => _showMenu(context),
            ),
          ),
          if (trailing != null) ...[
            CodeHeaderDivider(palette: palette),
            trailing!,
          ],
        ],
      ),
    );
  }

  void _showMenu(BuildContext context) {
    unawaited(
      showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuItem(
            label: 'Run all cells',
            icon: Icons.play_arrow_rounded,
            enabled: kernel.canRun && !running,
            onSelected: onRunAll,
          ),
          AppMenuItem(
            label: 'Restart and run all',
            icon: Icons.restart_alt_rounded,
            enabled: kernel.canRun && !running,
            onSelected: onRestartAndRun,
          ),
          AppMenuItem(
            label: 'Restart the kernel',
            icon: Icons.power_settings_new_rounded,
            enabled: kernel.isRunning,
            onSelected: onRestart,
          ),
          const AppMenuSeparator(),
          if (editable) ...[
            AppMenuItem(
              label: 'Add a code cell',
              icon: Icons.code_rounded,
              onSelected: () => onAddCell(NotebookCellType.code),
            ),
            AppMenuItem(
              label: 'Add a markdown cell',
              icon: Icons.notes_rounded,
              onSelected: () => onAddCell(NotebookCellType.markdown),
            ),
            AppMenuItem(
              label: 'Clear every output',
              icon: Icons.layers_clear_rounded,
              onSelected: onClearOutputs,
            ),
            const AppMenuSeparator(),
          ],
          AppMenuItem(
            label: kernel.detail.isEmpty
                ? '${document.kernelName} · not started'
                : kernel.detail,
            icon: Icons.info_outline_rounded,
            enabled: false,
          ),
        ],
      ),
    );
  }
}

class _KernelStatus extends StatelessWidget {
  const _KernelStatus({required this.palette, required this.kernel});

  final CodeBlockPalette palette;
  final NotebookKernel kernel;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (kernel.state) {
      NotebookKernelState.busy => (palette.accent, 'Running'),
      NotebookKernelState.ready => (palette.success, 'Ready'),
      NotebookKernelState.starting => (palette.accent, 'Starting'),
      NotebookKernelState.unavailable => (palette.error, 'Unavailable'),
      NotebookKernelState.stopped => (palette.textMuted, 'Idle'),
    };
    return Tooltip(
      message: kernel.detail.isEmpty
          ? 'The kernel starts the first time a cell is run.'
          : kernel.detail,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: codeBlockAnimationDuration,
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: codeUiTextStyle(
              color: palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotebookNotice extends StatelessWidget {
  const _NotebookNotice({required this.palette, required this.message});

  final CodeBlockPalette palette;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: palette.input,
        borderRadius: BorderRadius.circular(codeSurfaceRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: palette.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotebookMessage extends StatelessWidget {
  const _NotebookMessage({required this.palette, required this.message});

  final CodeBlockPalette palette;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 26,
                color: palette.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The gap between two cells, where a new one is added.
class _NotebookInsertStrip extends StatefulWidget {
  const _NotebookInsertStrip({
    required this.palette,
    required this.visible,
    required this.onInsert,
    this.alwaysVisible = false,
  });

  final CodeBlockPalette palette;
  final bool visible;
  final bool alwaysVisible;
  final ValueChanged<NotebookCellType> onInsert;

  @override
  State<_NotebookInsertStrip> createState() => _NotebookInsertStripState();
}

class _NotebookInsertStripState extends State<_NotebookInsertStrip> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return const SizedBox(height: 10);
    }
    final showing = hovering || widget.alwaysVisible;
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: SizedBox(
        height: 26,
        child: Center(
          child: AnimatedOpacity(
            duration: codeBlockAnimationDuration,
            opacity: showing ? 1 : 0,
            child: IgnorePointer(
              ignoring: !showing,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CodeToolbarButton(
                    palette: widget.palette,
                    tooltip: 'Add a code cell here',
                    icon: Icons.add_rounded,
                    label: 'Code',
                    onPressed: () => widget.onInsert(NotebookCellType.code),
                  ),
                  const SizedBox(width: 4),
                  CodeToolbarButton(
                    palette: widget.palette,
                    tooltip: 'Add a markdown cell here',
                    icon: Icons.add_rounded,
                    label: 'Markdown',
                    onPressed: () => widget.onInsert(NotebookCellType.markdown),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- cell

class _NotebookCellView extends StatefulWidget {
  const _NotebookCellView({
    super.key,
    required this.cell,
    required this.editor,
    required this.palette,
    required this.language,
    required this.editable,
    required this.canRun,
    required this.running,
    required this.selected,
    required this.baseDirectory,
    required this.awaitingInput,
    required this.inputPrompt,
    required this.onInputSubmitted,
    required this.onSelected,
    required this.onSourceChanged,
    required this.onRun,
    required this.onStop,
    required this.onMove,
    required this.onDuplicate,
    required this.onDelete,
    required this.onChangeType,
    required this.onClearOutput,
  });

  final NotebookCell cell;
  final _CellEditor editor;
  final CodeBlockPalette palette;
  final String language;
  final bool editable;
  final bool canRun;
  final bool running;
  final bool selected;
  final String baseDirectory;
  final bool awaitingInput;
  final String inputPrompt;
  final ValueChanged<String> onInputSubmitted;
  final VoidCallback onSelected;
  final ValueChanged<String> onSourceChanged;
  final void Function({bool advance}) onRun;
  final VoidCallback onStop;
  final ValueChanged<int> onMove;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<NotebookCellType> onChangeType;
  final VoidCallback onClearOutput;

  @override
  State<_NotebookCellView> createState() => _NotebookCellViewState();
}

class _NotebookCellViewState extends State<_NotebookCellView> {
  bool hovering = false;
  final TextEditingController _input = TextEditingController();

  CodeBlockPalette get palette => widget.palette;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _showsSource =>
      widget.cell.isCode ||
      widget.editor.editingSource ||
      widget.cell.type == NotebookCellType.raw;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: codeBlockAnimationDuration,
          curve: AppFlowyMotion.standardCurve,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(codeSurfaceRadius),
            border: Border(
              left: BorderSide(
                color: widget.running
                    ? palette.accent
                    : widget.selected
                        ? palette.accent.withValues(alpha: 0.55)
                        : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _gutter(),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        _body(),
                        Positioned(
                          top: 0,
                          right: 4,
                          child: AnimatedOpacity(
                            duration: codeBlockAnimationDuration,
                            opacity: hovering ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !hovering,
                              child: _actions(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.awaitingInput) _inputRow(),
                    if (widget.cell.isCode && widget.cell.hasOutputs)
                      _NotebookOutputs(
                        cell: widget.cell,
                        palette: palette,
                        baseDirectory: widget.baseDirectory,
                        editor: widget.editor,
                        onToggleExpanded: () => setState(
                          () => widget.editor.outputExpanded =
                              !widget.editor.outputExpanded,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gutter() {
    final label = widget.running
        ? '[*]'
        : widget.cell.executionCount != null
            ? '[${widget.cell.executionCount}]'
            : widget.cell.isCode
                ? '[ ]'
                : '';
    return SizedBox(
      width: 52,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hovering && (widget.cell.isCode || widget.editable))
              CodeToolbarButton(
                palette: palette,
                tooltip: widget.running
                    ? 'Stop this cell'
                    : widget.cell.isCode
                        ? 'Run this cell  (Ctrl+Enter)'
                        : 'Render this cell',
                icon: widget.running
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
                foregroundColor:
                    widget.running ? palette.error : palette.accent,
                onPressed: widget.running
                    ? widget.onStop
                    : widget.cell.isCode && !widget.canRun
                        ? null
                        : () => widget.onRun(),
              )
            else if (label.isNotEmpty)
              SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      label,
                      style: codeUiTextStyle(
                        color:
                            widget.running ? palette.accent : palette.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actions() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: palette.menu.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(9),
          boxShadow: palette.nestedShadows,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.cell.isCode)
              CodeToolbarButton(
                palette: palette,
                tooltip: widget.editor.editingSource
                    ? 'Show the rendered cell'
                    : 'Edit the markdown',
                icon: widget.editor.editingSource
                    ? Icons.visibility_rounded
                    : Icons.edit_rounded,
                onPressed: widget.editable
                    ? () => setState(
                          () => widget.editor.editingSource =
                              !widget.editor.editingSource,
                        )
                    : null,
              ),
            if (widget.editable) ...[
              CodeToolbarButton(
                palette: palette,
                tooltip: 'Move up',
                icon: Icons.keyboard_arrow_up_rounded,
                onPressed: () => widget.onMove(-1),
              ),
              CodeToolbarButton(
                palette: palette,
                tooltip: 'Move down',
                icon: Icons.keyboard_arrow_down_rounded,
                onPressed: () => widget.onMove(1),
              ),
            ],
            Builder(
              builder: (context) => CodeToolbarButton(
                palette: palette,
                tooltip: 'Cell actions',
                icon: Icons.more_horiz_rounded,
                onPressed: () => _showCellMenu(context),
              ),
            ),
          ],
        ),
      );

  void _showCellMenu(BuildContext context) {
    unawaited(
      showAppMenuForWidget<void>(
        context: context,
        entries: [
          AppMenuItem(
            label: 'Run cell',
            icon: Icons.play_arrow_rounded,
            shortcut: 'Ctrl+Enter',
            enabled: widget.canRun || !widget.cell.isCode,
            onSelected: () => widget.onRun(),
          ),
          AppMenuItem(
            label: 'Run and move on',
            icon: Icons.skip_next_rounded,
            shortcut: 'Shift+Enter',
            enabled: widget.canRun || !widget.cell.isCode,
            onSelected: () => widget.onRun(advance: true),
          ),
          const AppMenuSeparator(),
          AppMenuItem(
            label: 'Cell type',
            icon: Icons.swap_horiz_rounded,
            enabled: widget.editable,
            submenu: [
              for (final type in NotebookCellType.values)
                AppMenuItem(
                  label: type.label,
                  icon: switch (type) {
                    NotebookCellType.code => Icons.code_rounded,
                    NotebookCellType.markdown => Icons.notes_rounded,
                    NotebookCellType.raw => Icons.text_fields_rounded,
                  },
                  selected: widget.cell.type == type,
                  onSelected: () => widget.onChangeType(type),
                ),
            ],
          ),
          AppMenuItem(
            label: 'Duplicate',
            icon: Icons.copy_rounded,
            enabled: widget.editable,
            onSelected: widget.onDuplicate,
          ),
          AppMenuItem(
            label: 'Copy source',
            icon: Icons.content_copy_rounded,
            onSelected: () => unawaited(
              Clipboard.setData(
                ClipboardData(text: widget.editor.controller.text),
              ),
            ),
          ),
          if (widget.cell.hasOutputs)
            AppMenuItem(
              label: 'Clear output',
              icon: Icons.layers_clear_rounded,
              enabled: widget.editable,
              onSelected: widget.onClearOutput,
            ),
          const AppMenuSeparator(),
          AppMenuItem(
            label: 'Delete cell',
            icon: Icons.delete_outline_rounded,
            destructive: true,
            enabled: widget.editable,
            onSelected: widget.onDelete,
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (!_showsSource) {
      return _rendered();
    }
    return _editor();
  }

  Widget _rendered() {
    final source = widget.cell.source.trim();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: widget.editable
          ? () => setState(() => widget.editor.editingSource = true)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 30, 2),
        child: source.isEmpty
            ? Text(
                'Empty markdown cell — double-click to write in it.',
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              )
            : NotebookMarkup(
                source: widget.cell.source,
                palette: palette,
                baseDirectory: widget.baseDirectory,
                attachments: widget.cell.attachments,
              ),
      ),
    );
  }

  Widget _editor() {
    final isCode = widget.cell.isCode;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: isCode ? palette.input : palette.input.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(codeSurfaceRadius),
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
              widget.onRun(),
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
              widget.onRun(),
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
              widget.onRun(advance: true),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!isCode) {
              setState(() => widget.editor.editingSource = false);
            }
          },
        },
        child: TextField(
          controller: widget.editor.controller,
          focusNode: widget.editor.focus,
          readOnly: !widget.editable,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: codeUiTextStyle(
            color: palette.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ).copyWith(height: 1.55),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            border: InputBorder.none,
            isDense: true,
            hintText: isCode ? 'Write some ${widget.language}…' : 'Write…',
            hintStyle: codeUiTextStyle(
              color: palette.textMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
            ),
            // The cell already paints its surface; a filled field would blend
            // Material's hover colour over it and grey the cell out.
            filled: false,
            hoverColor: Colors.transparent,
          ),
          onChanged: widget.onSourceChanged,
        ),
      ),
    );
  }

  /// The prompt a cell blocked on `input()` shows.
  Widget _inputRow() => Container(
        margin: const EdgeInsets.fromLTRB(0, 6, 4, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: palette.terminal,
          borderRadius: BorderRadius.circular(codeSurfaceRadius),
        ),
        child: Row(
          children: [
            Text(
              widget.inputPrompt.isEmpty ? '›' : widget.inputPrompt,
              style: codeUiTextStyle(
                color: palette.accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _input,
                autofocus: true,
                style: codeUiTextStyle(
                  color: palette.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                cursorWidth: 7,
                cursorRadius: Radius.zero,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  filled: false,
                  hoverColor: Colors.transparent,
                ),
                onSubmitted: (value) {
                  widget.onInputSubmitted(value);
                  _input.clear();
                },
              ),
            ),
          ],
        ),
      );
}

// ----------------------------------------------------------------- outputs

class _NotebookOutputs extends StatelessWidget {
  const _NotebookOutputs({
    required this.cell,
    required this.palette,
    required this.baseDirectory,
    required this.editor,
    required this.onToggleExpanded,
  });

  final NotebookCell cell;
  final CodeBlockPalette palette;
  final String baseDirectory;
  final _CellEditor editor;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final outputs =
        cell.outputs.where((output) => !output.isEmpty).toList(growable: false);
    if (outputs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 6, 4, 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.terminal,
        borderRadius: BorderRadius.circular(codeSurfaceRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < outputs.length; index++)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
              child: _output(outputs[index]),
            ),
        ],
      ),
    );
  }

  Widget _output(NotebookOutput output) {
    if (output.isError) {
      return _errorPanel(output);
    }
    if (output.kind == NotebookOutputKind.stream) {
      return _streamText(output);
    }

    final image = output.image;
    if (image != null) {
      final bytes = decodeBase64(image.value);
      if (bytes != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(bytes),
              ),
            ),
          ),
        );
      }
    }
    final svg = output.svg;
    if (svg != null && svg.trim().isNotEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SvgPicture.string(svg),
        ),
      );
    }
    final html = output.html;
    if (html != null && html.trim().isNotEmpty) {
      return NotebookMarkup(
        source: html,
        palette: palette,
        isHtml: true,
        baseDirectory: baseDirectory,
      );
    }
    final markdownText = output.markdown ?? output.latex;
    if (markdownText != null && markdownText.trim().isNotEmpty) {
      return NotebookMarkup(
        source: markdownText,
        palette: palette,
        baseDirectory: baseDirectory,
      );
    }
    return _monoText(output.plainText ?? '', palette.textPrimary);
  }

  Widget _streamText(NotebookOutput output) => _monoText(
        output.text.trimRight(),
        output.isStandardError ? palette.error : palette.textPrimary,
      );

  Widget _monoText(String text, Color color) {
    final lines = text.split('\n');
    final folded =
        !editor.outputExpanded && lines.length > notebookOutputPreviewLines;
    final shown =
        folded ? lines.take(notebookOutputPreviewLines).join('\n') : text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            shown,
            style: codeUiTextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ).copyWith(height: 1.5),
          ),
        ),
        if (folded ||
            editor.outputExpanded && lines.length > notebookOutputPreviewLines)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: CodeToolbarButton(
              palette: palette,
              tooltip:
                  folded ? 'Show the rest of this output' : 'Fold this output',
              icon: folded
                  ? Icons.unfold_more_rounded
                  : Icons.unfold_less_rounded,
              label: folded
                  ? 'Show ${lines.length - notebookOutputPreviewLines} more lines'
                  : 'Show less',
              onPressed: onToggleExpanded,
            ),
          ),
      ],
    );
  }

  Widget _errorPanel(NotebookOutput output) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: palette.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9),
          border: Border(
            left: BorderSide(color: palette.error, width: 2.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [output.errorName, output.errorValue]
                  .where((part) => part.isNotEmpty)
                  .join(': '),
              style: codeUiTextStyle(
                color: palette.error,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (output.traceback.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                output.errorText,
                style: codeUiTextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ).copyWith(height: 1.5),
              ),
            ],
          ],
        ),
      );
}
