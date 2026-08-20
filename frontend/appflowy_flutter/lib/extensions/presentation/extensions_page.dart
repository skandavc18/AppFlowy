import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_run_log.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/presentation/extension_folder_actions.dart';
import 'package:appflowy/extensions/presentation/extension_views.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The Extensions page, reached from the sidebar above Trash.
///
/// Everything installed, whether it is on, and — the part that matters — what
/// each action actually did the last few times it ran.
class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key});

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage> {
  final ExtensionStore _store = ExtensionStore.instance;
  final ExtensionRunLog _log = ExtensionRunLog.instance;
  final ActionScheduler _scheduler = ActionScheduler.instance;

  late final ExtensionFolderActions _folder =
      ExtensionFolderActions(store: _store);

  String _root = '';
  String? _openId;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    _log.addListener(_onChanged);
    _scheduler.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _log.removeListener(_onChanged);
    _scheduler.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final root = await _store.resolveRoot();
    await _store.ensureLoaded();
    await _log.ensureLoaded();
    if (mounted) {
      setState(() => _root = root);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extensions = _store.extensions;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocaleKeys.extensions_settingsTitle.tr(),
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      LocaleKeys.extensions_settingsSubtitle.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _store.isLoading ? null : _store.reload,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(LocaleKeys.extensions_reload.tr()),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _root.isEmpty
                    ? null
                    : () => _folder.writeExample(context, _root),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(LocaleKeys.extensions_createExample.tr()),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ExtensionFolderRow(
            path: _root,
            onOpen: () => _folder.openFolder(_root),
            onCopy: () => _folder.copyPath(context, _root),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              children: [
                const BuiltInExtensionsSection(),
                const ExtensionThemeChoice(),
                const SizedBox(height: 18),
                if (extensions.isEmpty)
                  _EmptyState(theme: theme)
                else
                  for (final extension in extensions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ExtensionCard(
                        extension: extension,
                        store: _store,
                        log: _log,
                        scheduler: _scheduler,
                        expanded: _openId == extension.id,
                        onToggleHistory: () => setState(
                          () => _openId =
                              _openId == extension.id ? null : extension.id,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.extension_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            Text(
              LocaleKeys.extensions_noneTitle.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              LocaleKeys.extensions_noneBody.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtensionCard extends StatelessWidget {
  const _ExtensionCard({
    required this.extension,
    required this.store,
    required this.log,
    required this.scheduler,
    required this.expanded,
    required this.onToggleHistory,
  });

  final LoadedExtension extension;
  final ExtensionStore store;
  final ExtensionRunLog log;
  final ActionScheduler scheduler;
  final bool expanded;
  final VoidCallback onToggleHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = store.isEnabled(extension.id);
    final history = log.runsFor(extension.id);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.06),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            extension.manifest.name,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ExtensionHeaderRow(extension: extension, store: store),
          const SizedBox(height: 16),
          if (extension.actions.isEmpty)
            Text(
              LocaleKeys.extensions_noActions.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final action in extension.actions)
              ExtensionActionRow(
                extension: extension,
                action: action,
                log: log,
                scheduler: scheduler,
                enabled: enabled,
              ),
          if (history.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onToggleHistory,
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                ),
                label: Text(
                  LocaleKeys.extensions_history.tr(args: ['${history.length}']),
                ),
              ),
            ),
            if (expanded)
              for (final run in history.take(12))
                _RunRow(run: run, theme: theme),
          ],
        ],
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run, required this.theme});

  final ActionRun run;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final failed = run.status == ActionRunStatus.failed ||
        run.status == ActionRunStatus.refused;
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${run.actionId} · ${run.cause.name} · '
              '${describeLastRun(run, null)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
