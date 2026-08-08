import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/collections/email/connected_accounts.dart';
import 'package:appflowy/workspace/application/collections/email/mail_secret_store.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The mailboxes AppFlowy reads, and what each one signs in with.
///
/// A section rather than a page: a mailbox is not a separate kind of account,
/// it is one more thing an already connected account is used for. Gmail and
/// Outlook are shown as the account they belong to; only a server with no
/// other way in still has a password of its own to manage.
class MailboxesSection extends StatefulWidget {
  const MailboxesSection({super.key});

  @override
  State<MailboxesSection> createState() => _MailboxesSectionState();
}

class _MailboxesSectionState extends State<MailboxesSection> {
  final ConnectedAccountRegistry _registry = const ConnectedAccountRegistry();
  final MailSecretStore _secrets = MailSecretStore();

  List<ConnectedAccount> _mailboxes = const <ConnectedAccount>[];
  Set<String> _ready = const <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ProviderConnections.instance.ensureLoaded();
    // A mailbox read with a connected account has nothing to manage here: it
    // is that account's row. Only a server with a password of its own does.
    final mailboxes = [
      for (final mailbox in await _registry.all())
        if (mailbox.connectionId.isEmpty) mailbox,
    ];
    final ready = <String>{};
    for (final mailbox in mailboxes) {
      if (await _secrets.has(mailbox.id)) {
        ready.add(mailbox.id);
      }
    }
    if (mounted) {
      setState(() {
        _mailboxes = mailboxes;
        _ready = ready;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _mailboxes.isEmpty) {
      return const SizedBox.shrink();
    }
    return SettingsCategory(
      title: LocaleKeys.settings_accountsPage_mail.tr(),
      children: [
        for (final mailbox in _mailboxes)
          _MailboxTile(
            key: ValueKey(mailbox.id),
            mailbox: mailbox,
            isReady: _ready.contains(mailbox.id),
            secrets: _secrets,
            onChanged: _load,
            onRemove: () async {
              await _secrets.forget(mailbox.id);
              await _registry.remove(mailbox.id);
              await _load();
            },
          ),
      ],
    );
  }
}

class _MailboxTile extends StatefulWidget {
  const _MailboxTile({
    super.key,
    required this.mailbox,
    required this.isReady,
    required this.secrets,
    required this.onChanged,
    required this.onRemove,
  });

  final ConnectedAccount mailbox;
  final bool isReady;
  final MailSecretStore secrets;
  final Future<void> Function() onChanged;
  final Future<void> Function() onRemove;

  @override
  State<_MailboxTile> createState() => _MailboxTileState();
}

class _MailboxTileState extends State<_MailboxTile> {
  final TextEditingController _secret = TextEditingController();
  bool _editing = false;
  String _note = '';

  /// Whether this mailbox has a password of its own to manage at all.
  bool get _hasOwnPassword => widget.mailbox.connectionId.isEmpty;

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
    await widget.secrets.write(widget.mailbox.id, value, remember: true);
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
    await widget.secrets.forget(widget.mailbox.id);
    if (!mounted) {
      return;
    }
    setState(
      () => _note = LocaleKeys.settings_accountsPage_passwordForgotten.tr(),
    );
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mailbox = widget.mailbox;
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
                      mailbox.username.isEmpty
                          ? mailbox.host
                          : mailbox.username,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(mailbox),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              _StateChip(
                label: widget.isReady
                    ? LocaleKeys.settings_accountsPage_signedIn.tr()
                    : _hasOwnPassword
                        ? LocaleKeys.settings_accountsPage_needsPassword.tr()
                        : LocaleKeys.settings_accountsPage_needsSignIn.tr(),
                tone: widget.isReady
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
                hintText: mailbox.provider.needsAppPassword
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
              if (_hasOwnPassword) ...[
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
                if (!_editing && widget.isReady)
                  TextButton(
                    onPressed: _forget,
                    child: Text(
                      LocaleKeys.settings_accountsPage_forgetPassword.tr(),
                    ),
                  ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    LocaleKeys.settings_accountsPage_managedByAccount.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
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

  String _subtitle(ConnectedAccount mailbox) {
    final account = mailbox.connectionId.isEmpty
        ? null
        : ProviderConnections.instance.byId(mailbox.connectionId);
    return <String>[
      mailbox.provider.label,
      if (account != null)
        LocaleKeys.settings_accountsPage_viaAccount
            .tr(args: [account.accountLabel])
      else if (mailbox.host.isNotEmpty)
        mailbox.host,
      if (mailbox.mailbox.isNotEmpty) mailbox.mailbox,
      if (mailbox.collectionName.isNotEmpty)
        LocaleKeys.settings_accountsPage_inCollection
            .tr(args: [mailbox.collectionName]),
    ].join(' · ');
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
