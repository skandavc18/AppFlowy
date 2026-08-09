import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/collections/email/connected_accounts.dart';
import 'package:appflowy/workspace/application/collections/email/mail_secret_store.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/settings/pages/connections/connections_chrome.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Whose account a password mailbox actually belongs to.
///
/// An app password is not a different kind of account, it is a different way
/// into the same one — so a Gmail mailbox signed in that way belongs under
/// Google beside the browser sign in, not in a list of its own. A server with
/// no account behind it (a self-hosted IMAP box, iCloud, Fastmail) answers
/// null and is listed on its own.
ProviderAccountFamily? mailboxAccountFamily(ConnectedAccount mailbox) {
  final service = mailbox.provider.oauthService;
  return service == null ? null : ProviderServices.of(service).family;
}

/// One mailbox, and the password it signs in with.
///
/// Only a mailbox with a password of its own has anything to manage here: one
/// read through a connected account is that account's business, and says so.
class MailboxTile extends StatefulWidget {
  const MailboxTile({
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
  State<MailboxTile> createState() => _MailboxTileState();
}

class _MailboxTileState extends State<MailboxTile> {
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
    final palette = FolderExplorerPalette.of(context);
    final mailbox = widget.mailbox;
    final family = mailboxAccountFamily(mailbox);

    return ConnectionCard(
      palette: palette,
      leading: ConnectionGlyph(
        icon: Icons.alternate_email_rounded,
        accent: family?.accent ?? palette.accent,
        muted: !widget.isReady,
      ),
      title: mailbox.username.isEmpty ? mailbox.host : mailbox.username,
      subtitle: _subtitle(mailbox),
      trailing: _StateChip(
        label: widget.isReady
            ? LocaleKeys.settings_accountsPage_signedIn.tr()
            : _hasOwnPassword
                ? LocaleKeys.settings_accountsPage_needsPassword.tr()
                : LocaleKeys.settings_accountsPage_needsSignIn.tr(),
        tone: widget.isReady ? palette.accent : palette.danger,
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editing) ...[
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
            const SizedBox(height: 8),
          ],
          if (_note.isNotEmpty) ...[
            Text(
              _note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              if (_hasOwnPassword) ...[
                ConnectionTextButton(
                  label: _editing
                      ? LocaleKeys.settings_accountsPage_save.tr()
                      : LocaleKeys.settings_accountsPage_changePassword.tr(),
                  onPressed:
                      _editing ? _save : () => setState(() => _editing = true),
                ),
                if (_editing)
                  ConnectionTextButton(
                    label: LocaleKeys.button_cancel.tr(),
                    onPressed: () => setState(() {
                      _editing = false;
                      _secret.clear();
                    }),
                  ),
                if (!_editing && widget.isReady)
                  ConnectionTextButton(
                    label: LocaleKeys.settings_accountsPage_forgetPassword.tr(),
                    onPressed: _forget,
                  ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    LocaleKeys.settings_accountsPage_managedByAccount.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              const Spacer(),
              ConnectionTextButton(
                label: LocaleKeys.settings_accountsPage_remove.tr(),
                tone: palette.danger,
                onPressed: () => widget.onRemove(),
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
      // An app password is the alternative to the browser sign in above it, so
      // the row has to say which route this mailbox took.
      if (account == null && mailbox.provider.signsInWithAccount)
        LocaleKeys.providers_settings_appPasswordMailbox.tr()
      else
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
