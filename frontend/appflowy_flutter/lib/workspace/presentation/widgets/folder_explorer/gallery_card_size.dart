import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
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
  final palette = FolderExplorerPalette.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final current = GalleryCardSizeStore.value;
  final chosen = await showMenu<GalleryCardSize>(
    context: context,
    color: palette.floatingSurface,
    surfaceTintColor: Colors.transparent,
    elevation: 14,
    shadowColor: palette.shadow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    constraints: const BoxConstraints(minWidth: 196, maxWidth: 240),
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      PopupMenuItem<GalleryCardSize>(
        enabled: false,
        height: 26,
        child: Text(
          'CARD SIZE',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 10.5,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
            color: palette.textMuted,
          ),
        ),
      ),
      for (final size in GalleryCardSize.values)
        PopupMenuItem<GalleryCardSize>(
          value: size,
          height: 40,
          child: Row(
            children: [
              Icon(size.icon, size: 17, color: palette.textSecondary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  size.label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (size == current)
                Icon(Icons.check_rounded, size: 16, color: palette.accent),
            ],
          ),
        ),
    ],
  );
  if (chosen != null) {
    await GalleryCardSizeStore.write(chosen);
  }
}
