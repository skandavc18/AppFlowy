import 'dart:async';

import 'package:appflowy/ai/skills/ai_skill.dart';
import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/ai/tools/mcp_server_config.dart';
import 'package:appflowy/ai/tools/tool_permissions.dart';
import 'package:appflowy/ai/tools/tool_registry.dart';
import 'package:appflowy/ai/tools/workspace_tools.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/toggle/toggle.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The tools an agent may use and the skills it is taught, shown as part of
/// Settings ▸ AI so everything the assistant can do is described in one place.
class AIToolsAndSkillsSetting extends StatefulWidget {
  const AIToolsAndSkillsSetting({super.key});

  @override
  State<AIToolsAndSkillsSetting> createState() =>
      _AIToolsAndSkillsSettingState();
}

class _AIToolsAndSkillsSettingState extends State<AIToolsAndSkillsSetting> {
  final McpServerStore _servers = McpServerStore.instance;
  final AISkillStore _skills = AISkillStore.instance;
  final AIToolPermissionStore _permissions = AIToolPermissionStore.instance;
  final AIToolRegistry _registry = AIToolRegistry.instance;

  @override
  void initState() {
    super.initState();
    for (final listenable in [_servers, _skills, _permissions, _registry]) {
      listenable.addListener(_onChanged);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final listenable in [_servers, _skills, _permissions, _registry]) {
      listenable.removeListener(_onChanged);
    }
    super.dispose();
  }

  Future<void> _load() async {
    await _servers.ensureLoaded();
    await _skills.ensureLoaded();
    await _permissions.ensureLoaded();
    await _registry.refresh();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BuiltInSection(palette: palette, registry: _registry),
        const SizedBox(height: 22),
        _ServersSection(palette: palette, registry: _registry),
        const SizedBox(height: 22),
        _SkillsSection(palette: palette),
        const SizedBox(height: 22),
        _PermissionsSection(palette: palette, registry: _registry),
      ],
    );
  }
}

// ------------------------------------------------------------------ built in

class _BuiltInSection extends StatelessWidget {
  const _BuiltInSection({required this.palette, required this.registry});

  final FolderExplorerPalette palette;
  final AIToolRegistry registry;

  @override
  Widget build(BuildContext context) {
    final own = registry.tools
        .where((tool) => tool.serverId == WorkspaceToolServer.serverId)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: LocaleKeys.aiTools_builtInTitle.tr(),
          description: LocaleKeys.aiTools_builtInDescription.tr(),
          palette: palette,
          action: _PillButton(
            label: LocaleKeys.aiTools_reloadTools.tr(),
            icon: Icons.refresh_rounded,
            palette: palette,
            busy: registry.isLoading,
            onTap: () => unawaited(registry.reload()),
          ),
        ),
        const SizedBox(height: 10),
        _Card(
          palette: palette,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tool in own)
                _ToolChip(tool: tool, palette: palette),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.tool, required this.palette});

  final AITool tool;
  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) {
    final colour = switch (tool.risk) {
      AIToolRisk.read => palette.textMuted,
      AIToolRisk.write => palette.accent,
      AIToolRisk.destructive => palette.danger,
    };
    return Tooltip(
      message: tool.description,
      child: Container(
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(7),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          tool.name,
          style: TextStyle(
            color: colour,
            fontSize: 11.5,
            fontVariations: const [FontVariation.weight(560)],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- servers

class _ServersSection extends StatelessWidget {
  const _ServersSection({required this.palette, required this.registry});

  final FolderExplorerPalette palette;
  final AIToolRegistry registry;

  @override
  Widget build(BuildContext context) {
    final servers = McpServerStore.instance.servers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: LocaleKeys.aiTools_serversTitle.tr(),
          description: LocaleKeys.aiTools_serversDescription.tr(),
          palette: palette,
          action: _PillButton(
            label: LocaleKeys.aiTools_addServer.tr(),
            icon: Icons.add_rounded,
            palette: palette,
            primary: true,
            onTap: () => unawaited(showMcpServerDialog(context)),
          ),
        ),
        const SizedBox(height: 10),
        if (servers.isEmpty)
          _Card(
            palette: palette,
            child: Text(
              LocaleKeys.aiTools_noServers.tr(),
              style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
            ),
          )
        else
          ...servers.map(
            (server) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ServerRow(
                server: server,
                palette: palette,
                registry: registry,
              ),
            ),
          ),
      ],
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.palette,
    required this.registry,
  });

  final McpServerConfig server;
  final FolderExplorerPalette palette;
  final AIToolRegistry registry;

  @override
  Widget build(BuildContext context) {
    final failure = registry.failures[server.id];
    final count =
        registry.tools.where((tool) => tool.serverId == server.id).length;

    return _Card(
      palette: palette,
      child: Row(
        children: [
          Icon(
            server.transport == McpTransport.stdio
                ? Icons.terminal_rounded
                : Icons.cloud_outlined,
            size: 17,
            color: palette.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontVariations: const [FontVariation.weight(580)],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  failure != null
                      ? LocaleKeys.aiTools_serverUnreachable.tr(args: [failure])
                      : '${server.summary} · '
                          '${LocaleKeys.aiTools_toolsFound.tr(args: ['$count'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: failure != null ? palette.danger : palette.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Toggle(
            value: server.enabled,
            onChanged: (value) async {
              await McpServerStore.instance
                  .upsert(server.copyWith(enabled: !value));
              await registry.reload();
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            iconSize: 16,
            splashRadius: 16,
            tooltip: LocaleKeys.aiProviders_edit.tr(),
            onPressed: () =>
                unawaited(showMcpServerDialog(context, server: server)),
            icon: Icon(Icons.edit_outlined, color: palette.textMuted),
          ),
          IconButton(
            iconSize: 16,
            splashRadius: 16,
            tooltip: LocaleKeys.button_delete.tr(),
            onPressed: () => unawaited(_confirmRemove(context)),
            icon: Icon(Icons.delete_outline_rounded, color: palette.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final removed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(LocaleKeys.aiTools_removeServerTitle.tr()),
        content: Text(
          LocaleKeys.aiTools_removeServerBody.tr(args: [server.name]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(LocaleKeys.button_delete.tr()),
          ),
        ],
      ),
    );
    if (removed == true) {
      await McpServerStore.instance.remove(server.id);
      await registry.reload();
    }
  }
}

// -------------------------------------------------------------------- skills

class _SkillsSection extends StatelessWidget {
  const _SkillsSection({required this.palette});

  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) {
    final skills = AISkillStore.instance.skills;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: LocaleKeys.aiTools_skillsTitle.tr(),
          description: LocaleKeys.aiTools_skillsDescription.tr(),
          palette: palette,
          action: _PillButton(
            label: LocaleKeys.aiTools_addSkill.tr(),
            icon: Icons.add_rounded,
            palette: palette,
            primary: true,
            onTap: () => unawaited(showAISkillDialog(context)),
          ),
        ),
        const SizedBox(height: 10),
        ...skills.map(
          (skill) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SkillRow(skill: skill, palette: palette),
          ),
        ),
      ],
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill, required this.palette});

  final AISkill skill;
  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) {
    return _Card(
      palette: palette,
      child: Row(
        children: [
          Icon(Icons.school_rounded, size: 17, color: palette.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        skill.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontVariations: const [FontVariation.weight(580)],
                        ),
                      ),
                    ),
                    if (skill.isBuiltIn) ...[
                      const SizedBox(width: 6),
                      Text(
                        LocaleKeys.aiTools_builtInSkill.tr(),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  skill.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Toggle(
            value: skill.enabled,
            onChanged: (value) => unawaited(
              AISkillStore.instance.setEnabled(skill, !value),
            ),
          ),
          if (!skill.isBuiltIn) ...[
            const SizedBox(width: 4),
            IconButton(
              iconSize: 16,
              splashRadius: 16,
              tooltip: LocaleKeys.aiProviders_edit.tr(),
              onPressed: () => unawaited(showAISkillDialog(context, skill: skill)),
              icon: Icon(Icons.edit_outlined, color: palette.textMuted),
            ),
            IconButton(
              iconSize: 16,
              splashRadius: 16,
              tooltip: LocaleKeys.button_delete.tr(),
              onPressed: () => unawaited(AISkillStore.instance.remove(skill.id)),
              icon: Icon(
                Icons.delete_outline_rounded,
                color: palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- permissions

class _PermissionsSection extends StatelessWidget {
  const _PermissionsSection({required this.palette, required this.registry});

  final FolderExplorerPalette palette;
  final AIToolRegistry registry;

  @override
  Widget build(BuildContext context) {
    final decisions = AIToolPermissionStore.instance.decisions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          title: LocaleKeys.aiTools_permissionsTitle.tr(),
          description: LocaleKeys.aiTools_permissionsDescription.tr(),
          palette: palette,
          action: decisions.isEmpty
              ? null
              : _PillButton(
                  label: LocaleKeys.aiTools_forgetDecisions.tr(),
                  palette: palette,
                  onTap: () =>
                      unawaited(AIToolPermissionStore.instance.forgetAll()),
                ),
        ),
        const SizedBox(height: 10),
        _Card(
          palette: palette,
          child: decisions.isEmpty
              ? Text(
                  LocaleKeys.aiTools_noDecisions.tr(),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in decisions.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                registry.toolFor(entry.key)?.name ?? entry.key,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            Text(
                              entry.value == AIToolPermission.allow
                                  ? LocaleKeys.aiTools_permissionAllow.tr()
                                  : LocaleKeys.aiTools_permissionDeny.tr(),
                              style: TextStyle(
                                color: entry.value == AIToolPermission.allow
                                    ? palette.accent
                                    : palette.danger,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- chrome

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.description,
    required this.palette,
    this.action,
  });

  final String title;
  final String description;
  final FolderExplorerPalette palette;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  fontVariations: const [FontVariation.weight(600)],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12,
                  height: 16 / 12,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.palette, required this.child});

  final FolderExplorerPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
        child: child,
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.palette,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.busy = false,
  });

  final String label;
  final FolderExplorerPalette palette;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final foreground = primary ? palette.accent : palette.textSecondary;
    return Material(
      color: primary
          ? palette.accent.withValues(alpha: enabled ? 0.12 : 0.06)
          : palette.hover,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: foreground,
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 14, color: foreground),
              if (busy || icon != null) const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? foreground : palette.textMuted,
                  fontSize: 12.5,
                  fontVariations: const [FontVariation.weight(560)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- dialogs

/// Adds or edits one MCP server.
Future<void> showMcpServerDialog(
  BuildContext context, {
  McpServerConfig? server,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _McpServerDialog(server: server),
    );

class _McpServerDialog extends StatefulWidget {
  const _McpServerDialog({this.server});

  final McpServerConfig? server;

  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  late McpTransport _transport =
      widget.server?.transport ?? McpTransport.stdio;
  late final TextEditingController _name =
      TextEditingController(text: widget.server?.name ?? '');
  late final TextEditingController _command = TextEditingController(
    text: [
      if (widget.server != null) widget.server!.command,
      if (widget.server != null) ...widget.server!.args,
    ].where((part) => part.isNotEmpty).join(' '),
  );
  late final TextEditingController _workingDirectory =
      TextEditingController(text: widget.server?.workingDirectory ?? '');
  late final TextEditingController _env = TextEditingController(
    text: _pairsToText(widget.server?.env ?? const {}, '='),
  );
  late final TextEditingController _url =
      TextEditingController(text: widget.server?.url ?? '');
  late final TextEditingController _headers = TextEditingController(
    text: _pairsToText(widget.server?.headers ?? const {}, ': '),
  );
  late final TextEditingController _destructive = TextEditingController(
    text: (widget.server?.destructiveTools ?? const []).join(', '),
  );
  late final TextEditingController _readOnly = TextEditingController(
    text: (widget.server?.readOnlyTools ?? const []).join(', '),
  );

  @override
  void dispose() {
    for (final controller in [
      _name,
      _command,
      _workingDirectory,
      _env,
      _url,
      _headers,
      _destructive,
      _readOnly,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _pairsToText(Map<String, String> pairs, String separator) =>
      pairs.entries.map((e) => '${e.key}$separator${e.value}').join('\n');

  static Map<String, String> _textToPairs(String text, String separator) {
    final pairs = <String, String>{};
    for (final line in text.split('\n')) {
      final at = line.indexOf(separator.trim());
      if (at <= 0) {
        continue;
      }
      final key = line.substring(0, at).trim();
      final value = line.substring(at + separator.trim().length).trim();
      if (key.isNotEmpty) {
        pairs[key] = value;
      }
    }
    return pairs;
  }

  static List<String> _names(String text) => text
      .split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final (command, args) =
        McpServerConfig.parseCommandLine(_command.text);
    final saved = await McpServerStore.instance.upsert(
      McpServerConfig(
        id: widget.server?.id ?? '',
        name: _name.text.trim().isEmpty ? 'MCP server' : _name.text.trim(),
        transport: _transport,
        command: command,
        args: args,
        env: _textToPairs(_env.text, '='),
        workingDirectory: _workingDirectory.text.trim(),
        url: _url.text.trim(),
        headers: _textToPairs(_headers.text, ': '),
        readOnlyTools: _names(_readOnly.text),
        destructiveTools: _names(_destructive.text),
        enabled: widget.server?.enabled ?? true,
      ),
    );
    if (saved.id.isNotEmpty) {
      await AIToolRegistry.instance.reload();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final isStdio = _transport == McpTransport.stdio;

    return Dialog(
      backgroundColor: palette.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 620),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.server == null
                      ? LocaleKeys.aiTools_addServerTitle.tr()
                      : LocaleKeys.aiTools_editServerTitle.tr(),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontVariations: const [FontVariation.weight(640)],
                  ),
                ),
                const SizedBox(height: 14),
                ProviderTextField(
                  label: LocaleKeys.aiTools_serverNameLabel.tr(),
                  controller: _name,
                  palette: palette,
                ),
                const SizedBox(height: 12),
                Text(
                  LocaleKeys.aiTools_transportLabel.tr(),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 11.5,
                    fontVariations: const [FontVariation.weight(580)],
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _Segment(
                      label: LocaleKeys.aiTools_transportStdio.tr(),
                      selected: isStdio,
                      palette: palette,
                      onTap: () =>
                          setState(() => _transport = McpTransport.stdio),
                    ),
                    const SizedBox(width: 6),
                    _Segment(
                      label: LocaleKeys.aiTools_transportHttp.tr(),
                      selected: !isStdio,
                      palette: palette,
                      onTap: () =>
                          setState(() => _transport = McpTransport.http),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isStdio) ...[
                  ProviderTextField(
                    label: LocaleKeys.aiTools_commandLabel.tr(),
                    controller: _command,
                    palette: palette,
                    hint: LocaleKeys.aiTools_commandHint.tr(),
                  ),
                  const SizedBox(height: 10),
                  ProviderTextField(
                    label: LocaleKeys.aiTools_workingDirectoryLabel.tr(),
                    controller: _workingDirectory,
                    palette: palette,
                  ),
                  const SizedBox(height: 10),
                  ProviderTextField(
                    label: LocaleKeys.aiTools_envLabel.tr(),
                    controller: _env,
                    palette: palette,
                  ),
                ] else ...[
                  ProviderTextField(
                    label: LocaleKeys.aiTools_urlLabel.tr(),
                    controller: _url,
                    palette: palette,
                    hint: 'https://example.com/mcp',
                  ),
                  const SizedBox(height: 10),
                  ProviderTextField(
                    label: LocaleKeys.aiTools_headersLabel.tr(),
                    controller: _headers,
                    palette: palette,
                    showPasteButton: true,
                  ),
                ],
                const SizedBox(height: 12),
                ProviderTextField(
                  label: LocaleKeys.aiTools_destructiveToolsLabel.tr(),
                  controller: _destructive,
                  palette: palette,
                ),
                const SizedBox(height: 10),
                ProviderTextField(
                  label: LocaleKeys.aiTools_readOnlyToolsLabel.tr(),
                  controller: _readOnly,
                  palette: palette,
                ),
                const SizedBox(height: 5),
                Text(
                  LocaleKeys.aiTools_toolRiskHelp.tr(),
                  style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _PillButton(
                      label: LocaleKeys.button_cancel.tr(),
                      palette: palette,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    _PillButton(
                      label: LocaleKeys.button_save.tr(),
                      palette: palette,
                      primary: true,
                      onTap: () => unawaited(_save()),
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

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final FolderExplorerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? palette.accent.withValues(alpha: 0.14)
          : palette.background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? palette.accent : palette.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Adds or edits one skill.
Future<void> showAISkillDialog(BuildContext context, {AISkill? skill}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _SkillDialog(skill: skill),
    );

class _SkillDialog extends StatefulWidget {
  const _SkillDialog({this.skill});

  final AISkill? skill;

  @override
  State<_SkillDialog> createState() => _SkillDialogState();
}

class _SkillDialogState extends State<_SkillDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.skill?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.skill?.description ?? '');
  late final TextEditingController _keywords = TextEditingController(
    text: (widget.skill?.keywords ?? const []).join(', '),
  );
  late final TextEditingController _instructions =
      TextEditingController(text: widget.skill?.instructions ?? '');

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _keywords,
      _instructions,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await AISkillStore.instance.upsert(
      AISkill(
        id: widget.skill?.id ?? '',
        name: _name.text.trim().isEmpty ? 'Skill' : _name.text.trim(),
        description: _description.text.trim(),
        instructions: _instructions.text.trim(),
        keywords: _keywords.text
            .split(',')
            .map((word) => word.trim())
            .where((word) => word.isNotEmpty)
            .toList(),
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);

    return Dialog(
      backgroundColor: palette.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.skill == null
                      ? LocaleKeys.aiTools_addSkillTitle.tr()
                      : LocaleKeys.aiTools_editSkillTitle.tr(),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontVariations: const [FontVariation.weight(640)],
                  ),
                ),
                const SizedBox(height: 14),
                ProviderTextField(
                  label: LocaleKeys.aiTools_skillNameLabel.tr(),
                  controller: _name,
                  palette: palette,
                ),
                const SizedBox(height: 10),
                ProviderTextField(
                  label: LocaleKeys.aiTools_skillDescriptionLabel.tr(),
                  controller: _description,
                  palette: palette,
                ),
                const SizedBox(height: 10),
                ProviderTextField(
                  label: LocaleKeys.aiTools_skillKeywordsLabel.tr(),
                  controller: _keywords,
                  palette: palette,
                ),
                const SizedBox(height: 10),
                ProviderTextField(
                  label: LocaleKeys.aiTools_skillInstructionsLabel.tr(),
                  controller: _instructions,
                  palette: palette,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _PillButton(
                      label: LocaleKeys.button_cancel.tr(),
                      palette: palette,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    _PillButton(
                      label: LocaleKeys.button_save.tr(),
                      palette: palette,
                      primary: true,
                      onTap: () => unawaited(_save()),
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
