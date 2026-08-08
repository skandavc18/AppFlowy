import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/services/box_provider.dart';
import 'package:appflowy/workspace/application/providers/services/github_provider.dart';
import 'package:appflowy/workspace/application/providers/services/gitlab_provider.dart';
import 'package:appflowy/workspace/application/providers/services/google_drive_provider.dart';
import 'package:appflowy/workspace/application/providers/services/google_photos_provider.dart';
import 'package:appflowy/workspace/application/providers/services/immich_provider.dart';
import 'package:appflowy/workspace/application/providers/services/onedrive_provider.dart';

/// Every provider implementation the application ships with.
///
/// This is the only file that has to change to add a service, alongside its
/// entry in [ProviderServices]. Registration is lazy, so a service nobody uses
/// costs nothing.
void registerBuiltInProviders() {
  ProviderRegistry.register(
    ProviderService.immich,
    (connection, source) =>
        ImmichAlbumProvider(connection: connection, source: source),
  );
  ProviderRegistry.register(
    ProviderService.googlePhotos,
    (connection, source) =>
        GooglePhotosProvider(connection: connection, source: source),
  );
  ProviderRegistry.register(
    ProviderService.github,
    (connection, source) =>
        GitHubRepositoryProvider(connection: connection, source: source),
  );
  ProviderRegistry.register(
    ProviderService.gitlab,
    (connection, source) =>
        GitLabRepositoryProvider(connection: connection, source: source),
  );
  ProviderRegistry.register(
    ProviderService.googleDrive,
    (connection, source) =>
        GoogleDriveProvider(connection: connection, source: source),
  );
  ProviderRegistry.register(
    ProviderService.oneDrive,
    (connection, source) =>
        OneDriveProvider(connection: connection, source: source),
  );
  ProviderRegistry.register(
    ProviderService.box,
    (connection, source) => BoxProvider(connection: connection, source: source),
  );
}
