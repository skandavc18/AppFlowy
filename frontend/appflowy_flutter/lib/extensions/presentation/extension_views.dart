import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_manifest.dart';
import 'package:appflowy/extensions/application/extension_run_log.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The pieces Settings ▸ Extensions and the Extensions page both draw.
///
/// One implementation, because the two surfaces answer the same questions —
/// what is installed, is it turned on, what did it do last, and when will it
/// do it again.

/// Name, version, enable switch, declared hosts and anything unreadable.
class ExtensionHeaderRow extends StatelessWidget {
  const ExtensionHeaderRow({
    super.key,
    required this.extension,
    required this.store,
  });

  final LoadedExtension extension;
  final ExtensionStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = extension.manifest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${manifest.id} · ${manifest.version}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (manifest.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      manifest.description,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: store.isEnabled(extension.id),
              onChanged: (value) => store.setEnabled(extension.id, value),
            ),
          ],
        ),
        if (manifest.hosts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            LocaleKeys.extensions_reaches.tr(args: [manifest.hosts.join(', ')]),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (!manifest.isSupported) ...[
          const SizedBox(height: 8),
          ExtensionProblemRow(
            text: LocaleKeys.extensions_unsupportedApi.tr(
              args: [
                '${manifest.apiVersion}',
                '${ExtensionManifest.currentApiVersion}',
              ],
            ),
          ),
        ],
        for (final problem in extension.problems) ...[
          const SizedBox(height: 6),
          ExtensionProblemRow(text: problem),
        ],
      ],
    );
  }
}

/// Something in the folder that could not be read, said out loud.
class ExtensionProblemRow extends StatelessWidget {
  const ExtensionProblemRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 15,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

/// The extensions that were compiled in, with a switch each.
///
/// These are not in a folder and cannot be added at runtime, so they are shown
/// apart from installed ones — but they can still be turned off, which unwinds
/// every block, command and theme they registered.
class BuiltInExtensionsSection extends StatelessWidget {
  const BuiltInExtensionsSection({super.key, this.showHeading = true});

  /// Settings draws its own category title, so it turns this off.
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: DartExtensionHost.instance,
      builder: (context, _) {
        final host = DartExtensionHost.instance;
        final extensions = host.extensions;
        if (extensions.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeading) ...[
              Text(
                LocaleKeys.extensions_builtIn.tr(),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
            ],
            Text(
              LocaleKeys.extensions_builtInHint.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final extension in extensions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            extension.info.name,
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            '${extension.info.id} · ${extension.info.version}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (extension.info.description.isNotEmpty)
                            Text(
                              extension.info.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Switch(
                      value: host.isEnabled(extension.info.id),
                      onChanged: (value) =>
                          host.setEnabled(extension.info.id, value),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Picks between AppFlowy's own appearance and one an extension supplies.
///
/// Only shown once an extension actually registers a theme, so the setting
/// does not sit there permanently offering a single choice.
class ExtensionThemeChoice extends StatelessWidget {
  const ExtensionThemeChoice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: ExtensionThemeRegistry.changes,
      builder: (context, _) {
        final themes = ExtensionThemeRegistry.all();
        if (themes.isEmpty) {
          return const SizedBox.shrink();
        }
        final selected = ExtensionThemeRegistry.selected.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.extensions_themeLabel.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(LocaleKeys.extensions_themeDefault.tr()),
                  selected: selected.isEmpty,
                  onSelected: (_) => DartExtensionHost.instance.selectTheme(''),
                ),
                for (final entry in themes)
                  ChoiceChip(
                    label: Text(entry.name),
                    selected: selected == ExtensionThemeRegistry.keyOf(entry),
                    onSelected: (_) => DartExtensionHost.instance
                        .selectTheme(ExtensionThemeRegistry.keyOf(entry)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              LocaleKeys.extensions_themeHint.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One action, with what it last did and when it is next owed a turn.
class ExtensionActionRow extends StatefulWidget {
  const ExtensionActionRow({
    super.key,
    required this.extension,
    required this.action,
    required this.log,
    required this.scheduler,
    required this.enabled,
  });

  final LoadedExtension extension;
  final ActionDefinition action;
  final ExtensionRunLog log;
  final ActionScheduler scheduler;
  final bool enabled;

  @override
  State<ExtensionActionRow> createState() => _ExtensionActionRowState();
}

class _ExtensionActionRowState extends State<ExtensionActionRow> {
  bool _running = false;

  Future<void> _runNow() async {
    setState(() => _running = true);
    try {
      final run = await widget.scheduler.runNow(
        extensionId: widget.extension.id,
        actionId: widget.action.id,
      );
      if (mounted) {
        showToastNotification(
          context: context,
          message: run.status == ActionRunStatus.ok
              ? LocaleKeys.extensions_ranOk.tr(args: [widget.action.id])
              : (run.message.isEmpty ? run.status.name : run.message),
          type: run.status == ActionRunStatus.ok
              ? ToastificationType.success
              : ToastificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = widget.action;
    final last = widget.log.lastRunOf(widget.extension.id, action.id);
    final next = widget.scheduler.nextRunOf(widget.extension.id, action);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        action.id,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ExtensionTriggerChip(trigger: action.trigger),
                  ],
                ),
                if (action.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    action.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  describeLastRun(last, next),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: last?.status == ActionRunStatus.failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (_running)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: widget.enabled && action.enabled ? _runNow : null,
              child: Text(LocaleKeys.extensions_runNow.tr()),
            ),
        ],
      ),
    );
  }
}

/// "Ran · 20 Aug 2026 14:10 · 8 ms — next at 14:25".
String describeLastRun(ActionRun? last, DateTime? next) {
  final parts = <String>[];
  if (last == null) {
    parts.add(LocaleKeys.extensions_neverRun.tr());
  } else {
    final when = DateFormat.yMMMd().add_Hm().format(last.startedAt);
    parts.add(
      '${describeRunStatus(last.status)} · $when · '
      '${last.duration.inMilliseconds} ms',
    );
    if (last.message.isNotEmpty) {
      parts.add(last.message);
    }
  }
  if (next != null) {
    parts.add(
      LocaleKeys.extensions_nextRun.tr(args: [DateFormat.Hm().format(next)]),
    );
  }
  return parts.join(' — ');
}

String describeRunStatus(ActionRunStatus status) => switch (status) {
      ActionRunStatus.ok => LocaleKeys.extensions_statusOk.tr(),
      ActionRunStatus.failed => LocaleKeys.extensions_statusFailed.tr(),
      ActionRunStatus.refused => LocaleKeys.extensions_statusRefused.tr(),
      ActionRunStatus.skipped => LocaleKeys.extensions_statusSkipped.tr(),
      ActionRunStatus.running => LocaleKeys.extensions_statusRunning.tr(),
    };

/// How an action starts itself, in a word.
class ExtensionTriggerChip extends StatelessWidget {
  const ExtensionTriggerChip({super.key, required this.trigger});

  final ActionTrigger trigger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _label();
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }

  String _label() {
    final schedule = trigger.schedule;
    if (schedule != null) {
      final interval = schedule.interval;
      if (interval != null) {
        return LocaleKeys.extensions_triggerEvery.tr(
          args: [readableInterval(interval)],
        );
      }
      final minutes = schedule.minutesAfterMidnight ?? 0;
      final hour = (minutes ~/ 60).toString().padLeft(2, '0');
      final minute = (minutes % 60).toString().padLeft(2, '0');
      return LocaleKeys.extensions_triggerAt.tr(args: ['$hour:$minute']);
    }
    if (trigger.event != ActionEvent.none) {
      return trigger.event.name;
    }
    return LocaleKeys.extensions_triggerManual.tr();
  }
}

String readableInterval(Duration interval) {
  if (interval.inDays > 0 && interval.inHours % 24 == 0) {
    return '${interval.inDays}d';
  }
  if (interval.inHours > 0 && interval.inMinutes % 60 == 0) {
    return '${interval.inHours}h';
  }
  if (interval.inMinutes > 0 && interval.inSeconds % 60 == 0) {
    return '${interval.inMinutes}m';
  }
  return '${interval.inSeconds}s';
}

/// The folder every extension is read from.
class ExtensionFolderRow extends StatelessWidget {
  const ExtensionFolderRow({
    super.key,
    required this.path,
    required this.onOpen,
    required this.onCopy,
  });

  final String path;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            path.isEmpty ? '…' : path,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: LocaleKeys.extensions_copyPath.tr(),
          onPressed: path.isEmpty ? null : onCopy,
          icon: const Icon(Icons.copy_rounded, size: 16),
        ),
        IconButton(
          tooltip: LocaleKeys.extensions_openFolder.tr(),
          onPressed: path.isEmpty ? null : onOpen,
          icon: const Icon(Icons.folder_open_rounded, size: 16),
        ),
      ],
    );
  }
}

/// What the example scaffold writes, shared by both surfaces.
const exampleExtensionId = 'example';

const String exampleExtensionManifest = '''
{
  // Everything an extension may reach has to be named here. A capability that
  // is not declared is refused, because a trigger has nobody to ask.
  "id": "$exampleExtensionId",
  "name": "Example",
  "version": "1.0.0",
  "apiVersion": 1,
  "description": "A worked example. Edit the files and the change is picked up at once.",
  "permissions": ["data", "net:worldtimeapi.org", "notify"]
}
''';

const String exampleExtensionAction = '''
{
  "id": "clock",
  "description": "Reads the time in London and keeps it where a block can show it.",
  "risk": "read",
  "schema": { "type": "object", "properties": {} },

  // Polling. Change this to { "on": "start" } for an interrupt instead.
  "trigger": { "every": "15m" },

  "steps": [
    {
      "id": "fetch",
      "http": { "get": "https://worldtimeapi.org/api/timezone/Europe/London" }
    },
    {
      // A flat comparison is the whole condition language. Anything more
      // belongs in a script step or an MCP tool.
      "when": "{{ fetch.status }} == 200",
      "set": {
        "key": "clock.london",
        "value": "{{ fetch.body.datetime }}",
        "staleAfter": "1h"
      }
    }
  ]
}
''';
