import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart' show showFlowyDialog;
import 'package:flutter/material.dart';

typedef SimpleAFDialogAction = (String, void Function(BuildContext)?);

/// A simple dialog with a title, content, and actions.
///
/// The primary button is a filled button and colored using theme or destructive
/// color depending on the [isDestructive] parameter. The secondary button is an
/// outlined button.
///
Future<void> showSimpleAFDialog({
  required BuildContext context,
  required String title,
  required String content,
  bool isDestructive = false,
  required SimpleAFDialogAction primaryAction,
  SimpleAFDialogAction? secondaryAction,
  bool barrierDismissible = true,
}) {
  return showFlowyDialog(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      return AFModal(
        constraints: BoxConstraints(
          maxWidth: AFModalDimension.S,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AFModalHeader(
              leading: Text(
                title,
                style: WorkspaceTypography.style(
                  dialogContext,
                  WorkspaceTextRole.section,
                ),
              ),
              trailing: [
                _DialogCloseButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: AFModalBody(
                  child: Text(
                    content,
                    style: WorkspaceTypography.style(
                      dialogContext,
                      WorkspaceTextRole.body,
                    ),
                  ),
                ),
              ),
            ),
            AFModalFooter(
              trailing: [
                if (secondaryAction != null)
                  AFOutlinedTextButton.normal(
                    text: secondaryAction.$1,
                    onTap: () {
                      secondaryAction.$2?.call(context);
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                isDestructive
                    ? AFFilledTextButton.destructive(
                        text: primaryAction.$1,
                        onTap: () {
                          primaryAction.$2?.call(context);
                          Navigator.of(dialogContext).pop();
                        },
                      )
                    : AFFilledTextButton.primary(
                        text: primaryAction.$1,
                        onTap: () {
                          primaryAction.$2?.call(context);
                          Navigator.of(dialogContext).pop();
                        },
                      ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// Shows a dialog for renaming an item with a text field.
/// The API is flexible: either provide a callback for confirmation or use the
/// returned Future to get the new value.
///
Future<String?> showAFTextFieldDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  void Function(String)? onConfirm,
  bool barrierDismissible = true,
  bool selectAll = true,
  int? maxLength,
  String? hintText,
}) {
  return showFlowyDialog<String>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) {
      return AFTextFieldDialog(
        title: title,
        initialValue: initialValue,
        onConfirm: onConfirm,
        selectAll: selectAll,
        maxLength: maxLength,
        hintText: hintText,
      );
    },
  );
}

class AFTextFieldDialog extends StatefulWidget {
  const AFTextFieldDialog({
    super.key,
    required this.title,
    required this.initialValue,
    this.onConfirm,
    this.selectAll = true,
    this.maxLength,
    this.hintText,
  });

  final String title;
  final String initialValue;
  final void Function(String)? onConfirm;
  final bool selectAll;
  final int? maxLength;
  final String? hintText;

  @override
  State<AFTextFieldDialog> createState() => _AFTextFieldDialogState();
}

class _AFTextFieldDialogState extends State<AFTextFieldDialog> {
  final textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    textController.value = TextEditingValue(
      text: widget.initialValue,
      selection: widget.selectAll
          ? TextSelection(
              baseOffset: 0,
              extentOffset: widget.initialValue.length,
            )
          : TextSelection.collapsed(
              offset: widget.initialValue.length,
            ),
    );
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AFModal(
      constraints: BoxConstraints(
        maxWidth: AFModalDimension.S,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AFModalHeader(
            leading: Text(
              widget.title,
              style:
                  WorkspaceTypography.style(context, WorkspaceTextRole.section),
            ),
            trailing: [
              _DialogCloseButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          Flexible(
            child: AFModalBody(
              child: AFTextField(
                autoFocus: true,
                size: AFTextFieldSize.m,
                hintText: widget.hintText,
                maxLength: widget.maxLength,
                controller: textController,
                onSubmitted: (_) {
                  handleConfirm();
                },
              ),
            ),
          ),
          AFModalFooter(
            trailing: [
              AFOutlinedTextButton.normal(
                text: LocaleKeys.button_cancel.tr(),
                onTap: () => Navigator.of(context).pop(),
              ),
              ValueListenableBuilder(
                valueListenable: textController,
                builder: (contex, value, child) {
                  return AFFilledTextButton.primary(
                    text: LocaleKeys.button_confirm.tr(),
                    disabled: value.text.trim().isEmpty,
                    onTap: handleConfirm,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void handleConfirm() {
    final text = textController.text.trim();

    if (text.isEmpty) {
      return;
    }

    widget.onConfirm?.call(text);
    Navigator.of(context).pop(text);
  }
}

class _DialogCloseButton extends StatelessWidget {
  const _DialogCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
          ),
        ).copyWith(
          animationDuration:
              WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
        ),
        icon: const Icon(Icons.close_rounded, size: WorkspaceTokens.iconSize),
      );
}
