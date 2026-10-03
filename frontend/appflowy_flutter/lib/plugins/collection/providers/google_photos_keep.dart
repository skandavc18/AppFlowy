import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/external_import.dart';
import 'package:appflowy/plugins/collection/providers/external_repository_view.dart';
import 'package:appflowy/plugins/collection/providers/google_photos_picker.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/services/google_photos_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Google lends a picked selection only until its session expires, and nothing
// can renew one. A collection either keeps its own copies, or only links and
// is picked again each time the selection lapses.

/// Copies a picked selection into a collection; [keepPickedPhotos] is the real
/// one.
typedef PickedPhotosKeeper = Future<int> Function(
  BuildContext context, {
  required String parentViewId,
  required CollectionSource picked,
});

/// Asks whether to keep a copy (true) or only link (false); null cancels.
/// [askToKeepPhotos] is the real one.
typedef KeepChoice = Future<bool?> Function(BuildContext context);

bool _linksOnly(CollectionSource source) =>
    source.option<bool>(GooglePhotosProvider.linkOnlyOption) == true;

/// Keep or only link a live Google Photos selection, or null when nothing
/// live is bound, somebody already chose to only link, or the page may not
/// change.
///
/// [keep] is replaced only by tests.
({VoidCallback keep, VoidCallback linkOnly})? keepPhotosOffer(
  BuildContext context, {
  required CollectionViewContext collection,
  required ProviderController? live,
  PickedPhotosKeeper keep = keepPickedPhotos,
}) {
  final source = collection.collectionView.source;
  final rebind = ProviderSourceUpdate.rebindOf(context);
  if (rebind == null ||
      live == null ||
      !source.info.picksExternally ||
      _linksOnly(source) ||
      live.hasFailed ||
      live.nodes.isEmpty) {
    return null;
  }
  return (
    keep: () => unawaited(
          _once(
            () => _keepInCollection(
              context,
              collection: collection,
              picked: source,
              rebind: rebind,
              keep: keep,
            ),
          ),
        ),
    linkOnly: () =>
        rebind(source.withOption(GooglePhotosProvider.linkOnlyOption, true)),
  );
}

/// The way back for a collection whose picked selection Google let lapse:
/// pick again, then keep or link what was picked. A collection that only links
/// was asked before, and goes on linking. Null when [failure] is anything else
/// or the page may not change.
///
/// [pick], [ask] and [keep] are replaced only by tests.
VoidCallback? pickPhotosAgainAction(
  BuildContext context, {
  required CollectionViewContext collection,
  required ProviderFailure? failure,
  GooglePhotosSelectionPicker pick = pickGooglePhotosSelection,
  KeepChoice ask = askToKeepPhotos,
  PickedPhotosKeeper keep = keepPickedPhotos,
}) {
  final rebind = ProviderSourceUpdate.rebindOf(context);
  if (rebind == null || failure == null || !failure.isLapsedSelection) {
    return null;
  }
  return () => unawaited(
        _once(() async {
          final source = collection.collectionView.source;
          await ProviderConnections.instance.ensureLoaded();
          final connection =
              ProviderConnections.instance.byId(source.connectionId);
          if (connection == null || !context.mounted) {
            return;
          }
          final picked = await pick(context, connection: connection);
          if (picked == null || !context.mounted) {
            return;
          }
          final keepCopy = _linksOnly(source) ? false : await ask(context);
          if (keepCopy == null || !context.mounted) {
            return;
          }
          if (!keepCopy) {
            _link(rebind, bound: source, picked: picked);
            return;
          }
          await _keepInCollection(
            context,
            collection: collection,
            picked: picked,
            rebind: rebind,
            keep: keep,
          );
        }),
      );
}

/// Points a collection at a fresh selection, still only linked.
void _link(
  void Function(CollectionSource) rebind, {
  required CollectionSource bound,
  required CollectionSource picked,
}) {
  final session = picked.option<String>(GooglePhotosProvider.sessionOption) ??
      picked.remoteId;
  if (bound.cacheKey != picked.cacheKey) {
    unawaited(ProviderCache.instance.evict(bound.cacheKey));
  }
  rebind(
    bound
        .copyWith(remoteId: picked.remoteId, lastSyncedAt: picked.lastSyncedAt)
        .withOption(GooglePhotosProvider.sessionOption, session)
        .withOption(GooglePhotosProvider.linkOnlyOption, true),
  );
}

/// One keep at a time, however quickly a button is pressed twice.
bool _keeping = false;

Future<void> _once(Future<void> Function() run) async {
  if (_keeping) {
    return;
  }
  _keeping = true;
  try {
    await run();
  } finally {
    _keeping = false;
  }
}

Future<void> _keepInCollection(
  BuildContext context, {
  required CollectionViewContext collection,
  required CollectionSource picked,
  required void Function(CollectionSource) rebind,
  required PickedPhotosKeeper keep,
}) async {
  final bound = collection.collectionView.source;
  final kept = await keep(
    context,
    parentViewId: collection.collectionView.id,
    picked: picked,
  );
  if (kept == 0) {
    return;
  }
  if (bound.cacheKey != picked.cacheKey) {
    unawaited(ProviderCache.instance.evict(bound.cacheKey));
  }
  // Persisted even if this view has gone: the copies are already filed.
  rebind(CollectionSource.local);
  if (context.mounted) {
    unawaited(collection.explorer.refresh());
  }
}

/// Asks whether a picked selection is kept in AppFlowy or only linked: true
/// keeps a copy, false links, null leaves everything as it was.
Future<bool?> askToKeepPhotos(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) => const _KeepChoiceDialog(),
    );

class _KeepChoiceDialog extends StatelessWidget {
  const _KeepChoiceDialog();

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ViewerCard(
          color: palette.floatingSurface,
          reactsToPointer: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  LocaleKeys.providers_photos_keepTitle.tr(),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontVariations: const [FontVariation.weight(640)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  LocaleKeys.providers_photos_keepBody.tr(),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
                _KeepChoiceTile(
                  key: const ValueKey('keep-photos-copy'),
                  icon: Icons.save_alt_rounded,
                  title: LocaleKeys.providers_photos_keepCopy.tr(),
                  body: LocaleKeys.providers_photos_keepCopyBody.tr(),
                  palette: palette,
                  onTap: () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: 8),
                _KeepChoiceTile(
                  key: const ValueKey('keep-photos-link'),
                  icon: Icons.link_rounded,
                  title: LocaleKeys.providers_photos_linkOnly.tr(),
                  body: LocaleKeys.providers_photos_linkOnlyBody.tr(),
                  palette: palette,
                  onTap: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(LocaleKeys.button_cancel.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepChoiceTile extends StatelessWidget {
  const _KeepChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final FolderExplorerPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(10);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: shape,
        hoverColor: palette.hover,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 18, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.5,
                        fontVariations: const [FontVariation.weight(600)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
