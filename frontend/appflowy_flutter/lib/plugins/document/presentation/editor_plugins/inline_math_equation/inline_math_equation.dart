import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_source_editor.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';

class InlineMathEquationKeys {
  const InlineMathEquationKeys._();

  static const formula = 'formula';
}

class InlineMathEquation extends StatefulWidget {
  const InlineMathEquation({
    super.key,
    required this.formula,
    required this.node,
    required this.index,
    this.textStyle,
  });

  final Node node;
  final int index;
  final String formula;
  final TextStyle? textStyle;

  @override
  State<InlineMathEquation> createState() => _InlineMathEquationState();
}

class _InlineMathEquationState extends State<InlineMathEquation> {
  final popoverController = PopoverController();

  @override
  Widget build(BuildContext context) {
    // Captured here: the popover is built under the overlay, where the
    // document's providers are out of reach.
    final editorState = context.read<EditorState>();
    return _IgnoreParentPointer(
      child: AppFlowyPopover(
        controller: popoverController,
        direction: PopoverDirection.bottomWithLeftAligned,
        popupBuilder: (_) {
          return MathInputTextField(
            initialText: widget.formula,
            editorState: editorState,
            onSubmit: (value) async {
              popoverController.close();
              if (value == widget.formula) {
                return;
              }
              final transaction = editorState.transaction
                ..formatText(widget.node, widget.index, 1, {
                  InlineMathEquationKeys.formula: value,
                });
              await editorState.apply(transaction);
            },
          );
        },
        offset: const Offset(0, 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: _buildMathEquation(context),
          ),
        ),
      ),
    );
  }

  Widget _buildMathEquation(BuildContext context) {
    final theme = Theme.of(context);
    final longEq = Math.tex(
      widget.formula,
      textStyle: widget.textStyle,
      mathStyle: MathStyle.text,
      options: MathOptions(
        style: MathStyle.text,
        mathFontOptions: const FontOptions(
          fontShape: FontStyle.italic,
        ),
        fontSize: widget.textStyle?.fontSize ?? 14.0,
        color: widget.textStyle?.color ?? theme.colorScheme.onSurface,
      ),
      onErrorFallback: (errmsg) {
        return FlowyText(
          errmsg.message,
          fontSize: widget.textStyle?.fontSize ?? 14.0,
          color: widget.textStyle?.color ?? theme.colorScheme.onSurface,
        );
      },
    );
    return longEq;
  }
}

class MathInputTextField extends StatefulWidget {
  const MathInputTextField({
    super.key,
    required this.initialText,
    required this.onSubmit,
    this.editorState,
  });

  final String initialText;
  final void Function(String value) onSubmit;
  final EditorState? editorState;

  @override
  State<MathInputTextField> createState() => _MathInputTextFieldState();
}

class _MathInputTextFieldState extends State<MathInputTextField> {
  late String _latex = widget.initialText;

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The rendered equation leads: the source is what produced it, not
          // what is being looked at.
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _latex.trim().isEmpty
                  ? Text(
                      LocaleKeys.diagrams_math_placeholderTitle.tr(),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textMuted,
                      ),
                    )
                  : Math.tex(
                      _latex,
                      mathStyle: MathStyle.text,
                      textStyle: TextStyle(fontSize: 20, color: palette.text),
                      onErrorFallback: (error) => Text(
                        error.messageWithType,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: MathSourceEditor(
              latex: widget.initialText,
              editorState: widget.editorState,
              hint: r'\pi r^2',
              showLabel: false,
              onChanged: (value) => setState(() => _latex = value),
              onSubmit: widget.onSubmit,
              onClose: () => widget.onSubmit(_latex),
            ),
          ),
        ],
      ),
    );
  }
}

class _IgnoreParentPointer extends StatelessWidget {
  const _IgnoreParentPointer({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      onTapDown: (_) {},
      onDoubleTap: () {},
      onLongPress: () {},
      child: child,
    );
  }
}
