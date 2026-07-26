import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
  });

  final String url;
  final String name;
  final FileMediaKind kind;

  @override
  State<FileMediaPlayer> createState() => _FileMediaPlayerState();
}

class _FileMediaPlayerState extends State<FileMediaPlayer> {
  late final Player player;
  VideoController? videoController;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant FileMediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.kind != widget.kind) {
      if (widget.kind == FileMediaKind.video && videoController == null) {
        videoController = VideoController(player);
      }
      player.open(Media(widget.url), play: false);
    }
  }

  void _initializePlayer() {
    player = Player();
    if (widget.kind == FileMediaKind.video) {
      videoController = VideoController(player);
    }
    player.open(Media(widget.url), play: false);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kind == FileMediaKind.video) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: EditorSurfaceStyle.embedBorderRadius,
          boxShadow: EditorSurfaceStyle.embedShadow(context),
        ),
        child: ClipRRect(
          borderRadius: EditorSurfaceStyle.embedBorderRadius,
          child: ColoredBox(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: videoController!),
            ),
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
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.fillColorScheme.content,
        border: Border.all(color: EditorSurfaceStyle.embedBorder(context)),
        borderRadius: EditorSurfaceStyle.embedBorderRadius,
        boxShadow: EditorSurfaceStyle.embedShadow(context),
      ),
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
                        final position = positionSnapshot.data ?? Duration.zero;
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
    );
  }
}
