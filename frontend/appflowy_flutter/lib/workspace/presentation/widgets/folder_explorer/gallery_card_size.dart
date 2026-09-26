import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

export 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';

const String kGalleryCardSizeKey = 'appflowy_gallery_card_size';

/// The one place the gallery card size lives.
///
/// Every gallery listens to the same value, so changing it in one view
/// resizes the cards in all of them at once.
abstract final class GalleryCardSizeStore {
  static final ValueNotifier<GalleryCardSize> notifier =
      ValueNotifier(GalleryCardSize.medium);

  static bool _loaded = false;
  static Future<void>? _loading;
  static Future<void>? _writing;
  static int _generation = 0;
  static int _revision = 0;
  static GalleryCardSize _persisted = GalleryCardSize.medium;

  static GalleryCardSize get value => notifier.value;

  /// Reads the stored size once, keeping the default if it cannot be read.
  ///
  /// A gallery is worth showing even when the preference is unavailable, so a
  /// missing store leaves the cards at their default size rather than failing.
  static Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    final storage = _storage;
    if (storage == null) {
      return Future.value();
    }
    final generation = _generation;
    return _loading ??= _read(storage, generation, _revision).whenComplete(() {
      if (generation == _generation) _loading = null;
    });
  }

  static Future<void> _read(
    KeyValueStorage storage,
    int generation,
    int revision,
  ) async {
    try {
      final stored = await storage.get(kGalleryCardSizeKey);
      // A write may have succeeded while retrying a previously failed read.
      // Its ACK is newer than this read, including the rollback value.
      if (generation != _generation || _loaded) return;
      _persisted = GalleryCardSize.fromName(stored);
      _loaded = true;
      // A choice made while the startup read was pending takes precedence.
      if (revision == _revision) notifier.value = _persisted;
    } catch (error) {
      // Do not latch a failed read; another gallery/menu can retry it.
      Log.warn('Unable to read the gallery card size: $error');
    }
  }

  static Future<void> write(GalleryCardSize size) {
    final loading = ensureLoaded();
    final storage = _storage;
    final generation = _generation;
    final revision = ++_revision;
    final write = (_writing ?? Future<void>.value()).then((_) async {
      await loading;
      if (generation != _generation) return;
      try {
        if (storage == null) {
          throw StateError('Gallery preferences are unavailable');
        }
        // KeyValueStorage acknowledges with void, not a settings payload.
        await storage.set(kGalleryCardSizeKey, size.name);
        if (generation != _generation) return;
        _persisted = size;
        _loaded = true;
      } catch (error) {
        if (generation == _generation && revision == _revision) {
          notifier.value = _persisted;
        }
        rethrow;
      }
    });
    // Reserve the queue before notifying: a listener may choose another size
    // synchronously. A failed save must not poison subsequent writes.
    _writing = write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    notifier.value = size;
    return write;
  }

  static KeyValueStorage? get _storage =>
      getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null;

  @visibleForTesting
  static void reset() {
    _generation++;
    _revision = 0;
    _loaded = false;
    _loading = null;
    _writing = null;
    _persisted = GalleryCardSize.medium;
    notifier.value = GalleryCardSize.medium;
  }
}

/// Asks which size the cards should be drawn at, anchored at [globalPosition].
Future<void> showGalleryCardSizeMenu({
  required BuildContext context,
  required Offset globalPosition,
}) async {
  await GalleryCardSizeStore.ensureLoaded();
  if (!context.mounted) return;
  final current = GalleryCardSizeStore.value;
  final chosen = await showAppMenu<GalleryCardSize>(
    context: context,
    globalPosition: globalPosition,
    entries: [
      const AppMenuHeader('Card size'),
      for (final size in GalleryCardSize.values)
        AppMenuItem(
          label: size.label,
          icon: size.icon,
          value: size,
          selected: size == current,
        ),
    ],
  );
  if (chosen != null) {
    try {
      await GalleryCardSizeStore.write(chosen);
    } catch (error) {
      Log.warn('Unable to save the gallery card size: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not save card size. Please try again.'),
        ),
      );
    }
  }
}
