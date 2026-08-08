import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/settings/pages/google_calendar_section.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_mailboxes_view.dart';
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
    final accounts = groupProviderAccounts(connections.all);

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
          const GoogleCalendarSection(),
          const MailboxesSection(),
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

  List<Widget> _familyChildren(
    ProviderAccountFamily family,
    List<ProviderAccountGroup> accounts,
    FolderExplorerPalette palette,
  ) {
    final mine = [
      for (final group in accounts)
        if (group.family == family) group,
    ];
    final services = ProviderServices.forFamily(family);
    // One sign in covers everything the account can do, so there is one thing
    // to press. Microsoft is the exception: its token endpoint will not carry
    // OneDrive and Outlook mail together, so those stay separate.
    final oneGrant = family.sharesOneGrant;

    return [
      for (final group in mine)
        _AccountRow(
          key: ValueKey(group.primary.id),
          group: group,
          palette: palette,
          onAdd: (info) => unawaited(_connect(info)),
          onReconnect: () => unawaited(_reconnect(group)),
          onDisconnect: () => unawaited(_disconnect(group)),
        ),
      if (mine.isEmpty)
        if (oneGrant)
          _AccountConnectRow(
            key: ValueKey(family),
            family: family,
            services: services,
            palette: palette,
            onConnect: () => unawaited(_connect(services.first)),
          )
        else
          for (final info in services)
            _ServiceRow(
              key: ValueKey(info.service),
              info: info,
              palette: palette,
              onConnect: () => unawaited(_connect(info)),
            )
      else
        _AnotherAccountRow(
          family: family,
          services: oneGrant ? services.take(1).toList() : services,
          palette: palette,
          onConnect: (info) => unawaited(_connect(info)),
        ),
    ];
  }

  Future<void> _connect(ProviderServiceInfo info) async {
    await showProviderConnectDialog(context, info: info);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reconnect(ProviderAccountGroup group) async {
    // One sign in renews everything the account carries; only a family that
    // cannot grant them together needs one trip per capability.
    final services = group.family.sharesOneGrant
        ? <ProviderService>{group.primary.service}
        : group.services;
    for (final service in services) {
      if (!mounted) {
        return;
      }
      await showProviderConnectDialog(
        context,
        info: ProviderServices.of(service),
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _disconnect(ProviderAccountGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          LocaleKeys.providers_settings_confirmDisconnectTitle
              .tr(args: [group.label]),
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
    for (final connection in group.connections) {
      await connections.remove(connection.id);
    }
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

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.group,
    required this.palette,
    required this.onAdd,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final ProviderAccountGroup group;
  final FolderExplorerPalette palette;
  final ValueChanged<ProviderServiceInfo> onAdd;
  final VoidCallback onReconnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final family = group.family;
    final carries = [
      for (final service in group.services) ProviderServices.of(service).label,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: family.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(family.icon, size: 17, color: family.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.5,
                        fontVariations: const [FontVariation.weight(580)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        carries,
                        if (group.host.isNotEmpty)
                          Uri.tryParse(group.host)?.host ?? group.host,
                        LocaleKeys.providers_settings_connectedSince.tr(
                          args: [providerRelativeTime(group.connectedAt)],
                        ),
                      ].where((part) => part.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: palette.textMuted, fontSize: 11.5),
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
          if (group.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 46, top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    LocaleKeys.providers_settings_alsoUseFor.tr(),
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                  for (final info in group.missing)
                    _ServiceChip(
                      info: info,
                      palette: palette,
                      onTap: () => onAdd(info),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One press signs the whole account in, when the account allows it.
class _AccountConnectRow extends StatelessWidget {
  const _AccountConnectRow({
    super.key,
    required this.family,
    required this.services,
    required this.palette,
    required this.onConnect,
  });

  final ProviderAccountFamily family;
  final List<ProviderServiceInfo> services;
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
                color: family.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                family.icon,
                size: 17,
                color: family.accent.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    LocaleKeys.providers_settings_signInOnce
                        .tr(args: [family.label]),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [for (final info in services) info.label].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
}

/// The way to sign a second account of the same family in.
class _AnotherAccountRow extends StatelessWidget {
  const _AnotherAccountRow({
    required this.family,
    required this.services,
    required this.palette,
    required this.onConnect,
  });

  final ProviderAccountFamily family;
  final List<ProviderServiceInfo> services;
  final FolderExplorerPalette palette;
  final ValueChanged<ProviderServiceInfo> onConnect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 46, top: 2, bottom: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              LocaleKeys.providers_settings_anotherAccount
                  .tr(args: [family.label]),
              style: TextStyle(color: palette.textMuted, fontSize: 11.5),
            ),
            for (final info in services)
              _ServiceChip(
                info: info,
                palette: palette,
                onTap: () => onConnect(info),
              ),
          ],
        ),
      );
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({
    required this.info,
    required this.palette,
    required this.onTap,
  });

  final ProviderServiceInfo info;
  final FolderExplorerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: info.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(info.icon, size: 12, color: info.accent),
                const SizedBox(width: 5),
                Text(
                  info.label,
                  style: TextStyle(
                    color: info.accent,
                    fontSize: 11.5,
                    fontVariations: const [FontVariation.weight(560)],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
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
    final how = switch (info.authKind) {
      ProviderAuthKind.selfHostedToken =>
        LocaleKeys.providers_connectSelfHosted.tr(),
      ProviderAuthKind.personalToken => LocaleKeys.providers_connectToken.tr(),
      _ => LocaleKeys.providers_connectBrowser.tr(),
    };
    // Calendar and mail stand behind no collection type at all, so there is
    // nothing to name but how they sign in.
    return kinds.isEmpty ? how : '$kinds · $how';
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
