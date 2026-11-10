// The first screen's ways to start.
//
// Instead of an account to sign in to, a person picks where their workspace
// lives: in a folder in Google Drive, OneDrive or Box that keeps every computer
// they use the same, on their own AppFlowy server, or on this computer only.

import 'dart:async';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/sign_in_anonymous_button.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/settings/appflowy_cloud_urls_bloc.dart'
    show validateUrl;
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/sync/app_synced_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/backup_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/sync_dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FirstRunSyncOptions extends StatefulWidget {
  const FirstRunSyncOptions({
    super.key,
    this.showLocalOption = true,
    this.startLocal,
  });

  /// Whether "this computer only" is offered here, rather than by a button of
  /// the screen's own.
  final bool showLocalOption;

  /// Makes a workspace on this computer. A guest sign in when not given.
  final Future<void> Function()? startLocal;

  @override
  State<FirstRunSyncOptions> createState() => _FirstRunSyncOptionsState();
}

class _FirstRunSyncOptionsState extends State<FirstRunSyncOptions> {
  WorkspaceSyncEngine get _sync => WorkspaceSyncEngine.instance;

  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            LocaleKeys.firstRun_title.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: premium.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            LocaleKeys.firstRun_body.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: premium.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          for (final kind in const [
            BackupDestinationKind.googleDrive,
            BackupDestinationKind.oneDrive,
            BackupDestinationKind.box,
          ]) ...[
            _OptionCard(
              key: ValueKey('first-run-${kind.name}'),
              icon: backupDestinationIcon(kind),
              accent: backupDestinationAccent(kind),
              title: LocaleKeys.firstRun_syncWith
                  .tr(args: [backupDestinationLabel(kind)]),
              body: LocaleKeys.firstRun_syncWithBody.tr(),
              enabled: !_working,
              onTap: () => unawaited(_syncWith(kind)),
            ),
            const SizedBox(height: 8),
          ],
          _OptionCard(
            key: const ValueKey('first-run-self-hosted'),
            icon: Icons.dns_rounded,
            accent: premium.accent,
            title: LocaleKeys.firstRun_selfHosted.tr(),
            body: LocaleKeys.firstRun_selfHostedBody.tr(),
            enabled: !_working,
            onTap: () => unawaited(_selfHosted()),
          ),
          if (widget.showLocalOption) ...[
            const SizedBox(height: 14),
            Center(
              child: SignInAnonymousButtonV2(
                label: LocaleKeys.firstRun_thisComputer.tr(),
                beforeStart: () => offerAppPassword(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Sync can be set up before any workspace exists: a folder that holds one
  /// is joined, and AppFlowy restarts into it; an empty one is sealed and
  /// waits for the workspace made next.
  void _prepareSync() {
    _sync.configure(
      dataPath: () => getIt<ApplicationDataStorage>().getPath(),
      restart: () async {
        _sync.detach();
        await runAppFlowy();
      },
      preferences: AppSyncedPreferences(
        dataPath: () => getIt<ApplicationDataStorage>().getPath(),
        workspaceId: () => _sync.binding?.workspaceId,
      ),
    );
  }

  Future<void> _syncWith(BackupDestinationKind kind) async {
    setState(() => _working = true);
    try {
      _prepareSync();
      final destination = await chooseProviderFolder(context, kind);
      if (destination == null || !mounted) {
        return;
      }
      await continueSyncSetup(
        context,
        destination,
        onEmptyFolder: () async {
          final ready = await runWithSyncProgress(
            context,
            title: LocaleKeys.sync_startConfirm.tr(),
            work: () async {
              await _sync.startWhenReady(destination);
              return true;
            },
          );
          if (ready == true && mounted) {
            // A workspace of its own first; sync starts in the folder as
            // soon as it is open.
            final startLocal = widget.startLocal;
            if (startLocal != null) {
              await startLocal();
            } else {
              context.read<SignInBloc>().add(const SignInEvent.signInAsGuest());
            }
          }
        },
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _selfHosted() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _ServerAddressDialog(),
    );
    if (url == null || !mounted) {
      return;
    }
    await useBaseWebDomain(ShareConstants.defaultBaseWebDomain);
    await useSelfHostedAppFlowyCloud(url);
    await runAppFlowy();
  }
}

/// Offers to choose the AppFlowy password before the first workspace is made
/// on this computer. "Not now" carries on without one; whatever needs it later
/// asks then. Always true: there is no going back from here.
Future<bool> offerAppPassword(BuildContext context) async {
  // Tests sign in by the button and have nobody to answer.
  if (FlowyRunner.currentMode.isTest) {
    return true;
  }
  final passwords = AppPassword.instance;
  await passwords.ensureLoaded();
  if (passwords.isSet || !context.mounted) {
    return true;
  }
  await askAppPassword(
    context,
    question: AppPasswordQuestion.choose,
    skipLabel: LocaleKeys.appPassword_skip.tr(),
    check: (password) async {
      await passwords.choose(password);
      return null;
    },
  );
  return true;
}

class _OptionCard extends StatefulWidget {
  const _OptionCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_OptionCard> createState() => _OptionCardState();
}

class _OptionCardState extends State<_OptionCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final surface = _hovering ? premium.hover : premium.surface;
    const wash = 0.12;
    final ink = LegibleColor.onWash(
      surface,
      widget.accent,
      wash: wash,
      minimum: LegibleColor.glyph,
    );
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: premium.border),
          ),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.5,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: wash),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, size: 18, color: ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: premium.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.body,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: premium.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: premium.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks where a self-hosted AppFlowy server is.
class _ServerAddressDialog extends StatefulWidget {
  const _ServerAddressDialog();

  @override
  State<_ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<_ServerAddressDialog> {
  final TextEditingController _address = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final typed = _address.text.trim();
    final address = typed.contains('://') ? typed : 'https://$typed';
    validateUrl(address).fold(
      (url) {
        final host = Uri.tryParse(url)?.host ?? '';
        if (host.isEmpty) {
          setState(() => _error = LocaleKeys.firstRun_serverInvalid.tr());
          return;
        }
        Navigator.of(context).pop(url);
      },
      (error) => setState(() => _error = error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.firstRun_selfHosted.tr(),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.firstRun_serverBody.tr(),
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: premium.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ProviderTextField(
              label: LocaleKeys.firstRun_serverAddress.tr(),
              hint: 'https://appflowy.example.com',
              controller: _address,
              palette: FolderExplorerPalette.of(context),
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style:
                    const TextStyle(fontSize: 12.5, color: Color(0xFFD9534F)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(LocaleKeys.firstRun_serverContinue.tr()),
        ),
      ],
    );
  }
}

/// Goes back to the first screen's choices from a self-hosted server's sign
/// in.
Future<void> chooseAnotherWayToStart() async {
  await useAppFlowyBetaCloudWithURL(
    kAppflowyCloudUrl,
    AuthenticatorType.appflowyCloud,
  );
  await runAppFlowy();
}
