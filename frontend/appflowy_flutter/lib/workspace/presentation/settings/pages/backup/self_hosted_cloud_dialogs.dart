// Setting up sync through a self-hosted AppFlowy Cloud: where it is, who you
// are there, and which of its sync folders to use.

import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/sync/self_hosted_cloud.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_backend/log.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What a new sync folder is called: the same on every computer, so the second
/// one finds what the first one made — and not translated, for that reason.
const String defaultSelfHostedSyncFolder = 'AppFlowy';

const Color _errorColor = Color(0xFFD9534F);

/// Asks where the AppFlowy Cloud is, signs in there and picks the sync folder.
/// Null when any step is cancelled.
Future<BackupDestination?> chooseSelfHostedCloudDestination(
  BuildContext context, {
  SelfHostedCloud? cloud,
}) async {
  final accounts = SelfHostedCloudAccounts.instance;
  await accounts.ensureLoaded();
  final recent = accounts.all.lastOrNull;
  if (!context.mounted) {
    return null;
  }
  final account = await showDialog<SelfHostedCloudAccount>(
    context: context,
    builder: (_) => SelfHostedCloudSignInDialog(
      cloud: cloud,
      server: recent?.server ?? '',
      email: recent?.email ?? '',
    ),
  );
  if (account == null || !context.mounted) {
    return null;
  }
  final folder = await showDialog<String>(
    context: context,
    builder: (_) => SelfHostedCloudFolderDialog(account: account, cloud: cloud),
  );
  if (folder == null) {
    return null;
  }
  return BackupDestination(
    kind: BackupDestinationKind.selfHostedCloud,
    connectionId: account.id,
    accountLabel: account.label,
    folderId: folder,
    folderName: folder,
    server: account.server,
  );
}

/// Signs in again to the account [destination]'s folder is kept with, keeping
/// the account's id so the destination still names it. True when signed in.
Future<bool> signInAgainToSelfHostedCloud(
  BuildContext context,
  BackupDestination destination, {
  SelfHostedCloud? cloud,
}) async {
  final accounts = SelfHostedCloudAccounts.instance;
  await accounts.ensureLoaded();
  final kept = accounts.byId(destination.connectionId);
  if (!context.mounted) {
    return false;
  }
  final account = await showDialog<SelfHostedCloudAccount>(
    context: context,
    builder: (_) => SelfHostedCloudSignInDialog(
      cloud: cloud,
      server: kept?.server ?? destination.server,
      email: kept?.email ?? destination.accountLabel.split(' · ').first,
      keepId: destination.connectionId,
    ),
  );
  return account != null;
}

/// Signs in to — or signs up on — a self-hosted AppFlowy Cloud, asking for its
/// address first.
class SelfHostedCloudSignInDialog extends StatefulWidget {
  const SelfHostedCloudSignInDialog({
    super.key,
    this.server = '',
    this.email = '',
    this.keepId,
    this.cloud,
  });

  final String server;
  final String email;

  /// Signing in again: the server stays as it is, and the account keeps this
  /// id.
  final String? keepId;

  final SelfHostedCloud? cloud;

  @override
  State<SelfHostedCloudSignInDialog> createState() =>
      _SelfHostedCloudSignInDialogState();
}

class _SelfHostedCloudSignInDialogState
    extends State<SelfHostedCloudSignInDialog> {
  late final TextEditingController _server =
      TextEditingController(text: widget.server);
  late final TextEditingController _email =
      TextEditingController(text: widget.email);
  final TextEditingController _password = TextEditingController();

  bool _creating = false;
  bool _working = false;
  String? _error;
  String? _notice;

  /// The address last found to keep sync folders, so another try at the
  /// password does not ask the server again.
  String? _readyServer;

  SelfHostedCloud get _cloud => widget.cloud ?? SelfHostedCloud.instance;

  bool get _again => widget.keepId != null;

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) {
      return;
    }
    final server = SelfHostedCloud.normalizeServer(_server.text);
    if (server == null) {
      setState(() => _error = LocaleKeys.firstRun_serverInvalid.tr());
      return;
    }
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = LocaleKeys.selfHostedSync_missingFields.tr());
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_readyServer != server) {
        final problem = switch (await _cloud.check(server)) {
          SelfHostedCloudCheck.ready => null,
          SelfHostedCloudCheck.noSyncFolders =>
            LocaleKeys.selfHostedSync_noSyncFolders.tr(),
          SelfHostedCloudCheck.notAppFlowyCloud =>
            LocaleKeys.selfHostedSync_notAppFlowyCloud.tr(),
          SelfHostedCloudCheck.unreachable =>
            LocaleKeys.selfHostedSync_unreachable.tr(),
        };
        if (!mounted) {
          return;
        }
        if (problem != null) {
          setState(() => _error = problem);
          return;
        }
        _readyServer = server;
      }
      if (_creating) {
        final signedUp = await _cloud.signUp(
          server: server,
          email: email,
          password: password,
        );
        if (!mounted) {
          return;
        }
        if (signedUp.needsConfirmation) {
          _password.clear();
          setState(() {
            _creating = false;
            _notice = LocaleKeys.selfHostedSync_confirmEmail.tr();
          });
          return;
        }
        Navigator.of(context).pop(signedUp.account);
        return;
      }
      final account = await _cloud.signIn(
        server: server,
        email: email,
        password: password,
        keepId: widget.keepId,
      );
      if (mounted) {
        Navigator.of(context).pop(account);
      }
    } on SelfHostedCloudAuthError catch (error) {
      Log.info('Signing in to a self-hosted AppFlowy Cloud did not work: '
          '$error');
      if (mounted) {
        setState(() => _error = _describe(error.problem));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  static String _describe(SelfHostedCloudAuthProblem problem) =>
      switch (problem) {
        SelfHostedCloudAuthProblem.wrongPassword =>
          LocaleKeys.selfHostedSync_wrongPassword.tr(),
        SelfHostedCloudAuthProblem.emailNotConfirmed =>
          LocaleKeys.selfHostedSync_emailNotConfirmed.tr(),
        SelfHostedCloudAuthProblem.signUpsClosed =>
          LocaleKeys.selfHostedSync_signUpsClosed.tr(),
        SelfHostedCloudAuthProblem.accountExists =>
          LocaleKeys.selfHostedSync_accountExists.tr(),
        SelfHostedCloudAuthProblem.weakPassword =>
          LocaleKeys.selfHostedSync_weakPassword.tr(),
        SelfHostedCloudAuthProblem.unreachable =>
          LocaleKeys.selfHostedSync_unreachable.tr(),
        SelfHostedCloudAuthProblem.refused =>
          LocaleKeys.selfHostedSync_refused.tr(),
      };

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);
    final focusServer = !_again && widget.server.isEmpty;
    final focusEmail = !focusServer && widget.email.isEmpty;
    void submit(String _) => unawaited(_submit());

    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.selfHostedSync_signInTitle.tr(),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _again
                    ? LocaleKeys.selfHostedSync_signInAgainBody
                        .tr(args: [serverHost(widget.server)])
                    : LocaleKeys.selfHostedSync_signInBody.tr(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: premium.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              if (!_again) ...[
                ProviderTextField(
                  key: const ValueKey('self-hosted-sync-server'),
                  label: LocaleKeys.firstRun_serverAddress.tr(),
                  hint: 'https://appflowy.example.com',
                  controller: _server,
                  palette: palette,
                  autofocus: focusServer,
                  onSubmitted: submit,
                ),
                const SizedBox(height: 12),
              ],
              ProviderTextField(
                key: const ValueKey('self-hosted-sync-email'),
                label: LocaleKeys.selfHostedSync_email.tr(),
                hint: 'name@example.com',
                controller: _email,
                palette: palette,
                autofocus: focusEmail,
                onSubmitted: submit,
              ),
              const SizedBox(height: 12),
              ProviderTextField(
                key: const ValueKey('self-hosted-sync-password'),
                label: LocaleKeys.selfHostedSync_password.tr(),
                controller: _password,
                palette: palette,
                obscure: true,
                autofocus: !focusServer && !focusEmail,
                onSubmitted: submit,
              ),
              if (!_again) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _working
                      ? null
                      : () => setState(() {
                            _creating = !_creating;
                            _error = null;
                            _notice = null;
                          }),
                  child: Text(
                    _creating
                        ? LocaleKeys.selfHostedSync_haveAccount.tr()
                        : LocaleKeys.selfHostedSync_noAccount.tr(),
                  ),
                ),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 6),
                Text(
                  _notice!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: premium.textSecondary,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12.5, color: _errorColor),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: _working ? null : () => unawaited(_submit()),
          child: _working
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _creating
                      ? LocaleKeys.selfHostedSync_createAccount.tr()
                      : LocaleKeys.selfHostedSync_signIn.tr(),
                ),
        ),
      ],
    );
  }
}

/// Picks the sync folder on the server: one already there, which another
/// computer syncs to, or a new one.
class SelfHostedCloudFolderDialog extends StatefulWidget {
  const SelfHostedCloudFolderDialog({
    super.key,
    required this.account,
    this.cloud,
  });

  final SelfHostedCloudAccount account;
  final SelfHostedCloud? cloud;

  @override
  State<SelfHostedCloudFolderDialog> createState() =>
      _SelfHostedCloudFolderDialogState();
}

class _SelfHostedCloudFolderDialogState
    extends State<SelfHostedCloudFolderDialog> {
  final TextEditingController _name =
      TextEditingController(text: defaultSelfHostedSyncFolder);

  /// Null while the server is being asked.
  List<String>? _folders;
  bool _failed = false;

  /// The folder already there that was picked, or null for a new one.
  String? _picked;
  String? _nameError;

  SelfHostedCloud get _cloud => widget.cloud ?? SelfHostedCloud.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() {
      _folders = null;
      _failed = false;
    });
    await _load();
  }

  Future<void> _load() async {
    try {
      final folders = await _cloud.folders(widget.account);
      if (!mounted) {
        return;
      }
      setState(() {
        _folders = folders;
        _picked = folders.contains(defaultSelfHostedSyncFolder)
            ? defaultSelfHostedSyncFolder
            : folders.firstOrNull;
        if (folders.contains(_name.text)) {
          _name.clear();
        }
      });
    } on Object catch (error) {
      Log.info('The sync folders on the server could not be read: $error');
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  void _submit() {
    final picked = _picked;
    if (picked != null) {
      Navigator.of(context).pop(picked);
      return;
    }
    final name = _name.text.trim();
    if (!SelfHostedCloud.isValidFolderName(name)) {
      setState(() => _nameError = LocaleKeys.selfHostedSync_folderInvalid.tr());
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);
    final folders = _folders;
    final note = TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: premium.textSecondary,
    );

    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.selfHostedSync_folderTitle.tr(),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.selfHostedSync_folderBody
                    .tr(args: [widget.account.host]),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: premium.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (_failed) ...[
                Text(
                  LocaleKeys.selfHostedSync_folderLoadFailed.tr(),
                  style: const TextStyle(fontSize: 12.5, color: _errorColor),
                ),
                TextButton(
                  onPressed: () => unawaited(_retry()),
                  child: Text(LocaleKeys.button_tryAgain.tr()),
                ),
              ] else if (folders == null)
                Row(
                  children: [
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      LocaleKeys.selfHostedSync_folderLoading.tr(),
                      style: note,
                    ),
                  ],
                )
              else ...[
                for (final folder in folders)
                  _FolderRow(
                    key: ValueKey('self-hosted-sync-folder-$folder'),
                    icon: Icons.folder_rounded,
                    label: folder,
                    selected: _picked == folder,
                    onTap: () => setState(() => _picked = folder),
                  ),
                if (folders.isNotEmpty)
                  _FolderRow(
                    key: const ValueKey('self-hosted-sync-folder-new'),
                    icon: Icons.create_new_folder_rounded,
                    label: LocaleKeys.selfHostedSync_folderNew.tr(),
                    selected: _picked == null,
                    onTap: () => setState(() => _picked = null),
                  ),
                if (_picked == null) ...[
                  const SizedBox(height: 10),
                  ProviderTextField(
                    key: const ValueKey('self-hosted-sync-folder-name'),
                    label: LocaleKeys.selfHostedSync_folderName.tr(),
                    hint: defaultSelfHostedSyncFolder,
                    controller: _name,
                    palette: palette,
                    autofocus: folders.isNotEmpty,
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (_nameError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _nameError!,
                    style: const TextStyle(fontSize: 12.5, color: _errorColor),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: folders == null || _failed ? null : _submit,
          child: Text(LocaleKeys.selfHostedSync_continue.tr()),
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return Material(
      color: selected ? premium.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        hoverColor: premium.hover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 17, color: premium.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: premium.textPrimary),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 17, color: premium.accent),
            ],
          ),
        ),
      ),
    );
  }
}
