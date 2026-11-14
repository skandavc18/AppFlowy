// Working on an AppFlowy server — AppFlowy Cloud itself or one of your own —
// instead of keeping the workspace on this computer: choosing one, and the
// card in Settings ▸ Sync that says which one this is.

import 'dart:async';
import 'dart:io';

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/workspace/application/sync/self_hosted_cloud.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/account_sign_in_out.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/sync_dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Where a server's error text is drawn, as everywhere else in Settings.
const Color _errorColor = Color(0xFFD9534F);

/// A server to work on, and where its shared and published pages open.
@immutable
class AppFlowyServerChoice {
  const AppFlowyServerChoice({required this.url, required this.webUrl});

  /// AppFlowy's own service.
  static const AppFlowyServerChoice appflowyCloud = AppFlowyServerChoice(
    url: kAppflowyCloudUrl,
    webUrl: ShareConstants.defaultBaseWebDomain,
  );

  final String url;
  final String webUrl;

  bool get isAppFlowyCloud => url == kAppflowyCloudUrl;
}

/// Asks which AppFlowy server to work on: AppFlowy Cloud, or one at an
/// address. Null when cancelled.
Future<AppFlowyServerChoice?> chooseAppFlowyServer(
  BuildContext context, {
  AppFlowyServerChoice? current,
  String? signsOutOf,
  bool pagesStay = false,
}) =>
    showDialog<AppFlowyServerChoice>(
      context: context,
      builder: (_) => AppFlowyServerDialog(
        current: current,
        signsOutOf: signsOutOf,
        pagesStay: pagesStay,
      ),
    );

class AppFlowyServerDialog extends StatefulWidget {
  const AppFlowyServerDialog({
    super.key,
    this.current,
    this.signsOutOf,
    this.pagesStay = false,
    this.check,
  });

  /// The server worked on now, to start from.
  final AppFlowyServerChoice? current;

  /// The server signed in to now, which continuing signs out of.
  final String? signsOutOf;

  /// Whether to say that the pages on this computer stay here.
  final bool pagesStay;

  /// What tells an AppFlowy server from anything else at an address.
  final Future<SelfHostedCloudCheck> Function(String server)? check;

  @override
  State<AppFlowyServerDialog> createState() => _AppFlowyServerDialogState();
}

class _AppFlowyServerDialogState extends State<AppFlowyServerDialog> {
  /// The server worked on now, when it is one of your own.
  late final AppFlowyServerChoice? _own =
      widget.current?.isAppFlowyCloud == false ? widget.current : null;
  late bool _ownServer = _own != null;
  late final TextEditingController _address =
      TextEditingController(text: _own?.url ?? '');
  late final TextEditingController _web = TextEditingController(
    text: _own != null && _own.webUrl != _own.url ? _own.webUrl : '',
  );
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _web.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) {
      return;
    }
    if (!_ownServer) {
      Navigator.of(context).pop(AppFlowyServerChoice.appflowyCloud);
      return;
    }
    final url = SelfHostedCloud.normalizeServer(_address.text);
    final web = _web.text.trim().isEmpty
        ? url
        : SelfHostedCloud.normalizeServer(_web.text);
    if (url == null || web == null) {
      setState(() => _error = LocaleKeys.firstRun_serverInvalid.tr());
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final check = widget.check ?? SelfHostedCloud.instance.check;
    final answer = await check(url);
    if (!mounted) {
      return;
    }
    final problem = switch (answer) {
      SelfHostedCloudCheck.ready || SelfHostedCloudCheck.noSyncFolders => null,
      SelfHostedCloudCheck.notAppFlowyCloud =>
        LocaleKeys.appflowyServer_notAppFlowyServer.tr(),
      SelfHostedCloudCheck.unreachable =>
        LocaleKeys.appflowyServer_unreachable.tr(),
    };
    if (problem != null) {
      setState(() {
        _working = false;
        _error = problem;
      });
      return;
    }
    Navigator.of(context).pop(AppFlowyServerChoice(url: url, webUrl: web));
  }

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final palette = FolderExplorerPalette.of(context);
    final note = TextStyle(
      fontSize: 12,
      height: 1.4,
      color: premium.textSecondary,
    );
    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.appflowyServer_dialogTitle.tr(),
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
                LocaleKeys.appflowyServer_dialogBody.tr(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: premium.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              _ChoiceRow(
                key: const ValueKey('appflowy-server-cloud'),
                icon: Icons.cloud_rounded,
                title: LocaleKeys.appflowyServer_cloudTitle.tr(),
                body: LocaleKeys.appflowyServer_cloudBody.tr(),
                selected: !_ownServer,
                onTap: () => setState(() {
                  _ownServer = false;
                  _error = null;
                }),
              ),
              const SizedBox(height: 6),
              _ChoiceRow(
                key: const ValueKey('appflowy-server-own'),
                icon: Icons.dns_rounded,
                title: LocaleKeys.appflowyServer_ownTitle.tr(),
                body: LocaleKeys.appflowyServer_ownBody.tr(),
                selected: _ownServer,
                onTap: () => setState(() {
                  _ownServer = true;
                  _error = null;
                }),
              ),
              if (_ownServer) ...[
                const SizedBox(height: 14),
                ProviderTextField(
                  key: const ValueKey('appflowy-server-address'),
                  label: LocaleKeys.firstRun_serverAddress.tr(),
                  hint: 'https://appflowy.example.com',
                  controller: _address,
                  palette: palette,
                  autofocus: true,
                  onSubmitted: (_) => unawaited(_submit()),
                ),
                const SizedBox(height: 12),
                ProviderTextField(
                  key: const ValueKey('appflowy-server-web'),
                  label: LocaleKeys.appflowyServer_webAddress.tr(),
                  hint: 'https://appflowy.example.com',
                  controller: _web,
                  palette: palette,
                  onSubmitted: (_) => unawaited(_submit()),
                ),
                const SizedBox(height: 6),
                Text(
                  LocaleKeys.appflowyServer_webAddressHint.tr(),
                  style: note,
                ),
              ],
              if (widget.signsOutOf != null) ...[
                const SizedBox(height: 12),
                Text(
                  LocaleKeys.appflowyServer_signsOut
                      .tr(args: [widget.signsOutOf!]),
                  style: note,
                ),
              ],
              if (widget.pagesStay) ...[
                const SizedBox(height: 12),
                Text(LocaleKeys.appflowyServer_pagesStay.tr(), style: note),
              ],
              if (_working) ...[
                const SizedBox(height: 12),
                Text(LocaleKeys.appflowyServer_checking.tr(), style: note),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
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
          child: Text(LocaleKeys.firstRun_serverContinue.tr()),
        ),
      ],
    );
  }
}

/// One of the choices in a dialog: a glyph, a name, a line about it.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final ink = LegibleColor.onWash(
      premium.floatingSurface,
      premium.accent,
      wash: 0.12,
      minimum: LegibleColor.glyph,
    );
    return Material(
      color: selected ? premium.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: premium.hover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: premium.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: premium.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_rounded, size: 17, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings ▸ Sync's card for the AppFlowy server this workspace is worked
/// on: connect to one, sign in to it, change it, or leave it.
class AppFlowyServerPanel extends StatelessWidget {
  const AppFlowyServerPanel({
    super.key,
    required this.userProfile,
    required this.restart,
  });

  final UserProfilePB userProfile;

  /// Starts AppFlowy again, on the server just chosen.
  final VoidCallback restart;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    final signedIn = userProfile.userAuthType == AuthTypePB.Server;
    final chosen = isServerChosen;
    final server = chosen || signedIn
        ? getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url
        : '';
    final host = server.isEmpty ? '' : serverHost(server);
    final connected = host.isNotEmpty;

    final title = connected
        ? '${LocaleKeys.appflowyServer_title.tr()} · $host'
        : LocaleKeys.appflowyServer_title.tr();
    final subtitle = signedIn
        ? LocaleKeys.appflowyServer_signedInAs.tr(args: [userProfile.email])
        : connected
            ? LocaleKeys.appflowyServer_notSignedIn.tr()
            : LocaleKeys.appflowyServer_panelBody.tr();

    return Column(
      key: const ValueKey('appflowy-server-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: premium.hover,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: premium.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.groups_rounded,
                  size: 18,
                  color: LegibleColor.onWash(
                    premium.hover,
                    premium.accent,
                    wash: 0.12,
                    minimum: LegibleColor.glyph,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: premium.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: premium.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!signedIn) ...[
                const SizedBox(width: 12),
                TextButton(
                  key: const ValueKey('appflowy-server-action'),
                  onPressed: () => connected
                      ? unawaited(showAccountSignInDialog(context))
                      : unawaited(
                          _choose(context, server: '', signedIn: false),
                        ),
                  style: TextButton.styleFrom(
                    foregroundColor: premium.accent,
                    backgroundColor: premium.accent.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    connected
                        ? LocaleKeys.appflowyServer_signIn.tr()
                        : LocaleKeys.appflowyServer_connect.tr(),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (connected) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => unawaited(
                  _choose(context, server: server, signedIn: signedIn),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: Text(LocaleKeys.appflowyServer_change.tr()),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => unawaited(
                  _leave(context, host: host, signedIn: signedIn),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: premium.textSecondary,
                ),
                child: Text(LocaleKeys.appflowyServer_leave.tr()),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _choose(
    BuildContext context, {
    required String server,
    required bool signedIn,
  }) async {
    final current = server.isEmpty
        ? null
        : AppFlowyServerChoice(
            url: server,
            webUrl: await getAppFlowyShareDomain(),
          );
    if (!context.mounted) {
      return;
    }
    final choice = await chooseAppFlowyServer(
      context,
      current: current,
      signsOutOf: signedIn ? serverHost(server) : null,
      pagesStay: !signedIn,
    );
    if (choice == null) {
      return;
    }
    // Signing in happens on the new server's own sign in screen, which a
    // session kept for the same address would go straight past.
    final sameData =
        serverHost(choice.url) == serverHost(await getAppFlowyCloudUrl());
    if ((signedIn || sameData) && !await _signOut()) {
      return;
    }
    await useAppFlowyServer(choice.url, webUrl: choice.webUrl);
    restart();
  }

  Future<void> _leave(
    BuildContext context, {
    required String host,
    required bool signedIn,
  }) async {
    final confirmed = await confirmSyncStep(
      context,
      title: LocaleKeys.appflowyServer_leaveTitle.tr(args: [host]),
      body: LocaleKeys.appflowyServer_leaveBody.tr(args: [host]),
      confirm: LocaleKeys.appflowyServer_leaveConfirm.tr(),
    );
    if (!confirmed || (signedIn && !await _signOut())) {
      return;
    }
    await useNoServer();
    restart();
  }

  static Future<bool> _signOut() async {
    try {
      await getIt<AuthService>().signOut();
      return true;
    } on FlowyError catch (error) {
      Log.error('Signing out before changing servers failed: ${error.msg}');
    } on FileSystemException catch (error) {
      Log.error('Signing out before changing servers failed: $error');
    } on StateError catch (error) {
      Log.error('Signing out before changing servers failed: $error');
    }
    showToastNotification(
      type: ToastificationType.error,
      message: LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
    );
    return false;
  }
}
