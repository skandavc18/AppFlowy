// The first screen's ways to start.
//
// Instead of an account to sign in to, a person picks where their workspace
// lives: in a folder in Google Drive, OneDrive, Box or their own AppFlowy Cloud
// that keeps every computer they use the same, on an AppFlowy server, or on
// this computer only.

import 'dart:async';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/sign_in_bloc.dart';
import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/sign_in_anonymous_button.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/sync/app_synced_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/appflowy_server.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/backup_dialogs.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/sync_dialogs.dart';
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
            BackupDestinationKind.selfHostedCloud,
          ]) ...[
            _OptionCard(
              key: ValueKey('first-run-${kind.name}'),
              icon: backupDestinationIcon(kind),
              accent: backupDestinationAccent(kind),
              title: kind == BackupDestinationKind.selfHostedCloud
                  ? LocaleKeys.selfHostedSync_signInTitle.tr()
                  : LocaleKeys.firstRun_syncWith
                      .tr(args: [backupDestinationLabel(kind)]),
              body: LocaleKeys.firstRun_syncWithBody.tr(),
              enabled: !_working,
              onTap: () => unawaited(_syncWith(kind)),
            ),
            const SizedBox(height: 8),
          ],
          _OptionCard(
            key: const ValueKey('first-run-self-hosted'),
            icon: Icons.groups_rounded,
            accent: premium.accent,
            title: LocaleKeys.firstRun_selfHosted.tr(),
            body: LocaleKeys.firstRun_selfHostedBody.tr(),
            enabled: !_working,
            onTap: () => unawaited(_selfHosted()),
          ),
          if (widget.showLocalOption) ...[
            const SizedBox(height: 8),
            if (widget.startLocal != null)
              _OptionCard(
                key: const ValueKey('first-run-local'),
                icon: Icons.computer_rounded,
                accent: premium.textSecondary,
                title: LocaleKeys.firstRun_localAccountTitle.tr(),
                body: LocaleKeys.firstRun_localAccountBody.tr(),
                enabled: !_working,
                onTap: () => unawaited(() async {
                  if (await offerAppPassword(context) && mounted) {
                    await widget.startLocal!();
                  }
                }()),
              )
            else
              SignInAnonymousButtonV2(
                label: LocaleKeys.firstRun_localAccountTitle.tr(),
                beforeStart: () => offerAppPassword(context),
                builder: (context, onTap, hasExistingLocal) => _OptionCard(
                  key: const ValueKey('first-run-local'),
                  icon: Icons.computer_rounded,
                  accent: premium.textSecondary,
                  title: hasExistingLocal
                      ? LocaleKeys.signIn_continueAnonymousUser.tr()
                      : LocaleKeys.firstRun_localAccountTitle.tr(),
                  body: LocaleKeys.firstRun_localAccountBody.tr(),
                  enabled: !_working,
                  onTap: onTap,
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
        isFirstRun: true,
        onEmptyFolder: (encrypt) async {
          await _sync.queueStartWhenReady(destination, encrypt: encrypt);
          if (!mounted) {
            return;
          }
          // Open straight into the workspace; initial sync runs asynchronously
          // in the background as soon as the workspace opens.
          final startLocal = widget.startLocal;
          if (startLocal != null) {
            await startLocal();
          } else {
            context.read<SignInBloc>().add(const SignInEvent.signInAsGuest());
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
    final choice = await chooseAppFlowyServer(context);
    if (choice == null || !mounted) {
      return;
    }
    await useAppFlowyServer(choice.url, webUrl: choice.webUrl);
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

/// Goes back to the first screen's choices from a self-hosted server's sign
/// in.
Future<void> chooseAnotherWayToStart() async {
  await useNoServer();
  await runAppFlowy();
}
