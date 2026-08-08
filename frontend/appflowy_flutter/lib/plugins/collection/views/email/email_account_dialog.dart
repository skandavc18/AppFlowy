import 'dart:async';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/workspace/application/collections/email/email_controller.dart';
import 'package:appflowy/workspace/application/collections/email/imap_client.dart';
import 'package:appflowy/workspace/application/collections/email/mail_account.dart';
import 'package:appflowy/workspace/application/collections/email/mail_sync.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_http.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Joins a mailbox to a real server.
///
/// Gmail and Outlook sign in the way everything else in the application signs
/// in — the browser, once, against the account already connected for Drive or
/// OneDrive — and no password is typed here at all. A server with no such way
/// in still asks for one, which is handed straight to the secret store.
Future<void> showMailAccountDialog(
  BuildContext context, {
  required EmailController controller,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _MailAccountDialog(controller: controller),
    );

class _MailAccountDialog extends StatefulWidget {
  const _MailAccountDialog({required this.controller});

  final EmailController controller;

  @override
  State<_MailAccountDialog> createState() => _MailAccountDialogState();
}

class _MailAccountDialogState extends State<_MailAccountDialog> {
  late MailAccount _account;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _mailbox;
  final TextEditingController _secret = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _note;
  List<ImapMailbox> _mailboxes = const <ImapMailbox>[];
  List<ProviderConnection> _accounts = const <ProviderConnection>[];
  String _connectionId = '';

  @override
  void initState() {
    super.initState();
    _account = widget.controller.account ??
        MailAccount.forProvider(MailProvider.gmail);
    _connectionId = _account.connectionId;
    _host = TextEditingController(text: _account.host);
    _port = TextEditingController(text: '${_account.port}');
    _username = TextEditingController(text: _account.username);
    _mailbox = TextEditingController(text: _account.mailbox);
    unawaited(_loadAccounts());
  }

  /// The connected accounts this provider's mail can be read with.
  List<ProviderConnection> _accountsFor(MailProvider provider) {
    final service = provider.oauthService;
    return service == null
        ? const <ProviderConnection>[]
        : ProviderConnections.instance.forService(service);
  }

  Future<void> _loadAccounts() async {
    await ProviderConnections.instance.ensureLoaded();
    if (!mounted) {
      return;
    }
    final accounts = _accountsFor(_account.provider);
    setState(() {
      _accounts = accounts;
      // One account and nothing chosen yet is not a choice worth asking about.
      if (_connectionId.isEmpty && accounts.length == 1) {
        _connectionId = accounts.first.id;
      }
    });
  }

  ProviderConnection? get _chosenAccount {
    for (final account in _accounts) {
      if (account.id == _connectionId) {
        return account;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _mailbox.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = emailThemeOf(context);
    return Dialog(
      backgroundColor: theme.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EmailMetrics.panelRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(EmailMetrics.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                LocaleKeys.collections_email_connectTitle.tr(),
                style: theme.face(
                  fontSize: 17,
                  color: theme.textStrong,
                  axis: 650,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: EmailMetrics.space2),
              Text(
                LocaleKeys.collections_email_connectHint.tr(),
                style: theme.meta.copyWith(height: 1.5),
              ),
              const SizedBox(height: EmailMetrics.space5),
              _providerPicker(theme),
              const SizedBox(height: EmailMetrics.space4),
              if (_account.provider.signsInWithAccount)
                _accountSection(theme)
              else
                _serverSection(theme),
              const SizedBox(height: EmailMetrics.space3),
              _mailboxField(theme),
              if (!_account.provider.signsInWithAccount) ...[
                const SizedBox(height: EmailMetrics.space4),
                _rememberRow(theme),
              ],
              if (_error != null) ...[
                const SizedBox(height: EmailMetrics.space3),
                _banner(theme, _error!, tone: const Color(0xFFD7443E)),
              ],
              if (_note != null) ...[
                const SizedBox(height: EmailMetrics.space3),
                _banner(theme, _note!, tone: theme.accent),
              ],
              const SizedBox(height: EmailMetrics.space5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.controller.isConnected)
                    EmailAction(
                      icon: Icons.link_off_rounded,
                      tooltip: LocaleKeys.collections_email_disconnect.tr(),
                      theme: theme,
                      label: LocaleKeys.collections_email_disconnect.tr(),
                      onPressed: _busy ? null : _disconnect,
                    ),
                  const Spacer(),
                  EmailAction(
                    icon: Icons.wifi_tethering_rounded,
                    tooltip: LocaleKeys.collections_email_test.tr(),
                    theme: theme,
                    label: LocaleKeys.collections_email_test.tr(),
                    onPressed: _busy ? null : _test,
                  ),
                  const SizedBox(width: EmailMetrics.space2),
                  EmailAction(
                    icon: Icons.check_rounded,
                    tooltip: LocaleKeys.collections_email_save.tr(),
                    theme: theme,
                    label: LocaleKeys.collections_email_save.tr(),
                    active: true,
                    size: 32,
                    onPressed: _busy ? null : _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _providerPicker(EmailTheme theme) => Wrap(
        spacing: EmailMetrics.space2,
        runSpacing: EmailMetrics.space2,
        children: [
          for (final provider in MailProvider.values)
            EmailChip(
              label: provider.label,
              theme: theme,
              tone: _account.provider == provider ? theme.accent : null,
              onTap: () => setState(() {
                _account = _account.withProvider(provider);
                _host.text = _account.host;
                _port.text = '${_account.port}';
                _mailboxes = const <ImapMailbox>[];
                _note = null;
                _error = null;
                _accounts = _accountsFor(provider);
                _connectionId = _accounts.length == 1 ? _accounts.first.id : '';
              }),
            ),
        ],
      );

  /// Which connected account this mailbox is read with.
  Widget _accountSection(EmailTheme theme) {
    final info = ProviderServices.of(_account.provider.oauthService!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.collections_email_signedInWith.tr(),
          style: theme.sectionLabel,
        ),
        const SizedBox(height: EmailMetrics.space2),
        if (_accounts.isEmpty)
          Text(
            LocaleKeys.collections_email_noAccount.tr(args: [info.label]),
            style: theme.meta.copyWith(height: 1.45),
          )
        else
          Wrap(
            spacing: EmailMetrics.space2,
            runSpacing: EmailMetrics.space2,
            children: [
              for (final account in _accounts)
                EmailChip(
                  label: account.accountLabel,
                  theme: theme,
                  tone: _connectionId == account.id ? theme.accent : null,
                  onTap: () => setState(() {
                    _connectionId = account.id;
                    _error = null;
                  }),
                ),
            ],
          ),
        const SizedBox(height: EmailMetrics.space2),
        Align(
          alignment: Alignment.centerLeft,
          child: EmailAction(
            icon: Icons.person_add_alt_rounded,
            tooltip: LocaleKeys.collections_email_connectAccount
                .tr(args: [info.label]),
            theme: theme,
            label: LocaleKeys.collections_email_connectAccount
                .tr(args: [info.label]),
            onPressed: _busy ? null : () => unawaited(_connectAccount(info)),
          ),
        ),
      ],
    );
  }

  /// A server that has no way in but a password.
  Widget _serverSection(EmailTheme theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_account.provider == MailProvider.custom) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _field(
                    theme,
                    label: LocaleKeys.collections_email_fieldHost.tr(),
                    controller: _host,
                  ),
                ),
                const SizedBox(width: EmailMetrics.space3),
                Expanded(
                  child: _field(
                    theme,
                    label: LocaleKeys.collections_email_fieldPort.tr(),
                    controller: _port,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: EmailMetrics.space3),
          ],
          _field(
            theme,
            label: LocaleKeys.collections_email_fieldUsername.tr(),
            controller: _username,
            hint: 'you@example.com',
          ),
          const SizedBox(height: EmailMetrics.space3),
          _field(
            theme,
            label: _account.provider.needsAppPassword
                ? LocaleKeys.collections_email_fieldAppPassword.tr()
                : LocaleKeys.collections_email_fieldPassword.tr(),
            controller: _secret,
            obscure: true,
          ),
          if (_account.provider.appPasswordUrl != null) ...[
            const SizedBox(height: EmailMetrics.space2),
            Align(
              alignment: Alignment.centerLeft,
              child: EmailAction(
                icon: Icons.open_in_new_rounded,
                tooltip: LocaleKeys.collections_email_appPasswordLink.tr(),
                theme: theme,
                label: LocaleKeys.collections_email_appPasswordLink.tr(),
                onPressed: () =>
                    afLaunchUrlString(_account.provider.appPasswordUrl!),
              ),
            ),
          ],
        ],
      );

  Future<void> _connectAccount(ProviderServiceInfo info) async {
    final connected = await showProviderConnectDialog(context, info: info);
    if (!mounted) {
      return;
    }
    final accounts = _accountsFor(_account.provider);
    setState(() {
      _accounts = accounts;
      _connectionId = connected?.id ?? _connectionId;
      _error = null;
    });
  }

  Widget _mailboxField(EmailTheme theme) {
    if (_mailboxes.isEmpty) {
      return _field(
        theme,
        label: LocaleKeys.collections_email_fieldMailbox.tr(),
        controller: _mailbox,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.collections_email_fieldMailbox.tr(),
          style: theme.sectionLabel,
        ),
        const SizedBox(height: EmailMetrics.space2),
        Wrap(
          spacing: EmailMetrics.space2,
          runSpacing: EmailMetrics.space2,
          children: [
            for (final mailbox in _mailboxes.take(24))
              EmailChip(
                label: mailbox.displayName,
                theme: theme,
                tone: _mailbox.text == mailbox.name ? theme.accent : null,
                onTap: () => setState(() => _mailbox.text = mailbox.name),
              ),
          ],
        ),
      ],
    );
  }

  Widget _rememberRow(EmailTheme theme) {
    final canRemember = widget.controller.canRememberSecret;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          canRemember && _account.rememberSecret
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          size: 18,
          color: canRemember ? theme.accent : theme.textFaint,
        ),
        const SizedBox(width: EmailMetrics.space2),
        Expanded(
          child: GestureDetector(
            onTap: canRemember
                ? () => setState(
                      () => _account = _account.copyWith(
                        rememberSecret: !_account.rememberSecret,
                      ),
                    )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.collections_email_remember.tr(),
                  style: theme.metaStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  canRemember
                      ? LocaleKeys.collections_email_rememberHint.tr()
                      : LocaleKeys.collections_email_rememberUnavailable.tr(),
                  style: theme.meta.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _banner(EmailTheme theme, String message, {required Color tone}) =>
      Container(
        padding: const EdgeInsets.all(EmailMetrics.space3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: theme.isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(EmailMetrics.controlRadius),
        ),
        child: Text(
          message,
          style: theme.meta.copyWith(color: tone, height: 1.45),
        ),
      );

  Widget _field(
    EmailTheme theme, {
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.sectionLabel),
          const SizedBox(height: EmailMetrics.space2 - 2),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(
              horizontal: EmailMetrics.space3,
            ),
            decoration: BoxDecoration(
              color: theme.sunken,
              borderRadius: BorderRadius.circular(EmailMetrics.controlRadius),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              style: theme.face(
                fontSize: EmailMetrics.metaSize + 1.5,
                color: theme.textStrong,
              ),
              cursorColor: theme.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                filled: false,
                hoverColor: Colors.transparent,
                hintText: hint,
                hintStyle: theme.meta,
              ),
            ),
          ),
        ],
      );

  MailAccount _readForm() {
    final account = _chosenAccount;
    if (_account.provider.signsInWithAccount && account != null) {
      return MailAccount.forConnection(
        connectionId: account.id,
        provider: _account.provider,
        username: account.accountLabel,
        mailbox: _mailbox.text.trim().isEmpty ? 'INBOX' : _mailbox.text.trim(),
      );
    }
    return _account.copyWith(
      host: _account.provider == MailProvider.custom
          ? _host.text.trim()
          : _account.provider.host,
      port: int.tryParse(_port.text.trim()) ?? _account.provider.port,
      username: _username.text.trim(),
      mailbox: _mailbox.text.trim().isEmpty ? 'INBOX' : _mailbox.text.trim(),
      clearError: true,
    );
  }

  /// The secret the form can sign in with right now, or null with a reason.
  Future<String?> _secretForForm(MailAccount account) async {
    if (!account.usesConnection) {
      return _secret.text.isEmpty ? null : _secret.text;
    }
    final token = await providerAccessToken(account.connectionId);
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(
          () => _error = LocaleKeys.collections_email_signInAgain.tr(),
        );
      }
      return null;
    }
    return token;
  }

  Future<void> _test() async {
    final account = _readForm();
    if (!account.isConfigured) {
      setState(() => _error = LocaleKeys.collections_email_needDetails.tr());
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });

    try {
      final secret = await _secretForForm(account);
      if (secret == null) {
        if (mounted) {
          setState(
            () => _error ??= LocaleKeys.collections_email_needDetails.tr(),
          );
        }
        return;
      }
      final mailboxes = await const MailSyncService().listMailboxes(
        account: account,
        secret: secret,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _account = account;
        _mailboxes = mailboxes;
        _note = LocaleKeys.collections_email_testOk
            .tr(args: ['${mailboxes.length}']);
      });
    } on ImapException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() async {
    final account = _readForm();
    if (!account.isConfigured) {
      setState(() => _error = LocaleKeys.collections_email_needDetails.tr());
      return;
    }
    if (_account.provider.signsInWithAccount && !account.usesConnection) {
      setState(() => _error = LocaleKeys.collections_email_needAccount.tr());
      return;
    }

    await widget.controller.connectAccount(account, secret: _secret.text);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    showToastNotification(
      message: LocaleKeys.collections_email_connected.tr(),
    );
  }

  Future<void> _disconnect() async {
    await widget.controller.disconnectAccount();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    showToastNotification(
      message: LocaleKeys.collections_email_disconnected.tr(),
    );
  }
}

/// Runs a sync and says what came of it, asking for the password again when
/// this machine does not keep one.
Future<void> syncMailWithFeedback(
  BuildContext context, {
  required EmailController controller,
}) async {
  if (!controller.isConnected) {
    await showMailAccountDialog(context, controller: controller);
    return;
  }

  if (!await controller.hasSecret()) {
    if (!context.mounted) {
      return;
    }
    await showMailAccountDialog(context, controller: controller);
    return;
  }

  final result = await controller.syncNow();
  if (!context.mounted) {
    return;
  }
  // Nothing came back and nothing is running: the mailbox has no way in right
  // now — a password this machine did not keep, or a sign in the service has
  // since withdrawn. Either way the panel is where it gets sorted out.
  if (result == null) {
    if (!controller.isSyncing) {
      await showMailAccountDialog(context, controller: controller);
    }
    return;
  }

  showToastNotification(
    message: result.succeeded
        ? LocaleKeys.collections_email_synced.tr(args: ['${result.fetched}'])
        : result.error ?? LocaleKeys.collections_email_syncFailed.tr(),
    type: result.succeeded
        ? ToastificationType.success
        : ToastificationType.error,
  );
}
