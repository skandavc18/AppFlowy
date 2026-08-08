import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/services/google_photos_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Runs one Google Photos picking session and returns what was chosen.
///
/// The choosing happens in Google's own interface, in a browser: AppFlowy opens
/// it, waits, and asks the session for the result. There is no way to list a
/// library any more, so this is the whole binding flow for Google Photos.
Future<CollectionSource?> pickGooglePhotosSelection(
  BuildContext context, {
  required ProviderConnection connection,
}) =>
    showDialog<CollectionSource>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _GooglePhotosPicker(connection: connection),
    );

class _GooglePhotosPicker extends StatefulWidget {
  const _GooglePhotosPicker({required this.connection});

  final ProviderConnection connection;

  @override
  State<_GooglePhotosPicker> createState() => _GooglePhotosPickerState();
}

class _GooglePhotosPickerState extends State<_GooglePhotosPicker> {
  GooglePhotosProvider? provider;
  PhotosPickingSession? session;
  Timer? poll;
  DateTime? deadline;
  String? error;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    poll?.cancel();
    provider?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => error = null);
    try {
      final created = ProviderRegistry.create(
        CollectionSource(
          service: ProviderService.googlePhotos,
          connectionId: widget.connection.id,
        ),
      );
      if (created is! GooglePhotosProvider) {
        throw const ProviderFailure(ProviderStatus.error);
      }
      provider?.dispose();
      provider = created;

      final opened = await created.createSession();
      if (!mounted) {
        return;
      }
      setState(() {
        session = opened;
        deadline = DateTime.now().add(opened.timeout);
      });

      await launchUrl(
        Uri.parse(opened.pickerUri),
        mode: LaunchMode.externalApplication,
      );
      _schedulePoll(opened.pollInterval);
    } on ProviderFailure catch (failure) {
      if (mounted) {
        setState(() => error = _readable(failure));
      }
    } catch (caught) {
      Log.warn('Unable to open the Google Photos picker: $caught');
      if (mounted) {
        setState(
          () => error =
              LocaleKeys.providers_error_generic.tr(args: ['Google Photos']),
        );
      }
    }
  }

  void _schedulePoll(Duration interval) {
    poll?.cancel();
    // Google tells us how often to ask; asking faster is how an application
    // gets rate limited.
    poll = Timer(interval, () => unawaited(_check()));
  }

  Future<void> _check() async {
    final open = session;
    final live = provider;
    if (open == null || live == null || !mounted) {
      return;
    }

    if (deadline != null && DateTime.now().isAfter(deadline!)) {
      setState(() => error = LocaleKeys.providers_photos_timedOut.tr());
      return;
    }

    try {
      final read = await live.readSession(open.id);
      if (!mounted) {
        return;
      }
      if (read.mediaItemsSet) {
        setState(() => finished = true);
        Navigator.of(context).pop(
          CollectionSource(
            service: ProviderService.googlePhotos,
            connectionId: widget.connection.id,
            remoteId: read.id,
            remoteName: LocaleKeys.providers_photos_selection.tr(),
            readOnly: true,
            lastSyncedAt: DateTime.now(),
            options: {GooglePhotosProvider.sessionOption: read.id},
          ),
        );
        return;
      }
      setState(() => session = read);
      _schedulePoll(read.pollInterval);
    } on ProviderFailure catch (failure) {
      if (mounted) {
        setState(() => error = _readable(failure));
      }
    }
  }

  String _readable(ProviderFailure failure) => switch (failure.status) {
        ProviderStatus.offline => LocaleKeys.providers_error_unreachable.tr(),
        ProviderStatus.authExpired =>
          LocaleKeys.providers_error_refused.tr(args: ['Google Photos']),
        ProviderStatus.permissionDenied =>
          LocaleKeys.providers_photos_apiDisabled.tr(),
        ProviderStatus.notFound => LocaleKeys.providers_photos_expired.tr(),
        _ => LocaleKeys.providers_error_generic.tr(args: ['Google Photos']),
      };

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
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: ProviderServices.googlePhotos.accent
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        ProviderServices.googlePhotos.icon,
                        size: 19,
                        color: ProviderServices.googlePhotos.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        LocaleKeys.providers_photos_title.tr(),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 16,
                          fontVariations: const [FontVariation.weight(640)],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                      height: 1.55,
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      if (!finished)
                        const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          LocaleKeys.providers_photos_waiting.tr(),
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    LocaleKeys.providers_photos_reopenHint.tr(),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(LocaleKeys.button_cancel.tr()),
                    ),
                    const SizedBox(width: 6),
                    if (error != null)
                      FilledButton.tonal(
                        onPressed: () => unawaited(_start()),
                        child: Text(LocaleKeys.providers_tryAgain.tr()),
                      )
                    else if (session != null)
                      FilledButton.tonal(
                        onPressed: () => unawaited(
                          launchUrl(
                            Uri.parse(session!.pickerUri),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        child: Text(LocaleKeys.providers_photos_reopen.tr()),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
