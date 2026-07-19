import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'youtube_video_download.dart';

class YoutubeEmbedPlayer extends StatefulWidget {
  const YoutubeEmbedPlayer({
    super.key,
    required this.url,
  });

  final String url;

  @override
  State<YoutubeEmbedPlayer> createState() => _YoutubeEmbedPlayerState();
}

class _YoutubeEmbedPlayerState extends State<YoutubeEmbedPlayer> {
  late final Player player;
  late final media_kit_video.VideoController controller;
  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = media_kit_video.VideoController(player);
    _load();
  }

  @override
  void didUpdateWidget(covariant YoutubeEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        hasError = false;
      });
    }

    final youtube = YoutubeExplode();
    try {
      final manifest = await youtube.videos.streams.getManifest(widget.url);
      final stream = bestYoutubeMuxedStream(manifest);
      await player.open(
        Media(
          stream.url.toString(),
          httpHeaders: const {
            'Referer': 'https://www.youtube.com/',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
        play: false,
      );
      if (mounted) {
        setState(() => isLoading = false);
      }
    } on Exception catch (error, stackTrace) {
      Log.error('Failed to load embedded YouTube video', error, stackTrace);
      if (mounted) {
        setState(() {
          isLoading = false;
          hasError = true;
        });
      }
    } finally {
      youtube.close();
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!isLoading && !hasError)
              media_kit_video.Video(controller: controller)
            else if (isLoading)
              const Center(child: CircularProgressIndicator.adaptive())
            else
              Center(
                child: TextButton.icon(
                  onPressed: _load,
                  icon: const FlowySvg(FlowySvgs.embed_error_xl),
                  label: FlowyText(
                    LocaleKeys
                        .document_plugins_linkPreview_linkPreviewMenu_unableToDisplay
                        .tr(),
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
