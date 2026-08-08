import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/registered_providers.dart';

/// Builds the provider that answers for one collection.
typedef ProviderFactory = CollectionProvider Function(
  ProviderConnection connection,
  CollectionSource source,
);

/// The catalogue of provider implementations.
///
/// Registration is the extension point: a new service is one factory and one
/// entry in [ProviderServices]. Nothing above this line changes.
abstract final class ProviderRegistry {
  static final Map<ProviderService, ProviderFactory> _factories = {};
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    registerBuiltInProviders();
  }

  static void register(ProviderService service, ProviderFactory factory) {
    _ensureInitialized();
    _factories[service] = factory;
  }

  static bool supports(ProviderService service) {
    _ensureInitialized();
    return _factories.containsKey(service);
  }

  /// The provider for [source], or null when the collection is local.
  ///
  /// Throws [ProviderFailure.authExpired] when the collection names a
  /// connection that is no longer there, because that is exactly what a person
  /// has to fix and it reads the same as a revoked token.
  static CollectionProvider? create(
    CollectionSource source, {
    ProviderConnections? connections,
  }) {
    if (source.isLocal) {
      return null;
    }
    _ensureInitialized();

    final factory = _factories[source.service];
    if (factory == null) {
      throw ProviderFailure(
        ProviderStatus.error,
        detail: 'No provider is registered for ${source.service.name}.',
      );
    }

    final registry = connections ?? ProviderConnections.instance;
    final connection = registry.byId(source.connectionId);
    if (connection == null) {
      throw const ProviderFailure.authExpired(
        'The connection this collection uses is gone.',
      );
    }

    return factory(connection, source);
  }

  static void reset() {
    _factories.clear();
    _initialized = false;
  }
}
