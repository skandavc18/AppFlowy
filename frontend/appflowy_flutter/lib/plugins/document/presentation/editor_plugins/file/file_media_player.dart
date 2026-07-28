import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/media/video_player_controls.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Videos are framed as widescreen until the decoder reports their real size.
const defaultVideoAspectRatio = 16 / 9;

/// The ratio portrait clips are shot in, YouTube Shorts included.
const portraitVideoAspectRatio = 9 / 16;

/// The display aspect ratio of the open video, or null while it is unknown.
///
/// The display size already accounts for rotation and non-square pixels, so it
/// is preferred over the raw frame size.
double? videoAspectRatioOf(VideoParams params) {
  final width = params.dw ?? params.w;
  final height = params.dh ?? params.h;
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  return width / height;
}

enum FileMediaKind {
  audio,
  video,
}

FileMediaKind? fileMediaKind(String? name, String? url) {
  for (final value in [name, url]) {
    if (value == null || value.isEmpty) {
      continue;
    }
    final path = Uri.tryParse(value)?.path ?? value;
    if (videoExtensionRegex.hasMatch(path.toLowerCase())) {
      return FileMediaKind.video;
    }
    if (audioExtensionRegex.hasMatch(path.toLowerCase())) {
      return FileMediaKind.audio;
    }
  }
  return null;
}

class FileMediaPlayer extends StatefulWidget {
  const FileMediaPlayer({
    super.key,
    required this.url,
    required this.name,
    required this.kind,
    this.httpHeaders = const {},
    this.onAspectRatioChanged,
  });

  final String url;
  final String name;
  final FileMediaKind kind;
  final Map<String, String> httpHeaders;

  /// Called with the real aspect ratio once the video has been probed, so the
  /// host can give portrait clips a frame that fits them.
  final ValueChanged<double>? onAspectRatioChanged;

  @override
  State<FileMediaPlayer> createState() => _FileMediaPlayerState();
}

class _FileMediaPlayerState extends State<FileMediaPlayer> {
  late final Player player;
  VideoController? videoController;
  StreamSubscription<VideoParams>? videoParamsSubscription;
  double? aspectRatio;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant FileMediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.kind != widget.kind ||
        !mapEquals(oldWidget.httpHeaders, widget.httpHeaders)) {
      if (widget.kind == FileMediaKind.video && videoController == null) {
        videoController = VideoController(player);
        videoParamsSubscription ??=
            player.stream.videoParams.listen(_handleVideoParams);
      }
      player.open(
        Media(widget.url, httpHeaders: widget.httpHeaders),
        play: false,
      );
    }
  }

  void _initializePlayer() {
    player = Player();
    if (widget.kind == FileMediaKind.video) {
      videoController = VideoController(player);
      videoParamsSubscription =
          player.stream.videoParams.listen(_handleVideoParams);
    }
    player.open(
      Media(widget.url, httpHeaders: widget.httpHeaders),
      play: false,
    );
  }

  void _handleVideoParams(VideoParams params) {
    final ratio = videoAspectRatioOf(params);
    if (ratio == null || ratio == aspectRatio || !mounted) {
      return;
    }
    setState(() => aspectRatio = ratio);
    widget.onAspectRatioChanged?.call(ratio);
  }

  @override
  void dispose() {
    videoParamsSubscription?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == FileMediaKind.video) {
      return ViewerCard(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: aspectRatio ?? defaultVideoAspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: videoController!,
                controls: NoVideoControls,
              ),
              VideoPlayerControls(player: player),
            ],
          ),
        ),
      );
    }

    return _AudioPlayer(player: player, name: widget.name);
  }
}

class _AudioPlayer extends StatelessWidget {
  const _AudioPlayer({
    required this.player,
    required this.name,
  });

  final Player player;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return ViewerCard(
      color: theme.fillColorScheme.content,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing,
              builder: (context, snapshot) => IconButton(
                onPressed: player.playOrPause,
                icon: Icon(
                  snapshot.data == true ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ),
            const HSpace(8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FlowyText(
                    name,
                    overflow: TextOverflow.ellipsis,
                  ),
                  StreamBuilder<Duration>(
                    stream: player.stream.duration,
                    initialData: player.state.duration,
                    builder: (context, durationSnapshot) {
                      final duration = durationSnapshot.data ?? Duration.zero;
                      return StreamBuilder<Duration>(
                        stream: player.stream.position,
                        initialData: player.state.position,
                        builder: (context, positionSnapshot) {
                          final position =
                              positionSnapshot.data ?? Duration.zero;
                          final maximum = duration.inMilliseconds
                              .toDouble()
                              .clamp(1.0, double.infinity)
                              .toDouble();
                          return Slider(
                            max: maximum,
                            value: position.inMilliseconds
                                .toDouble()
                                .clamp(0.0, maximum)
                                .toDouble(),
                            onChanged: (value) => player.seek(
                              Duration(milliseconds: value.round()),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
