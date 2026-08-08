import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:flutter/material.dart';

/// Where a collection's content actually lives.
///
/// A service is never a collection *type* — an album backed by Immich is still
/// an Album, a repository backed by GitHub is still a Repository. The service
/// only says which implementation answers the questions the collection asks,
/// so the person reading it keeps one mental model whatever is underneath.
enum ProviderService {
  local,
  immich,
  googlePhotos,
  github,
  gitlab,
  googleDrive,
  oneDrive,
  box,
  googleCalendar,
  gmail,
  outlookMail;

  static ProviderService fromValue(Object? value) {
    for (final service in ProviderService.values) {
      if (service.name == value) {
        return service;
      }
    }
    return ProviderService.local;
  }

  bool get isLocal => this == ProviderService.local;
  bool get isRemote => !isLocal;
}

/// Who the account belongs to, rather than what it is being used for.
///
/// Drive, Photos, Calendar and Gmail are four things AppFlowy can do with ONE
/// Google account: the same sign in, the same application identity, the same
/// refresh token. Grouping by family is what lets the connections page read as
/// a list of accounts instead of a list of products, and it is why a client id
/// is registered once per family rather than once per feature.
enum ProviderAccountFamily {
  workspace,
  google,
  microsoft,
  box,
  immich,
  github,
  gitlab;

  /// A company name is not translated, the same way a product name is not.
  String get label => switch (this) {
        ProviderAccountFamily.workspace => 'This workspace',
        ProviderAccountFamily.google => 'Google',
        ProviderAccountFamily.microsoft => 'Microsoft',
        ProviderAccountFamily.box => 'Box',
        ProviderAccountFamily.immich => 'Immich',
        ProviderAccountFamily.github => 'GitHub',
        ProviderAccountFamily.gitlab => 'GitLab',
      };

  IconData get icon => switch (this) {
        ProviderAccountFamily.workspace => Icons.home_rounded,
        ProviderAccountFamily.google => Icons.g_mobiledata_rounded,
        ProviderAccountFamily.microsoft => Icons.window_rounded,
        ProviderAccountFamily.box => Icons.inbox_rounded,
        ProviderAccountFamily.immich => Icons.photo_camera_back_rounded,
        ProviderAccountFamily.github => Icons.hub_rounded,
        ProviderAccountFamily.gitlab => Icons.merge_type_rounded,
      };

  Color get accent => switch (this) {
        ProviderAccountFamily.workspace => const Color(0xFF6B7280),
        ProviderAccountFamily.google => const Color(0xFF1A73E8),
        ProviderAccountFamily.microsoft => const Color(0xFF0364B8),
        ProviderAccountFamily.box => const Color(0xFF0061D5),
        ProviderAccountFamily.immich => const Color(0xFF4250AF),
        ProviderAccountFamily.github => const Color(0xFF24292F),
        ProviderAccountFamily.gitlab => const Color(0xFFFC6D26),
      };

  bool get isWorkspace => this == ProviderAccountFamily.workspace;

  /// Whether one sign in can carry every permission this account offers.
  ///
  /// ⚠️ Microsoft's is the exception and cannot be made to: its token endpoint
  /// issues a token for ONE resource at a time, so a Graph scope for OneDrive
  /// and an Outlook scope for mail are refused in the same request. Everything
  /// else grants the lot in a single browser round trip.
  bool get sharesOneGrant => this != ProviderAccountFamily.microsoft;
}

/// How a service proves who is asking.
enum ProviderAuthKind {
  /// Nothing to prove — the workspace already holds the content.
  none,

  /// A browser round trip, PKCE, and a refresh token afterwards.
  oauth,

  /// A token the person pastes in, issued by the service itself.
  personalToken,

  /// A self-hosted server: an address plus a token issued by that server.
  selfHostedToken,
}

/// The identity of one service: what to call it, how to draw it, what it can
/// stand behind, and how it authenticates.
@immutable
class ProviderServiceInfo {
  const ProviderServiceInfo({
    required this.service,
    required this.label,
    required this.icon,
    required this.accent,
    required this.authKind,
    required this.kinds,
    required this.family,
    this.tokenHelpUrl,
    this.needsHost = false,
    this.hostHint = '',
    this.picksExternally = false,
  });

  final ProviderService service;

  /// Product names are not translated — "GitHub" is "GitHub" everywhere.
  final String label;

  final IconData icon;
  final Color accent;
  final ProviderAuthKind authKind;

  /// The collection types this service can stand behind.
  final Set<CollectionKind> kinds;

  /// Whose account signs this in. Everything in one family shares an
  /// application identity and can share a sign in.
  final ProviderAccountFamily family;

  /// Where the person creates the token this service wants, when it wants one.
  final String? tokenHelpUrl;

  /// Whether the connection needs a server address as well as a secret.
  final bool needsHost;
  final String hostHint;

  /// Whether what a collection binds to is chosen in the service's own
  /// interface rather than listed by AppFlowy. Google Photos is the only one:
  /// it no longer lets an application see a library, so the person picks in
  /// Google's picker and the selection comes back.
  final bool picksExternally;

  bool supports(CollectionKind kind) => kinds.contains(kind);

  bool get needsBrowser => authKind == ProviderAuthKind.oauth;
}

/// The catalogue of services, and the questions the interface asks of it.
abstract final class ProviderServices {
  static const local = ProviderServiceInfo(
    service: ProviderService.local,
    label: 'This workspace',
    icon: Icons.home_rounded,
    accent: Color(0xFF6B7280),
    authKind: ProviderAuthKind.none,
    kinds: {...CollectionKind.values},
    family: ProviderAccountFamily.workspace,
  );

  static const immich = ProviderServiceInfo(
    service: ProviderService.immich,
    label: 'Immich',
    icon: Icons.photo_camera_back_rounded,
    accent: Color(0xFF4250AF),
    authKind: ProviderAuthKind.selfHostedToken,
    kinds: {CollectionKind.album},
    family: ProviderAccountFamily.immich,
    needsHost: true,
    hostHint: 'https://photos.example.com',
    tokenHelpUrl: 'https://immich.app/docs/features/command-line-interface',
  );

  static const googlePhotos = ProviderServiceInfo(
    service: ProviderService.googlePhotos,
    label: 'Google Photos',
    icon: Icons.photo_library_rounded,
    accent: Color(0xFFEA4335),
    authKind: ProviderAuthKind.oauth,
    kinds: {CollectionKind.album},
    family: ProviderAccountFamily.google,
    picksExternally: true,
  );

  static const github = ProviderServiceInfo(
    service: ProviderService.github,
    label: 'GitHub',
    icon: Icons.hub_rounded,
    accent: Color(0xFF24292F),
    authKind: ProviderAuthKind.personalToken,
    kinds: {CollectionKind.repository},
    family: ProviderAccountFamily.github,
    tokenHelpUrl: 'https://github.com/settings/tokens',
  );

  static const gitlab = ProviderServiceInfo(
    service: ProviderService.gitlab,
    label: 'GitLab',
    icon: Icons.merge_type_rounded,
    accent: Color(0xFFFC6D26),
    authKind: ProviderAuthKind.personalToken,
    kinds: {CollectionKind.repository},
    family: ProviderAccountFamily.gitlab,
    needsHost: true,
    hostHint: 'https://gitlab.com',
    tokenHelpUrl: 'https://gitlab.com/-/user_settings/personal_access_tokens',
  );

  static const googleDrive = ProviderServiceInfo(
    service: ProviderService.googleDrive,
    label: 'Google Drive',
    icon: Icons.cloud_rounded,
    accent: Color(0xFF1A73E8),
    authKind: ProviderAuthKind.oauth,
    kinds: {CollectionKind.folder},
    family: ProviderAccountFamily.google,
  );

  static const oneDrive = ProviderServiceInfo(
    service: ProviderService.oneDrive,
    label: 'OneDrive',
    icon: Icons.cloud_queue_rounded,
    accent: Color(0xFF0364B8),
    authKind: ProviderAuthKind.oauth,
    kinds: {CollectionKind.folder},
    family: ProviderAccountFamily.microsoft,
  );

  static const box = ProviderServiceInfo(
    service: ProviderService.box,
    label: 'Box',
    icon: Icons.inbox_rounded,
    accent: Color(0xFF0061D5),
    authKind: ProviderAuthKind.oauth,
    kinds: {CollectionKind.folder},
    family: ProviderAccountFamily.box,
  );

  /// A calendar is not a collection, so this stands behind no [CollectionKind]
  /// at all — it is connected in settings and read by the calendar view.
  static const googleCalendar = ProviderServiceInfo(
    service: ProviderService.googleCalendar,
    label: 'Google Calendar',
    icon: Icons.calendar_month_rounded,
    accent: Color(0xFF1A73E8),
    authKind: ProviderAuthKind.oauth,
    kinds: {},
    family: ProviderAccountFamily.google,
  );

  /// Mail signs in the same way everything else does, and reads over IMAP with
  /// the access token as `XOAUTH2`. It stands behind no [CollectionKind]: a
  /// mailbox is bound from the email collection's own panel, not by binding
  /// the collection itself to a service.
  static const gmail = ProviderServiceInfo(
    service: ProviderService.gmail,
    label: 'Gmail',
    icon: Icons.mail_rounded,
    accent: Color(0xFFEA4335),
    authKind: ProviderAuthKind.oauth,
    kinds: {},
    family: ProviderAccountFamily.google,
  );

  static const outlookMail = ProviderServiceInfo(
    service: ProviderService.outlookMail,
    label: 'Outlook Mail',
    icon: Icons.alternate_email_rounded,
    accent: Color(0xFF0364B8),
    authKind: ProviderAuthKind.oauth,
    kinds: {},
    family: ProviderAccountFamily.microsoft,
  );

  static const all = <ProviderServiceInfo>[
    local,
    immich,
    googlePhotos,
    github,
    gitlab,
    googleDrive,
    oneDrive,
    box,
    googleCalendar,
    gmail,
    outlookMail,
  ];

  /// The services a person can actually connect to, i.e. everything but the
  /// workspace itself.
  static List<ProviderServiceInfo> get connectable =>
      all.where((info) => info.service.isRemote).toList(growable: false);

  static ProviderServiceInfo of(ProviderService service) =>
      all.firstWhere((info) => info.service == service, orElse: () => local);

  /// The services that can stand behind [kind], the workspace first.
  static List<ProviderServiceInfo> forKind(CollectionKind kind) =>
      all.where((info) => info.supports(kind)).toList(growable: false);

  /// Whether [kind] has anything to offer beyond the workspace itself.
  static bool hasRemoteOptions(CollectionKind kind) =>
      forKind(kind).any((info) => info.service.isRemote);

  /// The services a folder can copy files out of.
  ///
  /// Wider than any one collection type: a plain folder holds anything, so it
  /// can take a photo out of a library as readily as a document out of a drive.
  static List<ProviderServiceInfo> importable() => [
        for (final info in all)
          if (info.service.isRemote &&
              (info.kinds.contains(CollectionKind.folder) ||
                  info.kinds.contains(CollectionKind.album)))
            info,
      ];

  /// The services with folders that can be mounted inside a workspace folder.
  ///
  /// A photo library has no folders to mount, so it is not offered.
  static List<ProviderServiceInfo> mountable() => [
        for (final info in all)
          if (info.service.isRemote &&
              !info.picksExternally &&
              info.kinds.contains(CollectionKind.folder))
            info,
      ];

  /// Everything one account can be used for, in catalogue order.
  static List<ProviderServiceInfo> forFamily(ProviderAccountFamily family) => [
        for (final info in all)
          if (info.service.isRemote && info.family == family) info,
      ];

  /// The families a person can connect an account in, in catalogue order.
  static List<ProviderAccountFamily> families() {
    final seen = <ProviderAccountFamily>[];
    for (final info in all) {
      if (info.service.isRemote && !seen.contains(info.family)) {
        seen.add(info.family);
      }
    }
    return seen;
  }

  /// The services that read a mailbox over IMAP with an OAuth token.
  static List<ProviderServiceInfo> mailServices() => const [gmail, outlookMail];
}
