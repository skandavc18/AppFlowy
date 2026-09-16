import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The same width shortcuts in the page menu and workspace settings. A custom
/// saved width is never rounded to a preset simply by opening this control.
class DocumentWidthAction extends StatelessWidget {
  const DocumentWidthAction({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<DocumentAppearanceCubit, DocumentAppearance>(
        buildWhen: (previous, current) => previous.width != current.width,
        builder: (context, appearance) => DocumentWidthPicker(
          width: appearance.width,
          onChanged: (width) => unawaited(
            context.read<DocumentAppearanceCubit>().syncWidth(width),
          ),
        ),
      );
}

class DocumentWidthPicker extends StatelessWidget {
  const DocumentWidthPicker({
    super.key,
    required this.width,
    required this.onChanged,
    this.showHeading = true,
  });

  final double width;
  final ValueChanged<double> onChanged;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final style = AppMenuStyle.of(context);
    final selected = DocumentWidthPreset.forWidth(width);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeading) ...[
            Text(
              LocaleKeys.settings_appearance_documentSettings_width.tr(),
              style: style.labelStyle,
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final preset in DocumentWidthPreset.values)
                Semantics(
                  selected: selected == preset,
                  child: Tooltip(
                    message: _hint(preset),
                    child: TextButton(
                      key: ValueKey('document-width-${preset.name}'),
                      onPressed: () => onChanged(preset.width),
                      style: ButtonStyle(
                        animationDuration:
                            MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 140),
                        minimumSize: const WidgetStatePropertyAll(
                          Size(0, WorkspaceChrome.controlHeight),
                        ),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10),
                        ),
                        foregroundColor: WidgetStatePropertyAll(
                          selected == preset
                              ? style.accent
                              : style.textSecondary,
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.hovered) ||
                                  states.contains(WidgetState.focused)
                              ? style.hover
                              : selected == preset
                                  ? style.selected
                                  : style.hoverBase,
                        ),
                        side: WidgetStateProperty.resolveWith(
                          (states) => BorderSide(
                            color: states.contains(WidgetState.focused)
                                ? style.accent
                                : style.accent.withValues(alpha: 0),
                          ),
                        ),
                        textStyle: WidgetStatePropertyAll(
                          style.labelStyle.copyWith(fontSize: 12),
                        ),
                      ),
                      child: Text(_label(preset)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (selected == null && width.isFinite) ...[
            Text(
              LocaleKeys.workspaceChrome_customWidth
                  .tr(args: [width.round().toString()]),
              style: style.subtitleStyle.copyWith(color: style.textSecondary),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            LocaleKeys.workspaceChrome_widthScope.tr(),
            style: style.subtitleStyle
                .copyWith(color: style.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _label(DocumentWidthPreset preset) => switch (preset) {
        DocumentWidthPreset.reading => LocaleKeys.workspaceChrome_reading.tr(),
        DocumentWidthPreset.wide => LocaleKeys.workspaceChrome_wide.tr(),
        DocumentWidthPreset.full => LocaleKeys.workspaceChrome_full.tr(),
      };

  String _hint(DocumentWidthPreset preset) => switch (preset) {
        DocumentWidthPreset.reading =>
          LocaleKeys.workspaceChrome_readingHint.tr(),
        DocumentWidthPreset.wide => LocaleKeys.workspaceChrome_wideHint.tr(),
        DocumentWidthPreset.full => LocaleKeys.workspaceChrome_fullHint.tr(),
      };
}
