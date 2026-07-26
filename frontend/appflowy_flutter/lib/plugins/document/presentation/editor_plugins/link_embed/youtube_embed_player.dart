import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/video_player_controls.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'youtube_video_download.dart';

const _youtubeStreamHeaders = {
  'Referer': 'https://www.youtube.com/',
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
};

/// The frame to use before the decoder reports the real dimensions.
///
/// Shorts are known to be portrait from their URL alone, so they never have to
/// start out letterboxed.
double initialYoutubeAspectRatio(String url) => isYoutubeShortsUrl(url)
    ? portraitVideoAspectRatio
    : defaultVideoAspectRatio;

/// One playable resolution of a YouTube video.
///
/// Only muxed streams qualify. YouTube answers its adaptive (video-only and
/// audio-only) URLs with `403` unless the request asks for a bounded byte range
/// that continues exactly where the previous one stopped — players ask for an
/// open-ended range and cannot seek that way, so those streams would only ever
/// show a black picture.
@immutable
class YoutubeStreamQuality {
  const YoutubeStreamQuality({
    required this.option,
    required this.videoUrl,
  });

  final VideoQualityOption option;
  final String videoUrl;

  int get height => int.tryParse(option.id) ?? 0;
}

/// The resolutions [manifest] can be played back in, best first.
///
/// Streams are keyed by their shortest side, which is the resolution people
/// know them by and which stays correct for portrait videos, rather than by
/// YouTube's quality label — that one disagrees with the actual frame size on
/// some streams.
List<YoutubeStreamQuality> youtubeStreamQualities(StreamManifest manifest) {
  final byHeight = <int, YoutubeStreamQuality>{};

  for (final stream in manifest.muxed) {
    final resolution = stream.videoResolution;
    final height = resolution.width < resolution.height
        ? resolution.width
        : resolution.height;
    if (height <= 0) {
      continue;
    }
    byHeight.putIfAbsent(
      height,
      () => YoutubeStreamQuality(
        option: VideoQualityOption(id: '$height', label: '${height}p'),
        videoUrl: stream.url.toString(),
      ),
    );
  }

  final qualities = byHeight.values.toList()
    ..sort((a, b) => b.height.compareTo(a.height));
  return qualities;
}

class YoutubeEmbedPlayer extends StatefulWidget {
  const YoutubeEmbedPlayer({
    super.key,
    required this.url,
    this.onAspectRatioChanged,
  });

  final String url;

  /// Called with the real aspect ratio once the video has been probed, so the
  /// host can give portrait clips a frame that fits them.
  final ValueChanged<double>? onAspectRatioChanged;

  @override
  State<YoutubeEmbedPlayer> createState() => _YoutubeEmbedPlayerState();
}

class _YoutubeEmbedPlayerState extends State<YoutubeEmbedPlayer> {
  late final Player player;
  late final media_kit_video.VideoController controller;
  StreamSubscription<VideoParams>? videoParamsSubscription;
  StreamSubscription<String>? errorSubscription;
  late double aspectRatio = initialYoutubeAspectRatio(widget.url);
  List<YoutubeStreamQuality> qualities = const [];
  String? selectedQualityId;
  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = media_kit_video.VideoController(player);
    videoParamsSubscription =
        player.stream.videoParams.listen(_handleVideoParams);
    errorSubscription = player.stream.error.listen(
      (error) => Log.error('YouTube playback failed: $error'),
    );
    _load();
  }

  @override
  void didUpdateWidget(covariant YoutubeEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      aspectRatio = initialYoutubeAspectRatio(widget.url);
      _load();
    }
  }

  void _handleVideoParams(VideoParams params) {
    final ratio = videoAspectRatioOf(params);
    if (ratio == null || ratio == aspectRatio || !mounted) {
      return;
    }
    setState(() => aspectRatio = ratio);
    widget.onAspectRatioChanged?.call(ratio);
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
      final manifest = await youtube.videos.streams.getManifest(
        youtubeVideoId(widget.url) ?? widget.url,
      );
      final stream = bestYoutubeMuxedStream(manifest);
      final resolution = stream.videoResolution;
      final defaultHeight = resolution.width < resolution.height
          ? resolution.width
          : resolution.height;
      await player.open(
        Media(stream.url.toString(), httpHeaders: _youtubeStreamHeaders),
        play: false,
      );
      if (mounted) {
        setState(() {
          qualities = youtubeStreamQualities(manifest);
          selectedQualityId = '$defaultHeight';
          isLoading = false;
        });
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

  /// Reopens the video at another resolution, picking up where it left off.
  Future<void> _selectQuality(String id) async {
    if (id == selectedQualityId) {
      return;
    }
    YoutubeStreamQuality? quality;
    for (final candidate in qualities) {
      if (candidate.option.id == id) {
        quality = candidate;
        break;
      }
    }
    if (quality == null) {
      return;
    }

    final previous = selectedQualityId;
    final position = player.state.position;
    final wasPlaying = player.state.playing;
    setState(() => selectedQualityId = id);
    try {
      await player.open(
        Media(quality.videoUrl, httpHeaders: _youtubeStreamHeaders),
        play: false,
      );
      await player.seek(position);
      if (wasPlaying) {
        await player.play();
      }
    } on Exception catch (error, stackTrace) {
      Log.error('Failed to switch YouTube video quality', error, stackTrace);
      if (mounted) {
        setState(() => selectedQualityId = previous);
      }
    }
  }

  @override
  void dispose() {
    videoParamsSubscription?.cancel();
    errorSubscription?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!isLoading && !hasError) ...[
                media_kit_video.Video(
                  controller: controller,
                  controls: media_kit_video.NoVideoControls,
                ),
                VideoPlayerControls(
                  player: player,
                  qualities: [
                    for (final quality in qualities) quality.option,
                  ],
                  selectedQualityId: selectedQualityId,
                  onQualitySelected: _selectQuality,
                ),
              ] else if (isLoading)
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
      ),
    );
  }
}
