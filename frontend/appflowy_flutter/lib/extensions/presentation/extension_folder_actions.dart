import 'dart:io';

import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/presentation/extension_views.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Opening the folder, copying its path and writing the example — the same
/// three things from Settings and from the Extensions page.
class ExtensionFolderActions {
  const ExtensionFolderActions({required this.store});

  final ExtensionStore store;

  Future<void> openFolder(String root) async {
    if (root.isEmpty) {
      return;
    }
    await Directory(root).create(recursive: true);
    await launchUrl(Uri.file(root));
  }

  Future<void> copyPath(BuildContext context, String root) async {
    await Clipboard.setData(ClipboardData(text: root));
    if (context.mounted) {
      showToastNotification(
        context: context,
        message: LocaleKeys.extensions_pathCopied.tr(),
      );
    }
  }

  Future<void> writeExample(BuildContext context, String root) async {
    if (root.isEmpty) {
      return;
    }
    final folder = Directory(p.join(root, exampleExtensionId));
    if (folder.existsSync()) {
      if (context.mounted) {
        showToastNotification(
          context: context,
          message: LocaleKeys.extensions_exampleExists.tr(),
          type: ToastificationType.warning,
        );
      }
      return;
    }
    await Directory(p.join(folder.path, 'actions')).create(recursive: true);
    await File(p.join(folder.path, 'manifest.json'))
        .writeAsString(exampleExtensionManifest);
    await File(p.join(folder.path, 'actions', 'quote.json'))
        .writeAsString(exampleExtensionAction);
    await store.reload();
    if (context.mounted) {
      showToastNotification(
        context: context,
        message: LocaleKeys.extensions_exampleCreated.tr(),
      );
    }
  }
}
