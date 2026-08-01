import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_block_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_test_case.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// The tray of saved test cases under a piece of code.
///
/// It reads like a submission panel: a strip of cases, the input and the
/// expected answer for the selected one, and — once the code has been run —
/// what actually came back.
///
/// The panel sizes itself to whatever bounded box the host gives it, so the
/// same widget works under a resizable block and in a full window viewer.
class CodeTestCasePanel extends StatefulWidget {
  const CodeTestCasePanel({
    super.key,
    required this.palette,
    required this.testCases,
    required this.outcomes,
    required this.running,
    required this.canRun,
    required this.editable,
    required this.onChanged,
    required this.onRun,
    required this.onStop,
    required this.onClose,
  });

  final CodeBlockPalette palette;
  final List<CodeTestCase> testCases;

  /// The last outcome of each case, keyed by case id.
  final Map<String, CodeTestOutcome> outcomes;

  final bool running;

  /// Whether this language can be run at all.
  final bool canRun;

  final bool editable;
  final ValueChanged<List<CodeTestCase>> onChanged;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final VoidCallback onClose;

  @override
  State<CodeTestCasePanel> createState() => _CodeTestCasePanelState();
}

class _CodeTestCasePanelState extends State<CodeTestCasePanel> {
  /// The cases as they are being edited. Typing must not wait on the document
  /// transaction that saves them, so the panel holds them and reports later.
  late List<CodeTestCase> cases = [...widget.testCases];
  int selectedIndex = 0;
  Timer? saveTimer;

  @override
  void didUpdateWidget(covariant CodeTestCasePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only adopt the host's list when it says something different from what
    // is being typed, or every keystroke would be echoed back stale.
    final incoming = widget.testCases;
    final sameContent = incoming.length == cases.length &&
        List.generate(cases.length, (i) => incoming[i] == cases[i])
            .every((equal) => equal);
    if (!sameContent && !(saveTimer?.isActive ?? false)) {
      cases = [...incoming];
      selectedIndex =
          cases.isEmpty ? 0 : selectedIndex.clamp(0, cases.length - 1);
    }
  }

  @override
  void dispose() {
    // The last keystrokes must survive the panel being closed.
    if (saveTimer?.isActive ?? false) {
      saveTimer!.cancel();
      widget.onChanged(cases);
    }
    saveTimer = null;
    super.dispose();
  }

  void _commit(List<CodeTestCase> next, {bool immediate = false}) {
    setState(() => cases = next);
    saveTimer?.cancel();
    if (immediate) {
      widget.onChanged(next);
      return;
    }
    saveTimer = Timer(
      const Duration(milliseconds: 500),
      () => widget.onChanged(cases),
    );
  }

  void _addCase() {
    final next = [...cases, createCodeTestCase(cases.length)];
    selectedIndex = next.length - 1;
    _commit(next, immediate: true);
  }

  void _removeSelected() {
    if (cases.isEmpty) {
      return;
    }
    final next = [...cases]..removeAt(selectedIndex);
    selectedIndex = selectedIndex.clamp(0, next.isEmpty ? 0 : next.length - 1);
    _commit(next, immediate: true);
  }

  void _updateSelected(CodeTestCase updated) {
    final next = [...cases];
    next[selectedIndex] = updated;
    _commit(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    if (selectedIndex >= cases.length) {
      selectedIndex = cases.isEmpty ? 0 : cases.length - 1;
    }
    final selected = cases.isEmpty ? null : cases[selectedIndex];
    final outcome = selected == null ? null : widget.outcomes[selected.id];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: palette.terminal,
        borderRadius: BorderRadius.circular(codeSurfaceRadius),
        boxShadow: palette.nestedShadows,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(palette),
          if (cases.isNotEmpty) _buildCaseStrip(palette),
          Expanded(
            child: selected == null
                ? _buildEmptyState(palette)
                : _buildCaseEditor(palette, selected, outcome),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(CodeBlockPalette palette) {
    final summary = summarizeCodeTests(cases, widget.outcomes);
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.checklist_rounded, color: palette.textMuted, size: 14),
          const SizedBox(width: 7),
          Text(
            'Test cases',
            style: codeUiTextStyle(
              color: palette.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (summary != null) ...[
            const SizedBox(width: 8),
            Text(
              summary.allPassed
                  ? 'all ${summary.total} passed'
                  : '${summary.label} passed',
              style: codeUiTextStyle(
                color: summary.allPassed ? palette.success : palette.error,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          if (widget.editable) ...[
            CodeToolbarButton(
              palette: palette,
              tooltip: 'Add a test case',
              icon: Icons.add_rounded,
              onPressed: widget.running ? null : _addCase,
            ),
            const SizedBox(width: 3),
            CodeToolbarButton(
              palette: palette,
              tooltip: 'Delete this test case',
              icon: Icons.delete_outline_rounded,
              onPressed:
                  widget.running || cases.isEmpty ? null : _removeSelected,
            ),
            const SizedBox(width: 3),
          ],
          CodeToolbarButton(
            palette: palette,
            tooltip: widget.running ? 'Stop' : 'Run every test case',
            icon: widget.running
                ? Icons.stop_rounded
                : Icons.play_circle_outline_rounded,
            label: widget.running ? 'Stop' : 'Run tests',
            foregroundColor: widget.running ? palette.error : palette.accent,
            onPressed: widget.running
                ? widget.onStop
                : cases.isEmpty || !widget.canRun
                    ? null
                    : widget.onRun,
          ),
          const SizedBox(width: 3),
          CodeToolbarButton(
            palette: palette,
            tooltip: widget.running ? 'Stop the run first' : 'Close',
            icon: Icons.close_rounded,
            onPressed: widget.running ? null : widget.onClose,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildCaseStrip(CodeBlockPalette palette) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: cases.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) => Center(
          child: _CaseChip(
            palette: palette,
            label: cases[index].name,
            status: widget.outcomes[cases[index].id]?.status,
            selected: index == selectedIndex,
            onTap: () => setState(() => selectedIndex = index),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(CodeBlockPalette palette) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No test cases yet',
            style: codeUiTextStyle(
              color: palette.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.editable)
            CodeToolbarButton(
              palette: palette,
              tooltip: 'Add a test case',
              icon: Icons.add_rounded,
              label: 'Add a case',
              foregroundColor: palette.accent,
              onPressed: _addCase,
            ),
        ],
      ),
    );
  }

  Widget _buildCaseEditor(
    CodeBlockPalette palette,
    CodeTestCase testCase,
    CodeTestOutcome? outcome,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(palette: palette, text: 'Input'),
          const SizedBox(height: 5),
          _CodeField(
            key: ValueKey('${testCase.id}-input'),
            palette: palette,
            initialValue: testCase.input,
            enabled: widget.editable && !widget.running,
            hintText: 'Typed into the program on stdin',
            onChanged: (value) =>
                _updateSelected(testCase.copyWith(input: value)),
          ),
          const SizedBox(height: 10),
          _FieldLabel(palette: palette, text: 'Expected output'),
          const SizedBox(height: 5),
          _CodeField(
            key: ValueKey('${testCase.id}-expected'),
            palette: palette,
            initialValue: testCase.expectedOutput,
            enabled: widget.editable && !widget.running,
            hintText: 'What the program should print',
            onChanged: (value) =>
                _updateSelected(testCase.copyWith(expectedOutput: value)),
          ),
          if (outcome != null) ...[
            const SizedBox(height: 12),
            _OutcomeView(palette: palette, outcome: outcome),
          ],
        ],
      ),
    );
  }
}

class _CaseChip extends StatefulWidget {
  const _CaseChip({
    required this.palette,
    required this.label,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final CodeBlockPalette palette;
  final String label;
  final CodeTestStatus? status;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CaseChip> createState() => _CaseChipState();
}

class _CaseChipState extends State<_CaseChip> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final dotColor = switch (widget.status) {
      CodeTestStatus.passed => palette.success,
      CodeTestStatus.failed || CodeTestStatus.errored => palette.error,
      CodeTestStatus.running => palette.accent,
      _ => palette.textMuted.withValues(alpha: 0.55),
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: codeBlockAnimationDuration,
          curve: AppFlowyMotion.standardCurve,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.selected
                : hovering
                    ? palette.hover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.status == CodeTestStatus.running)
                SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: dotColor,
                  ),
                )
              else
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: codeUiTextStyle(
                  color: widget.selected
                      ? palette.textPrimary
                      : palette.textSecondary,
                  fontSize: 11,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.palette, required this.text});

  final CodeBlockPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: codeUiTextStyle(
          color: palette.textMuted,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ).copyWith(letterSpacing: 0.6),
      );
}

/// A small monospaced box for one side of a case.
class _CodeField extends StatelessWidget {
  const _CodeField({
    super.key,
    required this.palette,
    required this.initialValue,
    required this.enabled,
    required this.hintText,
    required this.onChanged,
  });

  final CodeBlockPalette palette;
  final String initialValue;
  final bool enabled;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = codeUiTextStyle(
      color: palette.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ).copyWith(height: 1.45);

    return TextFormField(
      initialValue: initialValue,
      enabled: enabled,
      minLines: 2,
      maxLines: 6,
      style: style,
      cursorColor: palette.accent,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: palette.input,
        // Material blends its hover colour over the fill, which greys the
        // whole box out under the pointer.
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        hintText: hintText,
        hintStyle: style.copyWith(color: palette.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.border, width: 0.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.accent),
        ),
      ),
    );
  }
}

/// What came back from the last run of one case.
class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.palette, required this.outcome});

  final CodeBlockPalette palette;
  final CodeTestOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (outcome.status) {
      CodeTestStatus.passed => ('Accepted', palette.success),
      CodeTestStatus.failed => ('Wrong answer', palette.error),
      CodeTestStatus.errored => ('Runtime error', palette.error),
      CodeTestStatus.running => ('Running', palette.accent),
      CodeTestStatus.pending => ('Not run', palette.textMuted),
    };
    final details = [
      outcome.notice.trim(),
      outcome.errorOutput.trim(),
    ].where((text) => text.isNotEmpty).join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: codeUiTextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (outcome.isFinished) ...[
              const SizedBox(width: 8),
              Text(
                '${outcome.duration.inMilliseconds} ms',
                style: codeUiTextStyle(
                  color: palette.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        if (outcome.status != CodeTestStatus.running) ...[
          const SizedBox(height: 10),
          _FieldLabel(palette: palette, text: 'Your output'),
          const SizedBox(height: 5),
          _ReadOnlyBox(
            palette: palette,
            text: outcome.output.isEmpty
                ? 'The program printed nothing.'
                : outcome.output,
            muted: outcome.output.isEmpty,
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 10),
            _FieldLabel(palette: palette, text: 'Errors'),
            const SizedBox(height: 5),
            _ReadOnlyBox(
              palette: palette,
              text: details,
              textColor: palette.error,
            ),
          ],
        ],
      ],
    );
  }
}

class _ReadOnlyBox extends StatelessWidget {
  const _ReadOnlyBox({
    required this.palette,
    required this.text,
    this.muted = false,
    this.textColor,
  });

  final CodeBlockPalette palette;
  final String text;
  final bool muted;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: palette.input,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border, width: 0.5),
      ),
      child: SelectableText(
        text,
        style: codeUiTextStyle(
          color: textColor ?? (muted ? palette.textMuted : palette.textPrimary),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ).copyWith(height: 1.45),
      ),
    );
  }
}
