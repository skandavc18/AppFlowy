import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';

/// What an import of mail produced.
class EmailImportResult {
  const EmailImportResult({this.imported = 0, this.skipped = 0});

  final int imported;
  final int skipped;

  bool get isEmpty => imported == 0;
}

const emailImportExtensions = <String>['eml', 'mbox', 'mbx', 'txt'];

/// Brings mail into the collection.
///
/// A message file is stored as it was given, so the mailbox is always reading
/// the real thing; an mbox archive is taken apart first, because a mailbox
/// export is one file holding hundreds of messages and a folder of one file
/// would be no mailbox at all.
Future<EmailImportResult> importMailInto({
  required String parentViewId,
  WorkspaceItemService service = const WorkspaceItemService(),
}) async {
  final picked = await getIt<FilePickerService>().pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: emailImportExtensions,
  );

  final paths = picked?.files
          .map((file) => file.path)
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList() ??
      const <String>[];
  if (paths.isEmpty) {
    return const EmailImportResult();
  }

  var imported = 0;
  var skipped = 0;

  for (final path in paths) {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (_) {
      skipped += 1;
      continue;
    }

    final messages =
        looksLikeMboxArchive(bytes) ? splitMboxArchive(bytes) : [bytes];
    if (messages.isEmpty) {
      skipped += 1;
      continue;
    }

    for (final message in messages) {
      final result = await service.createBlankFile(
        parentViewId: parentViewId,
        kind: WorkspaceFileKind.file,
        name: emailFileNameFor(message),
        content: message,
      );
      result.fold(
        (_) => imported += 1,
        (_) => skipped += 1,
      );
    }
  }

  return EmailImportResult(imported: imported, skipped: skipped);
}

/// Runs an import and says what came of it.
Future<void> importMailWithFeedback(
  BuildContext context, {
  required ViewPB collection,
}) async {
  final result = await importMailInto(parentViewId: collection.id);
  if (!context.mounted || result.isEmpty && result.skipped == 0) {
    return;
  }

  showToastNotification(
    message: result.isEmpty
        ? LocaleKeys.collections_email_importNothing.tr()
        : LocaleKeys.collections_email_imported
            .tr(args: ['${result.imported}']),
    type: result.isEmpty
        ? ToastificationType.warning
        : ToastificationType.success,
  );
}
