import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/palette_scope.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The name a scope goes by on its tab and in the search box.
String paletteScopeLabel(PaletteScope scope) => switch (scope) {
      PaletteScope.all => LocaleKeys.commandPalette_scope_all.tr(),
      PaletteScope.pages => LocaleKeys.commandPalette_scope_pages.tr(),
      PaletteScope.commands => LocaleKeys.commandPalette_scope_commands.tr(),
      PaletteScope.settings => LocaleKeys.commandPalette_scope_settings.tr(),
      PaletteScope.extensions =>
        LocaleKeys.commandPalette_scope_extensions.tr(),
      PaletteScope.ai => LocaleKeys.commandPalette_scope_ai.tr(),
    };

IconData paletteScopeIcon(PaletteScope scope) => switch (scope) {
      PaletteScope.all => Icons.manage_search_rounded,
      PaletteScope.pages => Icons.description_outlined,
      PaletteScope.commands => Icons.bolt_rounded,
      PaletteScope.settings => Icons.tune_rounded,
      PaletteScope.extensions => Icons.extension_outlined,
      PaletteScope.ai => Icons.auto_awesome_rounded,
    };

/// What the search box invites in each scope.
String paletteScopeHint(PaletteScope scope, {String workspaceName = ''}) =>
    switch (scope) {
      PaletteScope.all =>
        LocaleKeys.search_searchFieldHint.tr(args: [workspaceName]),
      PaletteScope.pages => LocaleKeys.commandPalette_scopeHint_pages.tr(),
      PaletteScope.commands =>
        LocaleKeys.commandPalette_scopeHint_commands.tr(),
      PaletteScope.settings =>
        LocaleKeys.commandPalette_scopeHint_settings.tr(),
      PaletteScope.extensions =>
        LocaleKeys.commandPalette_scopeHint_extensions.tr(),
      PaletteScope.ai => LocaleKeys.commandPalette_scopeHint_ai.tr(),
    };

/// The pill inside the search box that names what the palette is narrowed
/// to, and steps back out of it.
class PaletteScopeBadge extends StatelessWidget {
  const PaletteScopeBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.onClear,
  });

  final String label;
  final IconData icon;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    return Container(
      key: const ValueKey('command-palette-scope-badge'),
      height: 26,
      padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
      decoration: BoxDecoration(
        color: WorkspaceChrome.selectedColor(context),
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceGlyph(icon, size: 14, color: palette.accent),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textStyle.caption.enhanced(color: palette.accent),
            ),
          ),
          ExcludeFocus(
            child: InkWell(
              onTap: onClear,
              borderRadius:
                  BorderRadius.circular(WorkspaceTokens.controlRadius),
              hoverColor: WorkspaceChrome.hoverColor(context),
              child: Tooltip(
                message: LocaleKeys.commandPalette_scope_clear.tr(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: WorkspaceGlyph(
                    Icons.close_rounded,
                    size: 12,
                    color: palette.accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The row of tabs under the search box that narrows what the palette looks
/// through, the way Spotlight's categories do.
class PaletteScopeBar extends StatelessWidget {
  const PaletteScopeBar({
    super.key,
    required this.scope,
    required this.onChanged,
  });

  final PaletteScope scope;
  final ValueChanged<PaletteScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: LocaleKeys.commandPalette_scope_label.tr(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        primary: false,
        child: Row(
          children: [
            for (final value in PaletteScope.values) ...[
              if (value == PaletteScope.ai)
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(
                    horizontal: WorkspaceTokens.space2,
                  ),
                  color: WorkspacePalette.of(context).border,
                ),
              _ScopeTab(
                key: ValueKey('command-palette-scope-${value.name}'),
                scope: value,
                selected: value == scope,
                onTap: () => onChanged(value),
              ),
              if (value != PaletteScope.values.last) const SizedBox(width: 2),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScopeTab extends StatelessWidget {
  const _ScopeTab({
    super.key,
    required this.scope,
    required this.selected,
    required this.onTap,
  });

  final PaletteScope scope;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    final hover = WorkspaceChrome.hoverColor(context);
    final selectedFill = WorkspaceChrome.selectedColor(context);
    final isAI = scope == PaletteScope.ai;
    final ink = selected
        ? palette.accent
        : isAI
            ? palette.accent.withValues(alpha: 0.85)
            : theme.textColorScheme.secondary;

    return Semantics(
      selected: selected,
      button: true,
      child: AFBaseButton(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        borderRadius: theme.borderRadius.m,
        borderColor: (_, __, ___, ____) => selected
            ? palette.accent.withValues(alpha: 0.28)
            : palette.accent.withValues(alpha: 0),
        backgroundColor: (_, isHovering, __) => selected
            ? (isHovering
                ? Color.alphaBlend(hover, selectedFill)
                : selectedFill)
            : (isHovering ? hover : hover.withValues(alpha: 0)),
        builder: (_, __, ___) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceGlyph(paletteScopeIcon(scope), size: 15, color: ink),
            const SizedBox(width: 5),
            Text(
              paletteScopeLabel(scope),
              maxLines: 1,
              style: (selected
                      ? theme.textStyle.caption.enhanced(color: ink)
                      : theme.textStyle.caption.standard(color: ink))
                  .copyWith(height: 18 / 12),
            ),
          ],
        ),
      ),
    );
  }
}
