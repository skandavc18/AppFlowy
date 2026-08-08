import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_accounts_view.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Every external service the application is signed in to.
///
/// One page, because a connection belongs to the person rather than to a
/// collection: signing in here is what makes every album, repository, folder
/// and page embed able to reach that service without asking again.
class SettingsConnectionsView extends StatefulWidget {
  const SettingsConnectionsView({super.key});

  @override
  State<SettingsConnectionsView> createState() =>
      _SettingsConnectionsViewState();
}

class _SettingsConnectionsViewState extends State<SettingsConnectionsView> {
  final ProviderConnections connections = ProviderConnections.instance;

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
    if (mounted) {
      setState(() {
        cacheBytes = size;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final connected = connections.all;
    final available = [
      for (final info in ProviderServices.connectable)
        if (!connected.any((account) => account.service == info.service)) info,
    ];

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
          if (connected.isEmpty)
            _Empty(palette: palette)
          else
            SettingsCategory(
              title: LocaleKeys.providers_connected.tr(),
              children: [
                for (final account in connected)
                  _ConnectedRow(
                    key: ValueKey(account.id),
                    account: account,
                    palette: palette,
                    onDisconnect: () => unawaited(_disconnect(account)),
                    onReconnect: () => unawaited(
                      _connect(ProviderServices.of(account.service)),
                    ),
                  ),
              ],
            ),
          if (available.isNotEmpty)
            SettingsCategory(
              title: LocaleKeys.providers_settings_available.tr(),
              children: [
                for (final info in available)
                  _AvailableRow(
                    key: ValueKey(info.service),
                    info: info,
                    palette: palette,
                    onConnect: () => unawaited(_connect(info)),
                  ),
              ],
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
          const MailAccountsSection(),
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

  Future<void> _connect(ProviderServiceInfo info) async {
    await showProviderConnectDialog(context, info: info);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _disconnect(ProviderConnection account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          LocaleKeys.providers_settings_confirmDisconnectTitle
              .tr(args: [account.info.label]),
        ),
        content: Text(
          LocaleKeys.providers_settings_confirmDisconnectBody.tr(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(LocaleKeys.providers_disconnect.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await connections.remove(account.id);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _clearCache() async {
    await ProviderCache.instance.clearAll();
    final size = await ProviderCache.instance.sizeInBytes();
    if (mounted) {
      setState(() => cacheBytes = size);
    }
  }
}

class _ConnectedRow extends StatelessWidget {
  const _ConnectedRow({
    super.key,
    required this.account,
    required this.palette,
    required this.onDisconnect,
    required this.onReconnect,
  });

  final ProviderConnection account;
  final FolderExplorerPalette palette;
  final VoidCallback onDisconnect;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final info = account.info;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: info.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(info.icon, size: 17, color: info.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  info.label,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontVariations: const [FontVariation.weight(580)],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    account.accountLabel,
                    if (account.host.isNotEmpty)
                      Uri.tryParse(account.host)?.host ?? account.host,
                    LocaleKeys.providers_settings_connectedSince.tr(
                      args: [providerRelativeTime(account.connectedAt)],
                    ),
                  ].where((part) => part.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onReconnect,
            child: Text(
              LocaleKeys.providers_reconnect.tr(),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: onDisconnect,
            child: Text(
              LocaleKeys.providers_disconnect.tr(),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableRow extends StatelessWidget {
  const _AvailableRow({
    super.key,
    required this.info,
    required this.palette,
    required this.onConnect,
  });

  final ProviderServiceInfo info;
  final FolderExplorerPalette palette;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: info.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                info.icon,
                size: 17,
                color: info.accent.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    info.label,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _describe(info),
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onConnect,
              child: Text(
                LocaleKeys.providers_connect.tr(),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );

  String _describe(ProviderServiceInfo info) {
    final kinds = info.kinds
        .map(
          (kind) => switch (kind.name) {
            'album' => LocaleKeys.providers_noun_album.tr(),
            'repository' => LocaleKeys.providers_noun_repository.tr(),
            _ => LocaleKeys.providers_noun_folder.tr(),
          },
        )
        .toSet()
        .join(', ');
    return '$kinds · ${switch (info.authKind) {
      ProviderAuthKind.selfHostedToken =>
        LocaleKeys.providers_connectSelfHosted.tr(),
      ProviderAuthKind.personalToken => LocaleKeys.providers_connectToken.tr(),
      _ => LocaleKeys.providers_connectBrowser.tr(),
    }}';
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
