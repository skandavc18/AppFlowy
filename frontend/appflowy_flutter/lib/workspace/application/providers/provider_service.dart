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
  box;

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
  );

  static const immich = ProviderServiceInfo(
    service: ProviderService.immich,
    label: 'Immich',
    icon: Icons.photo_camera_back_rounded,
    accent: Color(0xFF4250AF),
    authKind: ProviderAuthKind.selfHostedToken,
    kinds: {CollectionKind.album},
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
    picksExternally: true,
  );

  static const github = ProviderServiceInfo(
    service: ProviderService.github,
    label: 'GitHub',
    icon: Icons.hub_rounded,
    accent: Color(0xFF24292F),
    authKind: ProviderAuthKind.personalToken,
    kinds: {CollectionKind.repository},
    tokenHelpUrl: 'https://github.com/settings/tokens',
  );

  static const gitlab = ProviderServiceInfo(
    service: ProviderService.gitlab,
    label: 'GitLab',
    icon: Icons.merge_type_rounded,
    accent: Color(0xFFFC6D26),
    authKind: ProviderAuthKind.personalToken,
    kinds: {CollectionKind.repository},
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
  );

  static const oneDrive = ProviderServiceInfo(
    service: ProviderService.oneDrive,
    label: 'OneDrive',
    icon: Icons.cloud_queue_rounded,
    accent: Color(0xFF0364B8),
    authKind: ProviderAuthKind.oauth,
    kinds: {CollectionKind.folder},
  );

  static const box = ProviderServiceInfo(
    service: ProviderService.box,
    label: 'Box',
    icon: Icons.inbox_rounded,
    accent: Color(0xFF0061D5),
    authKind: ProviderAuthKind.oauth,
    kinds: {CollectionKind.folder},
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
}
