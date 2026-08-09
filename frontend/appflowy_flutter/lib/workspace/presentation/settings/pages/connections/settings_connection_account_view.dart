import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/presentation/settings/pages/connections/connections_chrome.dart';
import 'package:appflowy/workspace/presentation/settings/pages/google_calendar_section.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category_spacer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One account, and everything it is used for.
///
/// The list page answers "whose accounts are connected"; this answers "what is
/// this one allowed to do", one capability at a time. They are separate pages
/// because a Google account can stand behind four unrelated features and a
/// single row cannot say anything useful about all four at once.
class SettingsConnectionAccountView extends StatefulWidget {
  const SettingsConnectionAccountView({
    super.key,
    required this.group,
    required this.onBack,
  });

  final ProviderAccountGroup group;
  final VoidCallback onBack;

  @override
  State<SettingsConnectionAccountView> createState() =>
      _SettingsConnectionAccountViewState();
}

class _SettingsConnectionAccountViewState
    extends State<SettingsConnectionAccountView> {
  final ProviderConnections connections = ProviderConnections.instance;

  ProviderService? busy;

  ProviderAccountGroup get group => widget.group;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final family = group.family;
    final services = ProviderServices.forFamily(family);
    final calendarIds = <String>{
      for (final connection in group.connections)
        if (connection.covers(ProviderService.googleCalendar)) connection.id,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _BackRow(palette: palette, onTap: widget.onBack),
          const SizedBox(height: 14),
          _AccountHeader(group: group, palette: palette),
          const SettingsCategorySpacer(),
          SettingsCategory(
            title: LocaleKeys.providers_settings_usedForTitle.tr(),
            description: LocaleKeys.providers_settings_usedForBody.tr(),
            children: [
              for (final info in services)
                _CapabilityCard(
                  key: ValueKey(info.service),
                  info: info,
                  group: group,
                  palette: palette,
                  busy: busy == info.service,
                  onChanged: (value) => unawaited(_setUsed(info, value)),
                ),
            ],
          ),
          if (calendarIds.isNotEmpty) ...[
            const SettingsCategorySpacer(),
            GoogleCalendarSection(connectionIds: calendarIds),
          ],
          const SettingsCategorySpacer(),
          SettingsCategory(
            title: LocaleKeys.providers_settings_accountTitle.tr(),
            children: [
              ConnectionCard(
                palette: palette,
                leading: ConnectionGlyph(
                  icon: Icons.refresh_rounded,
                  accent: palette.accent,
                  muted: true,
                ),
                title: LocaleKeys.providers_reconnect.tr(),
                subtitle: LocaleKeys.providers_settings_signInAgainBody.tr(),
                trailing: ConnectionTextButton(
                  label: LocaleKeys.providers_signIn.tr(),
                  onPressed: () => unawaited(_reconnect()),
                ),
              ),
              ConnectionCard(
                palette: palette,
                leading: ConnectionGlyph(
                  icon: Icons.link_off_rounded,
                  accent: palette.danger,
                  muted: true,
                ),
                title: LocaleKeys.providers_settings_removeAccount.tr(),
                subtitle: LocaleKeys.providers_settings_removeAccountBody.tr(),
                trailing: ConnectionTextButton(
                  label: LocaleKeys.providers_disconnect.tr(),
                  tone: palette.danger,
                  onPressed: () => unawaited(_remove()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Turns one capability on or off for this account alone.
  Future<void> _setUsed(ProviderServiceInfo info, bool used) async {
    setState(() => busy = info.service);
    try {
      if (used) {
        await _turnOn(info);
      } else {
        await _turnOff(info);
      }
    } finally {
      if (mounted) {
        setState(() => busy = null);
      }
    }
  }

  Future<void> _turnOn(ProviderServiceInfo info) async {
    final primary = group.primary;
    // A permission this account already holds needs no browser trip — it was
    // granted when the account signed in, and only AppFlowy had stopped
    // reaching for it.
    final granted = primary.family.sharesOneGrant &&
        OAuthServices.servicesGrantedBy(primary.service, primary.scopes)
            .contains(info.service);
    if (granted) {
      await connections.setServices(
        primary.id,
        {...primary.covered, info.service},
      );
      return;
    }
    await showProviderConnectDialog(
      context,
      info: info,
      preferAccountId: group.accountId,
    );
  }

  Future<void> _turnOff(ProviderServiceInfo info) async {
    final connection = group.connectionFor(info.service);
    if (connection == null) {
      return;
    }
    final remaining = {...connection.covered}..remove(info.service);
    if (remaining.isEmpty) {
      // Nothing left for this sign in to do, so it is the account that is
      // going. Say so rather than silently deleting it.
      final confirmed = await _confirm(
        title: LocaleKeys.providers_settings_confirmDisconnectTitle
            .tr(args: [group.label]),
        body: LocaleKeys.providers_settings_turnOffLastBody.tr(),
        action: LocaleKeys.providers_disconnect.tr(),
      );
      if (!confirmed) {
        return;
      }
      await connections.remove(connection.id);
      if (mounted && group.connections.length <= 1) {
        widget.onBack();
      }
      return;
    }
    await connections.setServices(connection.id, remaining);
  }

  Future<void> _reconnect() async {
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
        preferAccountId: group.accountId,
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _remove() async {
    final confirmed = await _confirm(
      title: LocaleKeys.providers_settings_confirmDisconnectTitle
          .tr(args: [group.label]),
      body: LocaleKeys.providers_settings_confirmDisconnectBody.tr(),
      action: LocaleKeys.providers_disconnect.tr(),
    );
    if (!confirmed) {
      return;
    }
    for (final connection in group.connections) {
      await connections.remove(connection.id);
    }
    if (mounted) {
      widget.onBack();
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer ?? false;
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.palette, required this.onTap});

  final FolderExplorerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          label: Text(
            LocaleKeys.providers_connections.tr(),
            style: const TextStyle(fontSize: 12.5),
          ),
          style: TextButton.styleFrom(
            foregroundColor: palette.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.group, required this.palette});

  final ProviderAccountGroup group;
  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) {
    final family = group.family;
    final details = [
      family.label,
      if (group.host.isNotEmpty) Uri.tryParse(group.host)?.host ?? group.host,
      LocaleKeys.providers_settings_connectedSince
          .tr(args: [providerRelativeTime(group.connectedAt)]),
    ].where((part) => part.isNotEmpty).join(' · ');

    return Row(
      children: [
        ConnectionGlyph(
          icon: family.icon,
          accent: family.accent,
          size: 46,
        ),
        const SizedBox(width: 14),
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
                  fontSize: 19,
                  fontVariations: const [FontVariation.weight(650)],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One thing this account can be used for, with the switch that decides.
class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    super.key,
    required this.info,
    required this.group,
    required this.palette,
    required this.busy,
    required this.onChanged,
  });

  final ProviderServiceInfo info;
  final ProviderAccountGroup group;
  final FolderExplorerPalette palette;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final used = group.covers(info.service);
    final connection = group.connectionFor(info.service) ?? group.primary;
    final granted = group.family.sharesOneGrant &&
        OAuthServices.servicesGrantedBy(
          group.primary.service,
          group.primary.scopes,
        ).contains(info.service);

    final notes = <String>[
      providerServicePurpose(info.service),
      if (!used && info.needsBrowser && !granted)
        LocaleKeys.providers_settings_needsBrowser.tr()
      else if (!used && granted)
        LocaleKeys.providers_settings_alreadyGranted.tr(),
    ].where((note) => note.isNotEmpty).join(' · ');

    final writeScopes = OAuthServices.writeScopesFor(info.service);

    return ConnectionCard(
      palette: palette,
      leading: ConnectionGlyph(
        icon: info.icon,
        accent: info.accent,
        muted: !used,
      ),
      title: info.label,
      subtitle: notes,
      trailing: busy
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Switch(value: used, onChanged: onChanged),
      footer: used && writeScopes != null
          ? _PermissionNote(
              palette: palette,
              writes:
                  OAuthServices.grantsWrite(info.service, connection.scopes),
            )
          : null,
    );
  }
}

/// Says whether this capability may change anything, because "connected" and
/// "allowed to write" are different questions and only one of them is obvious.
class _PermissionNote extends StatelessWidget {
  const _PermissionNote({required this.palette, required this.writes});

  final FolderExplorerPalette palette;
  final bool writes;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 48),
        child: Row(
          children: [
            Icon(
              writes ? Icons.edit_rounded : Icons.lock_outline_rounded,
              size: 12,
              color: palette.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                writes
                    ? LocaleKeys.providers_settings_writeAllowed.tr()
                    : LocaleKeys.providers_settings_readOnly.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
      );
}
