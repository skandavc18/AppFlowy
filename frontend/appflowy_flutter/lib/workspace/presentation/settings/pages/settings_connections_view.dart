import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/workspace/application/collections/email/connected_accounts.dart';
import 'package:appflowy/workspace/application/collections/email/mail_secret_store.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/settings/pages/connections/connections_chrome.dart';
import 'package:appflowy/workspace/presentation/settings/pages/connections/settings_connection_account_view.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_mailboxes_view.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Every external service the application is signed in to.
///
/// A list of ACCOUNTS, not of features: one person can hold two Google
/// accounts and use each for different things, so every company section lists
/// however many accounts there are plus one button to add another. What an
/// account is used for is settled on its own page — a single row cannot say
/// anything useful about four unrelated capabilities at once.
class SettingsConnectionsView extends StatefulWidget {
  const SettingsConnectionsView({super.key});

  @override
  State<SettingsConnectionsView> createState() =>
      _SettingsConnectionsViewState();
}

class _SettingsConnectionsViewState extends State<SettingsConnectionsView> {
  final ProviderConnections connections = ProviderConnections.instance;
  final ConnectedAccountRegistry registry = const ConnectedAccountRegistry();
  final MailSecretStore mailSecrets = MailSecretStore();

  /// The account whose page is open, held as its key rather than as the group
  /// itself so it survives the list being rebuilt underneath it.
  String? openAccount;

  /// Mailboxes signed in with a password of their own. One read through a
  /// connected account has nothing to manage here — it is that account's row.
  List<ConnectedAccount> mailboxes = const <ConnectedAccount>[];
  Set<String> mailboxesReady = const <String>{};

  int cacheBytes = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    connections.addListener(_onChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    connections.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    await connections.ensureLoaded();
    final size = await ProviderCache.instance.sizeInBytes();
    await _loadMailboxes();
    if (mounted) {
      setState(() {
        cacheBytes = size;
        loading = false;
      });
    }
  }

  Future<void> _loadMailboxes() async {
    final own = [
      for (final mailbox in await registry.all())
        if (mailbox.connectionId.isEmpty) mailbox,
    ];
    final ready = <String>{};
    for (final mailbox in own) {
      if (await mailSecrets.has(mailbox.id)) {
        ready.add(mailbox.id);
      }
    }
    if (mounted) {
      setState(() {
        mailboxes = own;
        mailboxesReady = ready;
      });
    }
  }

  Widget _mailboxTile(ConnectedAccount mailbox) => MailboxTile(
        key: ValueKey(mailbox.id),
        mailbox: mailbox,
        isReady: mailboxesReady.contains(mailbox.id),
        secrets: mailSecrets,
        onChanged: _loadMailboxes,
        onRemove: () async {
          await mailSecrets.forget(mailbox.id);
          await registry.remove(mailbox.id);
          await _loadMailboxes();
        },
      );

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final accounts = groupProviderAccounts(connections.all);

    for (final group in accounts) {
      if (group.key == openAccount) {
        return SettingsConnectionAccountView(
          key: ValueKey(group.key),
          group: group,
          onBack: () => setState(() => openAccount = null),
        );
      }
    }

    return SettingsBody(
      title: LocaleKeys.providers_connections.tr(),
      description: LocaleKeys.providers_connectionsDescription.tr(),
      children: [
        if (loading)
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
        else ...[
          if (accounts.isEmpty) _Empty(palette: palette),
          // One heading per company, so the page reads as a list of accounts
          // rather than a list of features.
          for (final family in ProviderServices.families())
            SettingsCategory(
              title: family.label,
              description: [
                for (final info in ProviderServices.forFamily(family))
                  info.label,
              ].join(' · '),
              children: _familyChildren(family, accounts, palette),
            ),
          SettingsCategory(
            title: LocaleKeys.providers_settings_cacheTitle.tr(),
            children: [
              _CacheRow(
                palette: palette,
                bytes: cacheBytes,
                onClear: () => unawaited(_clearCache()),
              ),
            ],
          ),
          if (_ownMailboxes.isNotEmpty)
            SettingsCategory(
              title: LocaleKeys.providers_settings_otherMailboxes.tr(),
              description:
                  LocaleKeys.providers_settings_otherMailboxesBody.tr(),
              children: [
                for (final mailbox in _ownMailboxes) _mailboxTile(mailbox),
              ],
            ),
          if (!connections.canPersistSecrets)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                LocaleKeys.providers_secretSessionOnly.tr(),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// Mailboxes that belong to no account family, so they are listed on their
  /// own rather than under a company that has nothing to do with them.
  List<ConnectedAccount> get _ownMailboxes => [
        for (final mailbox in mailboxes)
          if (mailboxAccountFamily(mailbox) == null) mailbox,
      ];

  List<Widget> _familyChildren(
    ProviderAccountFamily family,
    List<ProviderAccountGroup> accounts,
    FolderExplorerPalette palette,
  ) {
    final mine = [
      for (final group in accounts)
        if (group.family == family) group,
    ];
    // An app password is a second way into the same account, so it belongs
    // beside the browser sign in rather than in a list of its own.
    final ownMailboxes = [
      for (final mailbox in mailboxes)
        if (mailboxAccountFamily(mailbox) == family) mailbox,
    ];

    return [
      for (final group in mine)
        _AccountCard(
          key: ValueKey(group.key),
          group: group,
          palette: palette,
          onOpen: () => setState(() => openAccount = group.key),
        ),
      for (final mailbox in ownMailboxes) _mailboxTile(mailbox),
      ConnectionAddButton(
        palette: palette,
        accent: family.accent,
        label: mine.isEmpty
            ? LocaleKeys.providers_settings_connectAccount
                .tr(args: [family.label])
            : LocaleKeys.providers_settings_anotherAccount
                .tr(args: [family.label]),
        onPressed: () => unawaited(_addAccount(family)),
      ),
    ];
  }

  /// Signs a NEW account in, then opens its page so the next question — what
  /// it should be used for — is answered where it belongs.
  Future<void> _addAccount(ProviderAccountFamily family) async {
    final services = ProviderServices.forFamily(family);
    if (services.isEmpty) {
      return;
    }
    final connection = await showProviderConnectDialog(
      context,
      info: services.first,
      // Empty rather than null: this is a new account and must not inherit the
      // permissions another one happens to hold.
      preferAccountId: '',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      if (connection != null) {
        openAccount = providerAccountKeyFor(connection);
      }
    });
  }

  Future<void> _clearCache() async {
    await ProviderCache.instance.clearAll();
    final size = await ProviderCache.instance.sizeInBytes();
    if (mounted) {
      setState(() => cacheBytes = size);
    }
  }
}

/// One account, summarised. Everything it can be told to do lives on its page.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    super.key,
    required this.group,
    required this.palette,
    required this.onOpen,
  });

  final ProviderAccountGroup group;
  final FolderExplorerPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final carries = [
      for (final service in group.services) ProviderServices.of(service).label,
    ].join(' · ');

    final subtitle = [
      if (carries.isEmpty)
        LocaleKeys.providers_settings_usedForNothing.tr()
      else
        carries,
      if (group.host.isNotEmpty) Uri.tryParse(group.host)?.host ?? group.host,
      LocaleKeys.providers_settings_connectedSince
          .tr(args: [providerRelativeTime(group.connectedAt)]),
    ].where((part) => part.isNotEmpty).join(' · ');

    return ConnectionCard(
      palette: palette,
      onTap: onOpen,
      leading: ConnectionGlyph(
        icon: group.family.icon,
        accent: group.family.accent,
      ),
      title: group.label,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConnectionTextButton(
            label: LocaleKeys.providers_settings_manage.tr(),
            onPressed: onOpen,
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: palette.textMuted,
          ),
        ],
      ),
    );
  }
}

class _CacheRow extends StatelessWidget {
  const _CacheRow({
    required this.palette,
    required this.bytes,
    required this.onClear,
  });

  final FolderExplorerPalette palette;
  final int bytes;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    LocaleKeys.providers_settings_cacheBody.tr(),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    LocaleKeys.providers_settings_cacheSize
                        .tr(args: [_format(bytes)]),
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onClear,
              child: Text(
                LocaleKeys.providers_settings_clearCache.tr(),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

  static String _format(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.palette});

  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.providers_settings_noConnections.tr(),
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13.5,
                fontVariations: const [FontVariation.weight(580)],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              LocaleKeys.providers_settings_noConnectionsBody.tr(),
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}
