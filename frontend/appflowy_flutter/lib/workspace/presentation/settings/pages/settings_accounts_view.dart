import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/collections/email/connected_accounts.dart';
import 'package:appflowy/workspace/application/collections/email/mail_secret_store.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Every account the application is signed in to, and what can be done about
/// them: change the password one was issued, forget it, or drop the account.
class SettingsAccountsView extends StatefulWidget {
  const SettingsAccountsView({super.key});

  @override
  State<SettingsAccountsView> createState() => _SettingsAccountsViewState();
}

class _SettingsAccountsViewState extends State<SettingsAccountsView> {
  final ConnectedAccountRegistry _registry = const ConnectedAccountRegistry();
  final MailSecretStore _secrets = MailSecretStore();

  List<ConnectedAccount> _accounts = const <ConnectedAccount>[];
  Set<String> _withSecret = const <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await _registry.all();
    final held = <String>{};
    for (final account in accounts) {
      if (await _secrets.has(account.id)) {
        held.add(account.id);
      }
    }
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _withSecret = held;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SettingsBody(
        title: LocaleKeys.settings_accountsPage_title.tr(),
        description: LocaleKeys.settings_accountsPage_description.tr(),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_accounts.isEmpty)
            _EmptyAccounts()
          else
            SettingsCategory(
              title: LocaleKeys.settings_accountsPage_mail.tr(),
              children: [
                for (final account in _accounts)
                  _AccountTile(
                    key: ValueKey(account.id),
                    account: account,
                    hasSecret: _withSecret.contains(account.id),
                    secrets: _secrets,
                    onChanged: _load,
                    onRemove: () async {
                      await _secrets.forget(account.id);
                      await _registry.remove(account.id);
                      await _load();
                    },
                  ),
              ],
            ),
        ],
      );
}

class _EmptyAccounts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleKeys.settings_accountsPage_empty.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            LocaleKeys.settings_accountsPage_emptyHint.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatefulWidget {
  const _AccountTile({
    super.key,
    required this.account,
    required this.hasSecret,
    required this.secrets,
    required this.onChanged,
    required this.onRemove,
  });

  final ConnectedAccount account;
  final bool hasSecret;
  final MailSecretStore secrets;
  final Future<void> Function() onChanged;
  final Future<void> Function() onRemove;

  @override
  State<_AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<_AccountTile> {
  final TextEditingController _secret = TextEditingController();
  bool _editing = false;
  String _note = '';

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _secret.text;
    if (value.isEmpty) {
      return;
    }
    await widget.secrets.write(
      widget.account.id,
      value,
      remember: true,
    );
    _secret.clear();
    if (!mounted) {
      return;
    }
    setState(() {
      _editing = false;
      _note = widget.secrets.canPersist
          ? LocaleKeys.settings_accountsPage_passwordSaved.tr()
          : LocaleKeys.settings_accountsPage_passwordSession.tr();
    });
    await widget.onChanged();
  }

  Future<void> _forget() async {
    await widget.secrets.forget(widget.account.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _note = LocaleKeys.settings_accountsPage_passwordForgotten.tr();
    });
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = widget.account;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.alternate_email_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.username.isEmpty
                          ? account.host
                          : account.username,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(account),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              _StateChip(
                label: widget.hasSecret
                    ? LocaleKeys.settings_accountsPage_signedIn.tr()
                    : LocaleKeys.settings_accountsPage_needsPassword.tr(),
                tone: widget.hasSecret
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _secret,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: account.provider.needsAppPassword
                    ? LocaleKeys.settings_accountsPage_appPasswordHint.tr()
                    : LocaleKeys.settings_accountsPage_passwordHint.tr(),
              ),
            ),
          ],
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed:
                    _editing ? _save : () => setState(() => _editing = true),
                child: Text(
                  _editing
                      ? LocaleKeys.settings_accountsPage_save.tr()
                      : LocaleKeys.settings_accountsPage_changePassword.tr(),
                ),
              ),
              if (_editing)
                TextButton(
                  onPressed: () => setState(() {
                    _editing = false;
                    _secret.clear();
                  }),
                  child: Text(LocaleKeys.button_cancel.tr()),
                ),
              if (!_editing && widget.hasSecret)
                TextButton(
                  onPressed: _forget,
                  child: Text(
                    LocaleKeys.settings_accountsPage_forgetPassword.tr(),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => widget.onRemove(),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: Text(LocaleKeys.settings_accountsPage_remove.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(ConnectedAccount account) {
    final pieces = <String>[
      account.provider.label,
      if (account.host.isNotEmpty) account.host,
      if (account.mailbox.isNotEmpty) account.mailbox,
      if (account.collectionName.isNotEmpty)
        LocaleKeys.settings_accountsPage_inCollection
            .tr(args: [account.collectionName]),
    ];
    return pieces.join(' · ');
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}
