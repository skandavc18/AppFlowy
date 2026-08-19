import 'dart:convert';

import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/encryption/encryption_policy.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// The mark that says "this needs the workspace key".
///
/// It rides in `ViewPB.extra` beside every other envelope, so a page, a folder,
/// a collection, a table or a file gains protection without the backend
/// learning a new kind of thing and without a single field being migrated.
///
/// What the mark promises is precise, and the words in the interface say the
/// same: the way IN is closed. It does not claim the bytes on disk are
/// scrambled — for that, seal the blocks inside a page or the cells inside a
/// column, which really are replaced by ciphertext.
@immutable
class EncryptionMark {
  const EncryptionMark({
    required this.scope,
    this.protectedAt,
    this.note = '',
  });

  static const envelopeKey = 'appflowy_encryption';
  static const currentVersion = 1;

  final EncryptionScope scope;
  final DateTime? protectedAt;

  /// A private label for why this was protected. Never shown while locked.
  final String note;

  static EncryptionMark? fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return null;
    }
    final values = Map<String, Object?>.from(envelope);
    final version = values['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      return null;
    }

    final scope = values['scope'];
    final protectedAt = values['protected_at'];
    return EncryptionMark(
      scope: EncryptionScope.values.firstWhere(
        (value) => value.name == scope,
        orElse: () => EncryptionScope.page,
      ),
      protectedAt: protectedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(protectedAt, isUtc: true)
          : null,
      note: values['note'] is String ? values['note']! as String : '',
    );
  }

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = {
      'version': currentVersion,
      'scope': scope.name,
      if (protectedAt != null)
        'protected_at': protectedAt!.toUtc().millisecondsSinceEpoch,
      if (note.isNotEmpty) 'note': note,
    };
    return jsonEncode(values);
  }

  static String removeFromExtra(String extra) {
    final values = decodeViewExtra(extra)..remove(envelopeKey);
    return values.isEmpty ? '' : jsonEncode(values);
  }
}

extension EncryptionViewExtension on ViewPB {
  EncryptionMark? get encryptionMark => EncryptionMark.fromExtra(extra);

  /// Whether this item is protected at all.
  bool get isProtected => encryptionMark != null;

  /// Whether this item cannot be opened right now.
  ///
  /// The key being in memory is not enough: each protected item is opened on
  /// purpose, and closes again when the application does.
  bool get isLockedNow =>
      isProtected && !EncryptionVault.instance.isRevealed(id);

  /// Whether what is inside should stay out of the sidebar for now.
  ///
  /// A protected folder keeps its own name — it is how somebody finds it again,
  /// and a row of dots where a name should be is unusable. What the key buys is
  /// the list of what is inside, so the tree simply stops at a locked folder.
  bool get hidesChildrenWhileLocked => isLockedNow;
}

/// Which scope a view belongs to, so the menu can say the right word.
EncryptionScope encryptionScopeOf(ViewPB view) {
  if (view.isCollection) {
    return EncryptionScope.collection;
  }
  if (view.isWorkspaceFile) {
    return EncryptionScope.file;
  }
  if (view.isWorkspaceFolder || view.isSpace) {
    return EncryptionScope.folder;
  }
  return switch (view.layout) {
    ViewLayoutPB.Grid ||
    ViewLayoutPB.Board ||
    ViewLayoutPB.Calendar =>
      EncryptionScope.table,
    _ => EncryptionScope.page,
  };
}

/// Putting the mark on and taking it off.
abstract final class EncryptionMarkService {
  /// A folder can hold a great many things; walking for ever is not a service.
  static const int maximumTreeItems = 2000;
  static const int maximumTreeDepth = 12;

  /// Protects [view] and everything inside it, and says how many were marked.
  ///
  /// A folder that is protected while the files in it are not would be a
  /// promise nobody kept: the folder is only a way of reaching them, and every
  /// other way in would still be open. Collections are containers too, so they
  /// behave the same.
  ///
  /// Requires the key to be in memory: protecting something while locked would
  /// let somebody shut another person out of their own work.
  static Future<int> protect(ViewPB view, {String note = ''}) async {
    final vault = EncryptionVault.instance;
    await vault.ensureLoaded();
    if (!vault.isUnlocked) {
      return 0;
    }

    final at = DateTime.now().toUtc();
    return _applyToTree(
      view.id,
      (fresh) => EncryptionMark(
        scope: encryptionScopeOf(fresh),
        protectedAt: at,
        note: note,
      ).mergeIntoExtra(fresh.extra),
    );
  }

  /// Takes the protection off [view] and everything inside it.
  static Future<int> unprotect(ViewPB view) async {
    final vault = EncryptionVault.instance;
    await vault.ensureLoaded();
    if (!vault.isUnlocked) {
      return 0;
    }

    return _applyToTree(
      view.id,
      (fresh) => EncryptionMark.removeFromExtra(fresh.extra),
    );
  }

  /// Whether something above [viewId] is protected.
  ///
  /// Marking the tree covers everything present when the folder was protected;
  /// this is what covers a file put into it afterwards.
  static Future<bool> isProtectedByAnAncestor(String viewId) async =>
      await protectingAncestorOf(viewId) != null;

  /// Which ancestor is protecting [viewId], if any.
  ///
  /// The gate needs the id, not just the fact: unlocking a folder has to open
  /// what is in it, rather than asking again for every file.
  static Future<String?> protectingAncestorOf(String viewId) async {
    final result = await ViewBackendService.getViewAncestors(viewId);
    return result.fold(
      // The chain includes the view itself, which is not its own ancestor.
      (ancestors) => ancestors.items
          .firstWhereOrNull((view) => view.id != viewId && view.isProtected)
          ?.id,
      (error) {
        Log.warn('Could not read the ancestors of $viewId: $error');
        return null;
      },
    );
  }

  /// Walks [rootId] and its descendants, rewriting each one's extra.
  static Future<int> _applyToTree(
    String rootId,
    String Function(ViewPB view) nextExtra,
  ) async {
    var changed = 0;
    var frontier = <String>[rootId];

    for (var depth = 0;
        depth <= maximumTreeDepth && frontier.isNotEmpty;
        depth++) {
      final next = <String>[];
      for (final id in frontier) {
        if (changed >= maximumTreeItems) {
          Log.warn('Stopped marking $rootId at $maximumTreeItems items.');
          return changed;
        }

        // Re-read: the extra carries the cover, the icon and every other mark,
        // and a stale copy would write them away.
        final current = await ViewBackendService.getView(id);
        final fresh = current.fold((found) => found, (_) => null);
        if (fresh == null) {
          continue;
        }

        final result = await ViewBackendService.updateView(
          viewId: id,
          extra: nextExtra(fresh),
        );
        result.fold(
          (_) => changed++,
          (error) => Log.warn('$id could not be marked: $error'),
        );

        final children = await ViewBackendService.getChildViews(viewId: id)
            .fold((views) => views, (_) => const <ViewPB>[]);
        next.addAll(children.map((child) => child.id));
      }
      frontier = next;
    }

    return changed;
  }

  /// Takes the mark off everything that carries one, and says how many.
  ///
  /// Removing the workspace passphrase has to remove what it was guarding. A
  /// mark left behind gates its item against a key that no longer exists — and
  /// against any key set later, which reads as the old passphrase still being
  /// asked for.
  ///
  /// Unlike [unprotect] this does not need the key: opening a gate is not
  /// decryption, and the caller has already proved the passphrase.
  static Future<int> clearEveryMark() async {
    final views = await WorkspaceItemService().getAllViews().fold(
          (views) => views,
          (error) {
            Log.warn('Could not list views to clear encryption marks: $error');
            return const <ViewPB>[];
          },
        );

    var cleared = 0;
    for (final view in views.where((view) => view.isProtected)) {
      final current = await ViewBackendService.getView(view.id);
      final fresh = current.fold((found) => found, (_) => null);
      if (fresh == null) {
        continue;
      }
      final result = await ViewBackendService.updateView(
        viewId: view.id,
        extra: EncryptionMark.removeFromExtra(fresh.extra),
      );
      result.fold(
        (_) => cleared++,
        (error) => Log.warn('${view.id} kept its encryption mark: $error'),
      );
    }
    return cleared;
  }
}
