// Asking for a PDF's password.
//
// An encrypted document is not a broken one. pdfrx asks for a password through
// a callback and gives up when it is handed null, so a person must be able to
// type one, be told when it was wrong, and be able to walk away.

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Asks for the password of [name]. Null means the person declined.
Future<String?> showPdfPasswordDialog(
  BuildContext context, {
  required String name,
  bool retry = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => _PdfPasswordDialog(name: name, retry: retry),
    );

class _PdfPasswordDialog extends StatefulWidget {
  const _PdfPasswordDialog({required this.name, required this.retry});

  final String name;
  final bool retry;

  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _submit() {
    final entered = controller.text;
    if (entered.isEmpty) {
      return;
    }
    Navigator.of(context).pop(entered);
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: ViewerCard(
          color: palette.floatingSurface,
          reactsToPointer: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: palette.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        LocaleKeys.document_plugins_pdf_locked.tr(),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontVariations: const [FontVariation.weight(620)],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.retry
                      ? LocaleKeys.document_plugins_pdf_wrongPassword.tr()
                      : LocaleKeys.document_plugins_pdf_askPassword
                          .tr(args: [widget.name]),
                  style: TextStyle(
                    color: widget.retry ? palette.danger : palette.textMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                ProviderTextField(
                  label: LocaleKeys.document_plugins_pdf_password.tr(),
                  controller: controller,
                  palette: palette,
                  obscure: true,
                  autofocus: true,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(LocaleKeys.button_cancel.tr()),
                    ),
                    const SizedBox(width: 6),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, _) => FilledButton(
                        onPressed: value.text.isEmpty ? null : _submit,
                        child: Text(
                          LocaleKeys.document_plugins_pdf_unlock.tr(),
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
    );
  }
}
