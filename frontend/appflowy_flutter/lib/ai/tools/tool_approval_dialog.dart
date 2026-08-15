import 'dart:convert';

import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/ai/tools/tool_permissions.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Asks whether a tool may run.
///
/// Reading is never asked about; anything that changes or removes something is,
/// once, and the answer can be remembered. The arguments are shown in full,
/// because "may I write to your workspace" is not a question anybody can answer
/// without seeing what would be written.
Future<AIToolDecision> askToRunTool(
  AITool tool,
  Map<String, dynamic> arguments,
) async {
  final context = AppGlobals.rootNavKey.currentContext;
  if (context == null) {
    return AIToolDecision.denyOnce;
  }

  final decision = await showDialog<AIToolDecision>(
    context: context,
    // Dismissing is refusing. A question nobody can get rid of would hold the
    // keyboard for the whole app, and the safe answer is no.
    builder: (_) => _ToolApprovalDialog(tool: tool, arguments: arguments),
  );
  return decision ?? AIToolDecision.denyOnce;
}

class _ToolApprovalDialog extends StatelessWidget {
  const _ToolApprovalDialog({required this.tool, required this.arguments});

  final AITool tool;
  final Map<String, dynamic> arguments;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final destructive = tool.risk == AIToolRisk.destructive;
    final accent = destructive ? palette.danger : palette.accent;

    return Dialog(
      backgroundColor: palette.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      destructive
                          ? Icons.delete_outline_rounded
                          : Icons.bolt_rounded,
                      size: 16,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      destructive
                          ? LocaleKeys.aiTools_approveDestructiveTitle
                              .tr(args: [tool.name])
                          : LocaleKeys.aiTools_approveTitle
                              .tr(args: [tool.name]),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 15,
                        fontVariations: const [FontVariation.weight(620)],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${tool.serverLabel} · ${tool.description}',
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
              if (arguments.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(11),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(arguments),
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11.5,
                          height: 1.45,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Choice(
                    label: LocaleKeys.aiTools_denyAlways.tr(),
                    palette: palette,
                    onTap: () => Navigator.of(context)
                        .pop(AIToolDecision.denyAlways),
                  ),
                  _Choice(
                    label: LocaleKeys.aiTools_deny.tr(),
                    palette: palette,
                    onTap: () =>
                        Navigator.of(context).pop(AIToolDecision.denyOnce),
                  ),
                  _Choice(
                    label: LocaleKeys.aiTools_allowAll.tr(),
                    palette: palette,
                    onTap: () => Navigator.of(context)
                        .pop(AIToolDecision.allowAllThisChat),
                  ),
                  _Choice(
                    label: LocaleKeys.aiTools_allowAlways.tr(),
                    palette: palette,
                    onTap: () => Navigator.of(context)
                        .pop(AIToolDecision.allowAlways),
                  ),
                  _Choice(
                    label: LocaleKeys.aiTools_allowOnce.tr(),
                    palette: palette,
                    primary: true,
                    onTap: () =>
                        Navigator.of(context).pop(AIToolDecision.allowOnce),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.palette,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final FolderExplorerPalette palette;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? palette.accent.withValues(alpha: 0.14) : palette.hover,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: primary ? palette.accent : palette.textSecondary,
              fontSize: 12.5,
              fontVariations: const [FontVariation.weight(570)],
            ),
          ),
        ),
      ),
    );
  }
}
