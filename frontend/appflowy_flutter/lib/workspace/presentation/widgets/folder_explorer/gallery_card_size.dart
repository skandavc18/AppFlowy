import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
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

  static GalleryCardSize get value => notifier.value;

  /// Reads the stored size once, keeping the default if it cannot be read.
  ///
  /// A gallery is worth showing even when the preference is unavailable, so a
  /// missing store leaves the cards at their default size rather than failing.
  static Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    final stored = await _storage?.get(kGalleryCardSizeKey);
    if (stored != null) {
      notifier.value = GalleryCardSize.fromName(stored);
    }
  }

  static Future<void> write(GalleryCardSize size) async {
    _loaded = true;
    notifier.value = size;
    await _storage?.set(kGalleryCardSizeKey, size.name);
  }

  static KeyValueStorage? get _storage =>
      getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null;

  @visibleForTesting
  static void reset() {
    _loaded = false;
    notifier.value = GalleryCardSize.medium;
  }
}

/// Asks which size the cards should be drawn at, anchored at [globalPosition].
Future<void> showGalleryCardSizeMenu({
  required BuildContext context,
  required Offset globalPosition,
}) async {
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
    await GalleryCardSizeStore.write(chosen);
  }
}
