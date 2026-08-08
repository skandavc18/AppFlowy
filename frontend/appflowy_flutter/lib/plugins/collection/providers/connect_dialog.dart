import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/providers/connections/connect_service.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_flow.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Connects one account.
///
/// Three shapes, one dialog, because they differ only in what they ask for:
/// a self-hosted server wants an address and a key, a code host wants a token,
/// and the rest sign in through a browser.
Future<ProviderConnection?> showProviderConnectDialog(
  BuildContext context, {
  required ProviderServiceInfo info,
  bool requestWriteAccess = false,
}) =>
    showDialog<ProviderConnection>(
      context: context,
      builder: (context) => _ConnectDialog(
        info: info,
        requestWriteAccess: requestWriteAccess,
      ),
    );

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({
    required this.info,
    required this.requestWriteAccess,
  });

  final ProviderServiceInfo info;
  final bool requestWriteAccess;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  final host = TextEditingController();
  final token = TextEditingController();
  final clientId = TextEditingController();
  final clientSecret = TextEditingController();

  final connector = ProviderConnector();

  bool busy = false;
  bool needsApp = false;

  /// Set when somebody reopens the application fields to correct them. Without
  /// it a client id saved once could never be given the secret it turned out
  /// to need.
  bool editingApp = false;
  String? error;

  bool get showsAppFields => needsApp || editingApp;

  @override
  void initState() {
    super.initState();
    if (widget.info.authKind == ProviderAuthKind.oauth) {
      unawaited(_loadApp());
    }
  }

  Future<void> _loadApp() async {
    final app = await OAuthAppRegistry.instance.read(widget.info.service);
    if (!mounted) {
      return;
    }
    setState(() {
      needsApp = app == null || !app.isConfigured;
      clientId.text = app?.clientId ?? '';
      clientSecret.text = app?.clientSecret ?? '';
    });
  }

  @override
  void dispose() {
    host.dispose();
    token.dispose();
    clientId.dispose();
    clientSecret.dispose();
    connector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final info = widget.info;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ViewerCard(
          color: palette.floatingSurface,
          reactsToPointer: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(palette, info),
                const SizedBox(height: 18),
                ..._fields(palette, info),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  _ErrorLine(message: error!, palette: palette),
                ],
                const SizedBox(height: 20),
                _actions(palette, info),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(FolderExplorerPalette palette, ProviderServiceInfo info) =>
      Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: info.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(info.icon, size: 19, color: info.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  LocaleKeys.providers_connectTo.tr(args: [info.label]),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontVariations: const [FontVariation.weight(640)],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitleFor(info),
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );

  String _subtitleFor(ProviderServiceInfo info) => switch (info.authKind) {
        ProviderAuthKind.selfHostedToken =>
          LocaleKeys.providers_connectSelfHosted.tr(),
        ProviderAuthKind.personalToken =>
          LocaleKeys.providers_connectToken.tr(),
        _ => LocaleKeys.providers_connectBrowser.tr(),
      };

  List<Widget> _fields(
    FolderExplorerPalette palette,
    ProviderServiceInfo info,
  ) {
    switch (info.authKind) {
      case ProviderAuthKind.none:
        return const <Widget>[];

      case ProviderAuthKind.selfHostedToken:
      case ProviderAuthKind.personalToken:
        return [
          if (info.needsHost) ...[
            ProviderTextField(
              label: LocaleKeys.providers_serverAddress.tr(),
              hint: info.hostHint,
              controller: host,
              palette: palette,
              autofocus: true,
            ),
            const SizedBox(height: 12),
          ],
          ProviderTextField(
            label: LocaleKeys.providers_accessToken.tr(),
            hint: LocaleKeys.providers_accessTokenHint.tr(),
            controller: token,
            palette: palette,
            obscure: true,
            showPasteButton: true,
            autofocus: !info.needsHost,
          ),
          if (info.tokenHelpUrl != null) ...[
            const SizedBox(height: 8),
            _LinkLine(
              label: LocaleKeys.providers_createToken.tr(args: [info.label]),
              url: info.tokenHelpUrl!,
              palette: palette,
            ),
          ],
          const SizedBox(height: 12),
          _SecurityNote(palette: palette),
        ];

      case ProviderAuthKind.oauth:
        final endpoints = OAuthServices.forService(info.service);
        if (!showsAppFields) {
          return [
            _SecurityNote(palette: palette),
            const SizedBox(height: 10),
            Text(
              LocaleKeys.providers_scopeNote.tr(),
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            _LinkLine(
              label: LocaleKeys.providers_editApp.tr(),
              palette: palette,
              onTap: () => setState(() => editingApp = true),
            ),
          ];
        }
        return [
          Text(
            LocaleKeys.providers_needsAppBody.tr(args: [info.label]),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          ProviderTextField(
            label: LocaleKeys.providers_clientId.tr(),
            controller: clientId,
            palette: palette,
            autofocus: true,
            showPasteButton: true,
          ),
          if (endpoints?.wantsClientSecret ?? false) ...[
            const SizedBox(height: 12),
            ProviderTextField(
              label: LocaleKeys.providers_clientSecret.tr(),
              controller: clientSecret,
              palette: palette,
              obscure: true,
              showPasteButton: true,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            LocaleKeys.providers_desktopClientHint.tr(),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          if ((endpoints?.registrationUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _LinkLine(
              label: LocaleKeys.providers_registerApp.tr(args: [info.label]),
              url: endpoints!.registrationUrl,
              palette: palette,
            ),
          ],
          const SizedBox(height: 10),
          _RedirectNote(palette: palette),
        ];
    }
  }

  Widget _actions(FolderExplorerPalette palette, ProviderServiceInfo info) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _DialogButton(
            label: LocaleKeys.button_cancel.tr(),
            palette: palette,
            onPressed: busy ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          _DialogButton(
            label: busy
                ? LocaleKeys.providers_connecting.tr()
                : info.needsBrowser && !showsAppFields
                    ? LocaleKeys.providers_signIn.tr()
                    : LocaleKeys.providers_connect.tr(),
            palette: palette,
            primary: true,
            onPressed: busy ? null : _connect,
          ),
        ],
      );

  Future<void> _connect() async {
    setState(() {
      busy = true;
      error = null;
    });

    try {
      final info = widget.info;
      if (info.authKind == ProviderAuthKind.oauth) {
        if (showsAppFields) {
          final id = clientId.text.trim();
          if (id.isEmpty) {
            throw const ProviderFailure(
              ProviderStatus.error,
              detail: oauthClientIdRequired,
            );
          }
          final secret = clientSecret.text.trim();
          if ((OAuthServices.forService(info.service)?.wantsClientSecret ??
                  false) &&
              secret.isEmpty) {
            throw const ProviderFailure(
              ProviderStatus.error,
              detail: oauthClientSecretRequired,
            );
          }
          await OAuthAppRegistry.instance.write(
            info.service,
            OAuthApp(clientId: id, clientSecret: secret),
          );
          if (mounted) {
            setState(() {
              needsApp = false;
              editingApp = false;
            });
          }
        }

        final connection = await connector.connectWithOAuth(
          service: info.service,
          requestWriteAccess: widget.requestWriteAccess,
        );
        if (mounted) {
          Navigator.of(context).pop(connection);
        }
        return;
      }

      final connection = await connector.connectWithToken(
        service: info.service,
        token: token.text,
        host: host.text,
      );
      if (mounted) {
        Navigator.of(context).pop(connection);
      }
    } on ProviderFailure catch (failure) {
      if (mounted) {
        setState(() {
          error = _readable(failure, widget.info);
          // A failure about the application itself has to reopen the fields,
          // or there is no way to correct what it is complaining about.
          if (_isAboutTheApp(failure.detail)) {
            editingApp = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = LocaleKeys.providers_state_errorTitle.tr());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  static bool _isAboutTheApp(String detail) => const {
        oauthClientIdRequired,
        oauthClientSecretRequired,
        'invalid_client',
        'unauthorized_client',
        'invalid_request',
      }.contains(detail);

  /// A failure turned into a sentence.
  ///
  /// A service's own prose never reaches the screen; what does is the standard
  /// OAuth code it answered with, said in AppFlowy's terms — because the fix is
  /// always something to change in this dialog.
  static String _readable(ProviderFailure failure, ProviderServiceInfo info) {
    final named = _fromCode(failure.detail, info);
    if (named != null) {
      return named;
    }
    return switch (failure.status) {
      ProviderStatus.authExpired =>
        LocaleKeys.providers_error_refused.tr(args: [info.label]),
      ProviderStatus.offline => LocaleKeys.providers_error_unreachable.tr(),
      ProviderStatus.permissionDenied =>
        LocaleKeys.providers_error_scope.tr(args: [info.label]),
      ProviderStatus.notFound =>
        LocaleKeys.providers_error_notFound.tr(args: [info.label]),
      _ when failure.detail.isNotEmpty => LocaleKeys
          .providers_error_oauthGeneric
          .tr(args: [info.label, failure.detail]),
      _ => LocaleKeys.providers_error_generic.tr(args: [info.label]),
    };
  }

  static String? _fromCode(String detail, ProviderServiceInfo info) =>
      switch (detail) {
        oauthClientIdRequired =>
          LocaleKeys.providers_error_clientIdRequired.tr(),
        oauthClientSecretRequired => LocaleKeys
            .providers_error_clientSecretRequired
            .tr(args: [info.label]),
        oauthGrantRevoked =>
          LocaleKeys.providers_error_grantRevoked.tr(args: [info.label]),
        'invalid_client' =>
          LocaleKeys.providers_error_invalidClient.tr(args: [info.label]),
        'unauthorized_client' =>
          LocaleKeys.providers_error_unauthorizedClient.tr(args: [info.label]),
        'invalid_grant' => LocaleKeys.providers_error_invalidGrant.tr(),
        'invalid_scope' =>
          LocaleKeys.providers_error_invalidScope.tr(args: [info.label]),
        'access_denied' => LocaleKeys.providers_error_accessDenied.tr(),
        _ => null,
      };
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote({required this.palette});

  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) {
    final sealed = ProviderConnections.instance.canPersistSecrets;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          sealed ? Icons.shield_rounded : Icons.info_outline_rounded,
          size: 14,
          color: palette.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            sealed
                ? LocaleKeys.providers_secretSealed.tr()
                : LocaleKeys.providers_secretSessionOnly.tr(),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _RedirectNote extends StatelessWidget {
  const _RedirectNote({required this.palette});

  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.providers_redirectTitle.tr(),
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 11.5,
                fontVariations: const [FontVariation.weight(580)],
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              'http://127.0.0.1:<port>/appflowy-oauth',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              LocaleKeys.providers_redirectBody.tr(),
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}

class _LinkLine extends StatelessWidget {
  const _LinkLine({
    required this.label,
    required this.palette,
    this.url,
    this.onTap,
  }) : assert(url != null || onTap != null, 'A link has to do something.');

  final String label;
  final String? url;
  final VoidCallback? onTap;
  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap ??
              () => unawaited(
                    launchUrl(
                      Uri.parse(url!),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                url == null ? Icons.tune_rounded : Icons.open_in_new_rounded,
                size: 12,
                color: palette.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11.5,
                  decoration: TextDecoration.underline,
                  decorationColor: palette.border,
                ),
              ),
            ],
          ),
        ),
      );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message, required this.palette});

  final String message;
  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE98A8A)
        : const Color(0xFFB3261E);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogButton extends StatefulWidget {
  const _DialogButton({
    required this.label,
    required this.palette,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final FolderExplorerPalette palette;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null;
    final accent = Theme.of(context).colorScheme.primary;
    final background = widget.primary
        ? accent.withValues(alpha: enabled ? (hovered ? 0.22 : 0.15) : 0.07)
        : palette.hover.withValues(alpha: hovered && enabled ? 1 : 0);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.primary
                  ? accent.withValues(alpha: enabled ? 1 : 0.5)
                  : palette.textSecondary.withValues(alpha: enabled ? 1 : 0.5),
              fontSize: 12.5,
              fontVariations: const [FontVariation.weight(580)],
            ),
          ),
        ),
      ),
    );
  }
}
