import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_run_log.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/presentation/extension_folder_actions.dart';
import 'package:appflowy/extensions/presentation/extension_views.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Settings ▸ Extensions.
///
/// Its real job is the run log. An action that quietly stopped working is
/// indistinguishable from one that was never written, so every action says
/// when it last ran, how long it took, what went wrong and when it is next
/// owed a turn.
class SettingsExtensionsView extends StatefulWidget {
  const SettingsExtensionsView({super.key});

  @override
  State<SettingsExtensionsView> createState() => _SettingsExtensionsViewState();
}

class _SettingsExtensionsViewState extends State<SettingsExtensionsView> {
  final ExtensionStore _store = ExtensionStore.instance;
  final ExtensionRunLog _log = ExtensionRunLog.instance;
  final ActionScheduler _scheduler = ActionScheduler.instance;

  late final ExtensionFolderActions _folder =
      ExtensionFolderActions(store: _store);

  String _root = '';

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
    return SettingsBody(
      title: LocaleKeys.extensions_settingsTitle.tr(),
      description: LocaleKeys.extensions_settingsSubtitle.tr(),
      children: [
        SettingsCategory(
          title: LocaleKeys.extensions_folderLabel.tr(),
          children: [
            ExtensionFolderRow(
              path: _root,
              onOpen: () => _folder.openFolder(_root),
              onCopy: () => _folder.copyPath(context, _root),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _store.isLoading ? null : _store.reload,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(LocaleKeys.extensions_reload.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: _root.isEmpty
                      ? null
                      : () => _folder.writeExample(context, _root),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(LocaleKeys.extensions_createExample.tr()),
                ),
              ],
            ),
          ],
        ),
        SettingsCategory(
          title: LocaleKeys.extensions_builtIn.tr(),
          children: const [
            BuiltInExtensionsSection(showHeading: false),
            ExtensionThemeChoice(),
          ],
        ),
        if (extensions.isEmpty)
          SettingsCategory(
            title: LocaleKeys.extensions_noneTitle.tr(),
            children: [
              Text(
                LocaleKeys.extensions_noneBody.tr(),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          )
        else
          for (final extension in extensions)
            SettingsCategory(
              title: extension.manifest.name,
              children: [
                ExtensionHeaderRow(extension: extension, store: _store),
                const SizedBox(height: 14),
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
                      log: _log,
                      scheduler: _scheduler,
                      enabled: _store.isEnabled(extension.id),
                    ),
              ],
            ),
      ],
    );
  }
}
