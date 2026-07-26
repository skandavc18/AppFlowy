import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

const codeBlockAnimationDuration = AppFlowyMotion.standard;

/// A code block is framed exactly like every other embedded document, so a
/// block in the editor and a code file opened in the viewer are the same
/// object seen in two places.
const codeBlockCornerRadius = EditorSurfaceStyle.embedCornerRadius;

enum CodeRuntime {
  /// Runs inside the WebView sandbox, with no toolchain of any kind.
  javascript,

  /// Runs through a compiler or interpreter installed on this computer.
  local,

  unsupported;
}

CodeRuntime codeRuntimeForName(String name) {
  return switch (p.extension(name).toLowerCase()) {
    '.js' || '.mjs' || '.cjs' => CodeRuntime.javascript,
    _ => localToolchainForName(name) == null
        ? CodeRuntime.unsupported
        : CodeRuntime.local,
  };
}

class SandboxedCodeRunner extends StatefulWidget {
  const SandboxedCodeRunner({
    super.key,
    required this.code,
    required this.fileName,
    required this.child,
    required this.language,
    required this.showLineNumbers,
    required this.onLanguageChanged,
    required this.onToggleLineNumbers,
    this.onDownload,
    this.toolbarTrailing,
    this.expandEditor = false,
    this.displayName,
    this.contentPadding = EdgeInsets.zero,
    this.framed = true,
    this.initiallyCollapsed = false,
    this.onHeaderInteractionChanged,
    this.onTerminalFocusChanged,
  });

  final String code;
  final String fileName;
  final Widget child;
  final String language;
  final bool showLineNumbers;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onToggleLineNumbers;
  final VoidCallback? onDownload;
  final Widget? toolbarTrailing;
  final bool expandEditor;
  final String? displayName;
  final EdgeInsets contentPadding;
  final bool framed;
  final bool initiallyCollapsed;
  final ValueChanged<bool>? onHeaderInteractionChanged;

  /// Fires when the terminal's input takes or loses focus.
  ///
  /// A host embedded in the document editor uses this to drop the document
  /// selection, so keys typed at the prompt are not also read as editing
  /// commands.
  final ValueChanged<bool>? onTerminalFocusChanged;

  @override
  State<SandboxedCodeRunner> createState() => _SandboxedCodeRunnerState();
}

class _SandboxedCodeRunnerState extends State<SandboxedCodeRunner> {
  final inputController = TextEditingController();
  final inputFocusNode = FocusNode();
  final terminalScrollController = ScrollController();
  InAppWebViewController? webViewController;
  LocalCodeRunner? localRunner;
  Timer? copyFeedbackTimer;
  String output = '';
  String errorOutput = '';
  bool running = false;
  bool terminalVisible = false;
  bool copied = false;
  late bool collapsed;

  CodeRuntime get runtime => codeRuntimeForName(widget.fileName);

  LocalToolchain? get toolchain => localToolchainForName(widget.fileName);

  /// Local programs read their input as they go, so the terminal takes one
  /// line at a time instead of a block of text handed over up front.
  bool get isInteractive => runtime == CodeRuntime.local;

  @override
  void initState() {
    super.initState();
    collapsed = widget.initiallyCollapsed;
  }

  @override
  void didUpdateWidget(covariant SandboxedCodeRunner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (codeRuntimeForName(oldWidget.fileName) == CodeRuntime.javascript &&
        runtime != CodeRuntime.javascript) {
      webViewController = null;
      running = false;
    }
  }

  @override
  void dispose() {
    localRunner?.cancel();
    copyFeedbackTimer?.cancel();
    terminalScrollController.dispose();
    inputFocusNode.dispose();
    inputController.dispose();
    super.dispose();
  }

  /// Shows text the moment the program prints it, and keeps the newest line in
  /// view the way a terminal does.
  void _appendOutput(String chunk, {required bool isError}) {
    if (!mounted || chunk.isEmpty) {
      return;
    }
    setState(() {
      if (isError) {
        errorOutput += chunk;
      } else {
        output += chunk;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (terminalScrollController.hasClients) {
        terminalScrollController
            .jumpTo(terminalScrollController.position.maxScrollExtent);
      }
    });
  }

  /// Answers the prompt the program is waiting on.
  void _submitInput(String value) {
    final runner = localRunner;
    if (runner == null || !runner.acceptsInput) {
      return;
    }
    runner.sendLine(value);
    inputController.clear();
    // A pipe does not echo, so the transcript would otherwise lose the answer.
    _appendOutput('$value\n', isError: false);
    inputFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _buildRunner(
        context,
        expandEditor: widget.expandEditor || constraints.hasTightHeight,
      ),
    );
  }

  Widget _buildRunner(
    BuildContext context, {
    required bool expandEditor,
  }) {
    final selectedLanguage = normalizeCodeLanguage(widget.language);
    final languages = {
      ...codeBlockSupportedLanguages,
      selectedLanguage,
    }.toList();
    final materialTheme = Theme.of(context);
    final appFlowyTheme = AppFlowyTheme.of(context);
    final palette = _CodeBlockPalette.resolve(context);
    final editor = Padding(
      padding: widget.contentPadding,
      child: widget.child,
    );
    final body = ColoredBox(
      color: palette.surface,
      child: Column(
        mainAxisSize: expandEditor ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (expandEditor) Expanded(child: editor) else editor,
          if (runtime == CodeRuntime.javascript) buildSandbox(),
          if (terminalVisible) _buildTerminal(context, palette),
        ],
      ),
    );
    final animatedBody = TweenAnimationBuilder<double>(
      tween: Tween(end: collapsed ? 0 : 1),
      duration: codeBlockAnimationDuration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: value,
          child: IgnorePointer(
            ignoring: collapsed,
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        ),
      ),
      child: body,
    );
    Widget runner = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => widget.onHeaderInteractionChanged?.call(true),
          onExit: (_) => widget.onHeaderInteractionChanged?.call(false),
          child: _CodeBlockHeader(
            palette: palette,
            selectedLanguage: selectedLanguage,
            languages: languages,
            displayName: widget.displayName,
            showLineNumbers: widget.showLineNumbers,
            running: running,
            copied: copied,
            collapsed: collapsed,
            runtime: runtime,
            toolchain: toolchain,
            onLanguageChanged: widget.onLanguageChanged,
            onToggleLineNumbers: widget.onToggleLineNumbers,
            onRun: running ? _stop : _run,
            onCopy: _copyCode,
            onToggleCollapsed: () => setState(() => collapsed = !collapsed),
            onDownload: widget.onDownload,
            trailing: widget.toolbarTrailing,
          ),
        ),
        if (expandEditor) Expanded(child: animatedBody) else animatedBody,
      ],
    );
    if (widget.framed) {
      runner = ViewerCard(
        color: palette.surface,
        child: runner,
      );
    } else {
      runner = ColoredBox(color: palette.surface, child: runner);
    }

    return Theme(
      data: materialTheme.copyWith(
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        textSelectionTheme: TextSelectionThemeData(
          selectionColor: appFlowyTheme.fillColorScheme.textSelect,
          selectionHandleColor: appFlowyTheme.iconColorScheme.secondary,
        ),
      ),
      child: runner,
    );
  }

  Future<void> _copyCode() async {
    copyFeedbackTimer?.cancel();
    setState(() => copied = true);
    copyFeedbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => copied = false);
      }
    });
    await Clipboard.setData(ClipboardData(text: widget.code));
  }

  Widget buildSandbox() {
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0,
        child: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: '''
<!doctype html>
<meta http-equiv="Content-Security-Policy"
 content="default-src 'none'; script-src 'unsafe-inline' blob:; worker-src blob:; connect-src 'none'">
''',
          ),
          initialSettings: InAppWebViewSettings(transparentBackground: true),
          onWebViewCreated: (controller) => webViewController = controller,
        ),
      ),
    );
  }

  Widget _buildTerminal(
    BuildContext context,
    _CodeBlockPalette palette,
  ) {
    // One mono face for the transcript and the prompt, matching the code.
    final mono = _codeUiTextStyle(
      color: palette.textPrimary,
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
    ).copyWith(height: 1.5);
    final acceptingInput =
        isInteractive ? (localRunner?.acceptsInput ?? false) : true;
    final status = !running
        ? ''
        : acceptingInput
            ? 'waiting for input'
            : 'running';
    final hint = isInteractive
        ? (acceptingInput ? '' : 'run the code to use the terminal')
        : 'one value per line';
    return FocusScope(
      skipTraversal: true,
      onFocusChange: widget.onTerminalFocusChanged,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          color: palette.terminal,
          border: Border(
            top: BorderSide(color: palette.divider),
          ),
        ),
        // Stretch, or the transcript shrink-wraps and floats in the middle
        // instead of starting at the left edge like a terminal.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.terminal_rounded,
                    color: palette.textMuted,
                    size: 14,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Terminal',
                    style: _codeUiTextStyle(
                      color: palette.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (status.isNotEmpty) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            acceptingInput ? palette.accent : palette.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: _codeUiTextStyle(
                        color: palette.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (isInteractive && running) ...[
                    _CodeToolbarButton(
                      palette: palette,
                      tooltip: 'Close the input stream (Ctrl+D)',
                      icon: Icons.block_rounded,
                      label: 'EOF',
                      onPressed: acceptingInput
                          ? () => setState(() => localRunner?.endInput())
                          : null,
                    ),
                    const SizedBox(width: 3),
                  ],
                  _CodeToolbarButton(
                    palette: palette,
                    tooltip:
                        running ? 'Stop execution first' : 'Close terminal',
                    icon: Icons.close_rounded,
                    onPressed: running
                        ? null
                        : () => setState(() => terminalVisible = false),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Divider(height: 1, color: palette.divider),
            Expanded(
              // Clicking anywhere in the pane puts the caret back on the
              // prompt, the way clicking a terminal window does.
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: inputFocusNode.requestFocus,
                child: SingleChildScrollView(
                  controller: terminalScrollController,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (output.isNotEmpty || errorOutput.isNotEmpty)
                        SelectableText.rich(
                          TextSpan(
                            style: mono,
                            children: [
                              TextSpan(text: output),
                              if (errorOutput.isNotEmpty)
                                TextSpan(
                                  text: errorOutput,
                                  style: TextStyle(color: palette.error),
                                ),
                            ],
                          ),
                        ),
                      // The prompt lives at the end of the transcript rather
                      // than in a form pinned to the bottom.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r'$',
                            style: mono.copyWith(
                              color: palette.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: inputController,
                              focusNode: inputFocusNode,
                              maxLines: isInteractive ? 1 : 3,
                              minLines: 1,
                              textInputAction: TextInputAction.send,
                              onSubmitted: isInteractive ? _submitInput : null,
                              style: mono,
                              cursorColor: palette.accent,
                              cursorWidth: 7,
                              cursorRadius: Radius.zero,
                              decoration: InputDecoration(
                                isCollapsed: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                                hintText: hint,
                                hintStyle: mono.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run() async {
    if (runtime == CodeRuntime.local) {
      return _runLocally();
    }
    final controller = webViewController;
    if (controller == null) {
      setState(() {
        terminalVisible = true;
        errorOutput = 'The sandbox is still starting. Try again.\n';
      });
      return;
    }
    setState(() {
      running = true;
      terminalVisible = true;
      output = '';
      errorOutput = '';
    });
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: _javascriptWorkerFunction,
        arguments: {
          'code': widget.code,
          'input': inputController.text,
        },
      ).timeout(const Duration(seconds: 8));
      if (!mounted) {
        return;
      }
      final value = result?.value;
      if (result?.error != null) {
        throw StateError(result!.error!);
      }
      if (value is Map) {
        setState(() {
          output = value['stdout']?.toString() ?? '';
          errorOutput = value['stderr']?.toString() ?? '';
        });
      } else {
        setState(() => errorOutput = 'The sandbox returned no result.\n');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => errorOutput = 'Execution timed out after 8 seconds.\n');
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => errorOutput = '$error\n');
      }
    } finally {
      if (mounted) {
        setState(() => running = false);
      }
    }
  }

  /// Compiles and runs the code with the toolchain installed on this computer.
  ///
  /// Nothing is sent anywhere: there is no execution service to reach.
  Future<void> _runLocally() async {
    final toolchain = this.toolchain;
    if (toolchain == null) {
      return;
    }
    // A toolchain installed since the last attempt should be picked up.
    clearExecutableCache();
    final runner = LocalCodeRunner();
    localRunner = runner;
    setState(() {
      running = true;
      terminalVisible = true;
      output = '';
      errorOutput = '';
    });
    inputFocusNode.requestFocus();
    try {
      final result = await runner.run(
        toolchain: toolchain,
        code: widget.code,
        onStdout: (chunk) => _appendOutput(chunk, isError: false),
        onStderr: (chunk) => _appendOutput(chunk, isError: true),
      );
      if (!mounted) {
        return;
      }
      _appendOutput(result.notice, isError: true);
    } on Exception catch (error) {
      if (mounted) {
        _appendOutput('$error\n', isError: true);
      }
    } finally {
      localRunner = null;
      if (mounted) {
        setState(() => running = false);
      }
    }
  }

  Future<void> _stop() async {
    if (runtime == CodeRuntime.local) {
      localRunner?.cancel();
      return;
    }
    await webViewController?.reload();
    if (mounted) {
      setState(() {
        running = false;
        errorOutput += 'Execution stopped.\n';
      });
    }
  }
}

class _CodeBlockHeader extends StatelessWidget {
  const _CodeBlockHeader({
    required this.palette,
    required this.selectedLanguage,
    required this.languages,
    required this.displayName,
    required this.showLineNumbers,
    required this.running,
    required this.copied,
    required this.collapsed,
    required this.runtime,
    required this.toolchain,
    required this.onLanguageChanged,
    required this.onToggleLineNumbers,
    required this.onRun,
    required this.onCopy,
    required this.onToggleCollapsed,
    required this.onDownload,
    required this.trailing,
  });

  final _CodeBlockPalette palette;
  final String selectedLanguage;
  final List<String> languages;
  final String? displayName;
  final bool showLineNumbers;
  final bool running;
  final bool copied;
  final bool collapsed;
  final CodeRuntime runtime;
  final LocalToolchain? toolchain;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onToggleLineNumbers;
  final VoidCallback onRun;
  final VoidCallback onCopy;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onDownload;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final veryCompact = constraints.maxWidth < 380;
        final filename = displayName?.trim();
        final canRun = runtime != CodeRuntime.unsupported;
        final runTooltip = switch (runtime) {
          CodeRuntime.unsupported => 'Preview only',
          _ when running => 'Stop',
          CodeRuntime.local when toolchain?.isInstalled == false =>
            'Run with ${toolchain!.label} (not found on PATH)',
          CodeRuntime.local => 'Run with ${toolchain!.label}',
          CodeRuntime.javascript => 'Run',
        };

        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.header,
            // Depth instead of an outline, matching the shared document
            // header so a code block reads as the same kind of surface.
            boxShadow: DocumentViewportStyle.of(context).chromeShadow,
          ),
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: codeBlockAnimationDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: veryCompact && copied
                        ? Padding(
                            key: const ValueKey('compact-copy-feedback'),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Copied ✓',
                              style: _codeUiTextStyle(
                                color: palette.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : _CodeLanguageMenu(
                            key: const ValueKey('code-language-menu'),
                            palette: palette,
                            selectedLanguage: selectedLanguage,
                            languages: languages,
                            maxLabelWidth: veryCompact ? 48 : 92,
                            onSelected: onLanguageChanged,
                          ),
                  ),
                  if (!compact && filename != null && filename.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _HeaderDivider(palette: palette),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.code_rounded,
                      size: 14,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _codeUiTextStyle(
                          color: palette.textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  // The controls stay with the identity they belong to. Pushed
                  // to the far edge they drift half a window away from the
                  // language picker on a wide editor. Flexible so the gap
                  // collapses first when the block is narrow.
                  const Flexible(child: SizedBox(width: 14)),
                  if (!veryCompact) ...[
                    _CodeToolbarButton(
                      palette: palette,
                      tooltip: showLineNumbers
                          ? 'Hide line numbers'
                          : 'Show line numbers',
                      icon: Icons.format_list_numbered_rounded,
                      selected: showLineNumbers,
                      onPressed: onToggleLineNumbers,
                    ),
                    const SizedBox(width: 3),
                  ],
                  _CodeToolbarButton(
                    palette: palette,
                    tooltip: runTooltip,
                    icon:
                        running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    label: compact ? null : (running ? 'Stop' : 'Run'),
                    foregroundColor: running ? palette.error : palette.accent,
                    onPressed: canRun ? onRun : null,
                  ),
                  const SizedBox(width: 3),
                  _CodeToolbarButton(
                    palette: palette,
                    tooltip: copied
                        ? 'Copied ✓'
                        : LocaleKeys.document_codeBlock_copyTooltip.tr(),
                    icon: copied
                        ? Icons.check_rounded
                        : Icons.content_copy_outlined,
                    label: copied
                        ? veryCompact
                            ? null
                            : 'Copied'
                        : compact
                            ? null
                            : LocaleKeys.editor_copy.tr(),
                    foregroundColor:
                        copied ? palette.success : palette.textSecondary,
                    onPressed: onCopy,
                  ),
                  if (onDownload != null) ...[
                    const SizedBox(width: 3),
                    _CodeToolbarButton(
                      palette: palette,
                      tooltip: 'Download code',
                      icon: Icons.download_outlined,
                      onPressed: onDownload,
                    ),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(width: 3),
                    trailing!,
                  ],
                  const SizedBox(width: 3),
                  _CodeToolbarButton(
                    palette: palette,
                    tooltip: collapsed ? 'Expand code' : 'Collapse code',
                    icon: collapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    onPressed: onToggleCollapsed,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CodeLanguageMenu extends StatelessWidget {
  const _CodeLanguageMenu({
    super.key,
    required this.palette,
    required this.selectedLanguage,
    required this.languages,
    required this.maxLabelWidth,
    required this.onSelected,
  });

  final _CodeBlockPalette palette;
  final String selectedLanguage;
  final List<String> languages;
  final double maxLabelWidth;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selectedLanguage == 'auto'
        ? LocaleKeys.document_codeBlock_language_auto.tr()
        : _languageLabel(selectedLanguage);

    return Tooltip(
      message: 'Select language',
      child: PopupMenuButton<String>(
        tooltip: '',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        color: palette.menu,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        constraints: const BoxConstraints(
          minWidth: 176,
          maxWidth: 208,
          maxHeight: 320,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: palette.border, width: 0.5),
        ),
        popUpAnimationStyle: AnimationStyle(
          duration: codeBlockAnimationDuration,
          reverseDuration: codeBlockAnimationDuration,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final language in languages)
            PopupMenuItem<String>(
              value: language,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: language == selectedLanguage
                        ? Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: palette.accent,
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    language == 'auto'
                        ? LocaleKeys.document_codeBlock_language_auto.tr()
                        : _languageLabel(language),
                    style: _codeUiTextStyle(
                      color: language == selectedLanguage
                          ? palette.textPrimary
                          : palette.textSecondary,
                      fontSize: 11.5,
                      fontWeight: language == selectedLanguage
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: _HoverSurface(
          palette: palette,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.code_rounded, size: 14, color: palette.textMuted),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _codeUiTextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverSurface extends StatefulWidget {
  const _HoverSurface({required this.palette, required this.child});

  final _CodeBlockPalette palette;
  final Widget child;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: AnimatedContainer(
        duration: codeBlockAnimationDuration,
        curve: AppFlowyMotion.standardCurve,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hovering ? widget.palette.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: widget.child,
      ),
    );
  }
}

class _CodeToolbarButton extends StatefulWidget {
  const _CodeToolbarButton({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.label,
    this.selected = false,
    this.foregroundColor,
  });

  final _CodeBlockPalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;
  final bool selected;
  final Color? foregroundColor;

  @override
  State<_CodeToolbarButton> createState() => _CodeToolbarButtonState();
}

class _CodeToolbarButtonState extends State<_CodeToolbarButton> {
  bool hovering = false;
  bool focused = false;
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final foreground = widget.foregroundColor ?? widget.palette.textSecondary;
    final background = pressing
        ? Color.alphaBlend(
            widget.palette.textPrimary.withValues(alpha: 0.06),
            widget.palette.hover,
          )
        : widget.selected
            ? widget.palette.selected
            : hovering || focused
                ? widget.palette.hover
                : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        child: AnimatedOpacity(
          duration: codeBlockAnimationDuration,
          opacity: enabled ? 1 : 0.42,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onHover:
                  enabled ? (value) => setState(() => hovering = value) : null,
              onFocusChange:
                  enabled ? (value) => setState(() => focused = value) : null,
              onHighlightChanged:
                  enabled ? (value) => setState(() => pressing = value) : null,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              borderRadius: BorderRadius.circular(7),
              child: AnimatedContainer(
                duration: codeBlockAnimationDuration,
                curve: AppFlowyMotion.standardCurve,
                height: 28,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.label == null ? 7 : 8,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: AnimatedSwitcher(
                  duration: codeBlockAnimationDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: Row(
                    key: ValueKey((widget.icon, widget.label)),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 15, color: foreground),
                      if (widget.label != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          widget.label!,
                          style: _codeUiTextStyle(
                            color: foreground,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider({required this.palette});

  final _CodeBlockPalette palette;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 14,
        child: VerticalDivider(
          width: 0.5,
          thickness: 0.5,
          color: palette.divider,
        ),
      );
}

/// The single surface every code layer paints on.
///
/// The header, the body and the code file editor all share it, so a code block
/// reads as one uniform card instead of a toolbar stacked on a page — and a
/// block in the editor matches a code file opened in the viewer exactly.
Color codeBlockSurfaceColor(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return const Color(0xFF18191D);
  }
  if (PaperTheme.isEnabled(context)) {
    return PaperTheme.codeBlockBackground;
  }
  return PremiumThemeExtension.maybeOf(context)?.surface ??
      const Color(0xFFFAF9F6);
}

class _CodeBlockPalette {
  const _CodeBlockPalette({
    required this.surface,
    required this.header,
    required this.terminal,
    required this.menu,
    required this.input,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.hover,
    required this.selected,
    required this.accent,
    required this.success,
    required this.error,
    required this.shadows,
  });

  factory _CodeBlockPalette.resolve(BuildContext context) {
    final materialTheme = Theme.of(context);
    final appFlowyTheme = AppFlowyTheme.of(context);
    final brightness = materialTheme.brightness;
    final isPaper = PaperTheme.isEnabled(context);
    final premiumPalette = PremiumThemeExtension.maybeOf(context);
    final surface = codeBlockSurfaceColor(context);

    if (brightness == Brightness.dark) {
      return _CodeBlockPalette(
        surface: surface,
        header: surface,
        terminal: const Color(0xFF141519),
        menu: const Color(0xFF202126),
        input: const Color(0xFF1E1F24),
        border: const Color(0x24FFFFFF),
        divider: const Color(0x14FFFFFF),
        textPrimary: const Color(0xFFE7E8EC),
        textSecondary: const Color(0xFFB0B3BC),
        textMuted: const Color(0xFF737780),
        hover: const Color(0x12FFFFFF),
        selected: const Color(0x267AA2F7),
        accent: const Color(0xFF8AB4F8),
        success: const Color(0xFF86D9A2),
        error: appFlowyTheme.textColorScheme.error,
        shadows: const [
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 18,
            offset: Offset(0, 7),
            spreadRadius: -8,
          ),
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 5,
            offset: Offset(0, 2),
            spreadRadius: -2,
          ),
        ],
      );
    }

    if (isPaper) {
      return _CodeBlockPalette(
        surface: surface,
        header: surface,
        terminal: PaperTheme.editorPreviewBackground,
        menu: PaperTheme.popupBackground,
        input: PaperTheme.controlBackground,
        border: PaperTheme.codeBlockBorder,
        divider: PaperTheme.codeBlockBorder.withValues(alpha: 0.7),
        textPrimary: appFlowyTheme.textColorScheme.primary,
        textSecondary: appFlowyTheme.textColorScheme.secondary,
        textMuted: appFlowyTheme.textColorScheme.tertiary,
        hover: PaperTheme.hoverOverlay,
        selected: PaperTheme.selectedOverlay,
        accent: PaperTheme.accent,
        success: const Color(0xFF53734F),
        error: appFlowyTheme.textColorScheme.error,
        shadows: const [
          BoxShadow(
            color: Color(0x123F352A),
            blurRadius: 14,
            offset: Offset(0, 5),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: Color(0x0A3F352A),
            blurRadius: 4,
            offset: Offset(0, 1),
            spreadRadius: -1,
          ),
        ],
      );
    }

    final border =
        premiumPalette?.border ?? appFlowyTheme.borderColorScheme.primary;

    return _CodeBlockPalette(
      surface: surface,
      header: surface,
      terminal: EditorSurfaceStyle.previewBackgroundFor(
        brightness,
        premiumPalette?.canvas ?? const Color(0xFFF1F0EC),
        isPaper: isPaper,
      ),
      menu: premiumPalette?.floatingSurface ??
          appFlowyTheme.surfaceColorScheme.primary,
      input: premiumPalette?.mutedSurface ??
          appFlowyTheme.fillColorScheme.contentHover,
      border: border,
      divider: border.withValues(alpha: 0.7),
      textPrimary: appFlowyTheme.textColorScheme.primary,
      textSecondary: appFlowyTheme.textColorScheme.secondary,
      textMuted: appFlowyTheme.textColorScheme.tertiary,
      hover:
          premiumPalette?.hover ?? appFlowyTheme.fillColorScheme.contentHover,
      selected:
          premiumPalette?.selected ?? appFlowyTheme.fillColorScheme.themeSelect,
      accent:
          premiumPalette?.accent ?? appFlowyTheme.fillColorScheme.themeThick,
      success: appFlowyTheme.textColorScheme.success,
      error: appFlowyTheme.textColorScheme.error,
      shadows: [
        BoxShadow(
          color: premiumPalette?.shadow ?? const Color(0x123F352A),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: -5,
        ),
        BoxShadow(
          color: (premiumPalette?.shadow ?? const Color(0x123F352A))
              .withValues(alpha: 0.04),
          blurRadius: 7,
          offset: const Offset(0, 1),
          spreadRadius: -1,
        ),
      ],
    );
  }

  final Color surface;
  final Color header;
  final Color terminal;
  final Color menu;
  final Color input;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color hover;
  final Color selected;
  final Color accent;
  final Color success;
  final Color error;
  final List<BoxShadow> shadows;
}

TextStyle _codeUiTextStyle({
  required Color color,
  required double fontSize,
  required FontWeight fontWeight,
}) =>
    getGoogleFontSafely(
      'JetBrains Mono',
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontColor: color,
      letterSpacing: -0.1,
    ).copyWith(
      fontFamilyFallback: const ['Geist Mono', 'RobotoMono', 'monospace'],
    );

const codeBlockSupportedLanguages = [
  'auto',
  'javascript',
  'typescript',
  'python',
  'c',
  'cpp',
  'java',
  'kotlin',
  'rust',
  'dart',
  'go',
  'json',
  'html',
  'css',
  'shell',
  'sql',
  'text',
];

String _languageLabel(String language) => language.isEmpty
    ? language
    : language[0].toUpperCase() + language.substring(1);

String codeLanguageForName(String name) {
  return switch (p.extension(name).toLowerCase()) {
    '.js' || '.mjs' || '.cjs' => 'javascript',
    '.ts' || '.tsx' => 'typescript',
    '.py' => 'python',
    '.c' || '.h' => 'c',
    '.cc' || '.cpp' || '.cxx' || '.hpp' => 'cpp',
    '.java' => 'java',
    '.kt' || '.kts' => 'kotlin',
    '.rs' => 'rust',
    '.dart' => 'dart',
    '.go' => 'go',
    '.json' => 'json',
    '.html' || '.htm' => 'html',
    '.css' || '.scss' || '.sass' || '.less' => 'css',
    '.sh' => 'shell',
    '.ps1' => 'powershell',
    '.sql' => 'sql',
    _ => 'text',
  };
}

String fileNameForCodeLanguage(String language) {
  final normalizedLanguage = normalizeCodeLanguage(language);
  final extension = switch (normalizedLanguage) {
    'auto' => '',
    'javascript' => 'js',
    'typescript' => 'ts',
    'python' => 'py',
    'cpp' => 'cpp',
    'kotlin' => 'kt',
    'rust' => 'rs',
    'shell' => 'sh',
    'powershell' => 'ps1',
    'text' => 'txt',
    _ => normalizedLanguage,
  };
  return extension.isEmpty ? 'main' : 'main.$extension';
}

const _javascriptWorkerFunction = r'''
const workerSource = `
self.onmessage = async (event) => {
  const lines = event.data.input.split(/\\r?\\n/);
  let lineIndex = 0;
  const stdout = [];
  const stderr = [];
  const format = (value) => {
    if (typeof value === 'string') return value;
    try { return JSON.stringify(value); } catch (_) { return String(value); }
  };
  const console = {
    log: (...values) => stdout.push(values.map(format).join(' ')),
    info: (...values) => stdout.push(values.map(format).join(' ')),
    warn: (...values) => stderr.push(values.map(format).join(' ')),
    error: (...values) => stderr.push(values.map(format).join(' '))
  };
  const readLine = () => lines[lineIndex++] ?? null;
  try {
    const fn = new Function(
      'console',
      'readLine',
      'stdin',
      '"use strict"; return (async () => {\\n' + event.data.code + '\\n})()'
    );
    const value = await fn(console, readLine, event.data.input);
    if (value !== undefined) stdout.push(format(value));
  } catch (error) {
    stderr.push(error && error.stack ? error.stack : String(error));
  }
  self.postMessage({
    stdout: stdout.length ? stdout.join('\\n') + '\\n' : '',
    stderr: stderr.length ? stderr.join('\\n') + '\\n' : ''
  });
};`;
const workerUrl = URL.createObjectURL(
  new Blob([workerSource], {type: 'text/javascript'})
);
const worker = new Worker(workerUrl);
return await new Promise((resolve) => {
  const timer = setTimeout(() => {
    worker.terminate();
    URL.revokeObjectURL(workerUrl);
    resolve({stdout: '', stderr: 'Execution timed out after 5 seconds.\\n'});
  }, 5000);
  worker.onmessage = (event) => {
    clearTimeout(timer);
    worker.terminate();
    URL.revokeObjectURL(workerUrl);
    resolve(event.data);
  };
  worker.onerror = (event) => {
    clearTimeout(timer);
    worker.terminate();
    URL.revokeObjectURL(workerUrl);
    resolve({stdout: '', stderr: event.message + '\\n'});
  };
  worker.postMessage({code, input});
});
''';
