import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// How far the rewind and fast forward buttons jump.
const videoSeekStep = Duration(seconds: 5);

/// The speeds offered in the settings menu.
const videoPlaybackSpeeds = <double>[0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

/// How long the chrome stays up after the last interaction.
const _chromeIdleDelay = Duration(milliseconds: 2600);

const _fade = Duration(milliseconds: 160);

/// A resolution the video can be played back in, e.g. `1080p`.
@immutable
class VideoQualityOption {
  const VideoQualityOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// `0:09`, or `1:02:09` once the video runs past an hour.
String formatVideoDuration(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final minutes = total.inMinutes.remainder(60).toString();
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (total.inHours == 0) {
    return '$minutes:$seconds';
  }
  return '${total.inHours}:${minutes.padLeft(2, '0')}:$seconds';
}

/// `Normal` at 1x, `1.5×` otherwise.
String formatPlaybackSpeed(double speed) {
  if (speed == 1) {
    return LocaleKeys.document_plugins_video_normalSpeed.tr();
  }
  final trimmed = speed.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  return '$trimmed×';
}

/// YouTube-style chrome for a [Player]: a play button in the middle of the
/// picture and a control bar that fades in over the bottom edge.
///
/// Rendered on top of the video, so it is laid out by the caller's `Stack`.
class VideoPlayerControls extends StatefulWidget {
  const VideoPlayerControls({
    super.key,
    required this.player,
    this.qualities = const [],
    this.selectedQualityId,
    this.onQualitySelected,
  });

  final Player player;

  /// Resolutions to offer in the settings menu. The menu section is hidden
  /// when there is nothing to choose between.
  final List<VideoQualityOption> qualities;
  final String? selectedQualityId;
  final ValueChanged<String>? onQualitySelected;

  @override
  State<VideoPlayerControls> createState() => _VideoPlayerControlsState();
}

class _VideoPlayerControlsState extends State<VideoPlayerControls> {
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _idleTimer;

  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  double _speed = 1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

  bool _chromeVisible = true;
  bool _scrubbing = false;
  _SettingsPage? _settingsPage;

  Player get _player => widget.player;

  bool get _chromePinned =>
      !_playing || _scrubbing || _settingsPage != null || _buffering;

  @override
  void initState() {
    super.initState();
    _playing = _player.state.playing;
    _buffering = _player.state.buffering;
    _completed = _player.state.completed;
    _speed = _player.state.rate;
    _position = _player.state.position;
    _duration = _player.state.duration;
    _buffer = _player.state.buffer;
    _subscriptions.addAll([
      _player.stream.playing.listen((value) => _update(() => _playing = value)),
      _player.stream.buffering
          .listen((value) => _update(() => _buffering = value)),
      _player.stream.completed
          .listen((value) => _update(() => _completed = value)),
      _player.stream.rate.listen((value) => _update(() => _speed = value)),
      // While the bar is being dragged it shows where the drag is, not where
      // playback still is.
      _player.stream.position.listen((value) {
        if (!_scrubbing) {
          _update(() => _position = value);
        }
      }),
      _player.stream.duration
          .listen((value) => _update(() => _duration = value)),
      _player.stream.buffer.listen((value) => _update(() => _buffer = value)),
    ]);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (!mounted) {
      return;
    }
    setState(change);
  }

  void _revealChrome() {
    _idleTimer?.cancel();
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
    }
    if (_chromePinned) {
      return;
    }
    _idleTimer = Timer(_chromeIdleDelay, () {
      if (mounted && !_chromePinned) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  void _hideChrome() {
    _idleTimer?.cancel();
    if (_chromeVisible && !_chromePinned) {
      setState(() => _chromeVisible = false);
    }
  }

  Future<void> _togglePlayback() async {
    _revealChrome();
    if (_completed) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    await _player.playOrPause();
  }

  Future<void> _seekBy(Duration step) async {
    _revealChrome();
    final target = _position + step;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && target > _duration
            ? _duration
            : target);
    await _player.seek(clamped);
  }

  Future<void> _seekToFraction(double fraction) async {
    if (_duration <= Duration.zero) {
      return;
    }
    await _player.seek(_duration * fraction.clamp(0.0, 1.0));
  }

  void _openSettings() {
    setState(
      () => _settingsPage = _settingsPage == null ? _SettingsPage.root : null,
    );
    _revealChrome();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(context);
    final visible = _chromeVisible || _chromePinned;
    return MouseRegion(
      opaque: false,
      onEnter: (_) => _revealChrome(),
      onHover: (_) => _revealChrome(),
      onExit: (_) => _hideChrome(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_settingsPage != null) {
                setState(() => _settingsPage = null);
                return;
              }
              _togglePlayback();
            },
            child: const SizedBox.expand(),
          ),
          Center(child: _buildCenterButton()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: _fade,
                child: _buildControlBar(accent),
              ),
            ),
          ),
          if (_settingsPage != null)
            Positioned(
              right: 12,
              bottom: 68,
              child: _SettingsPanel(
                page: _settingsPage!,
                speed: _speed,
                qualities: widget.qualities,
                selectedQualityId: widget.selectedQualityId,
                onPageChanged: (page) => setState(() => _settingsPage = page),
                onSpeedSelected: (speed) {
                  _player.setRate(speed);
                  setState(() => _settingsPage = null);
                },
                onQualitySelected: (id) {
                  widget.onQualitySelected?.call(id);
                  setState(() => _settingsPage = null);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterButton() {
    if (_buffering) {
      return const SizedBox.square(
        dimension: 44,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: Colors.white,
        ),
      );
    }

    final showing = !_playing;
    return IgnorePointer(
      ignoring: !showing,
      child: AnimatedScale(
        scale: showing ? 1 : 0.7,
        duration: _fade,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: showing ? 1 : 0,
          duration: _fade,
          child: _CircleButton(
            icon: _completed ? Icons.replay_rounded : Icons.play_arrow_rounded,
            tooltip: LocaleKeys.document_plugins_video_play.tr(),
            onPressed: _togglePlayback,
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar(Color accent) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Color(0x99000000),
            Color(0xD9000000),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 24, 10, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SeekBar(
              position: _position,
              duration: _duration,
              buffer: _buffer,
              accent: accent,
              onScrubStart: () => setState(() => _scrubbing = true),
              onScrubUpdate: (fraction) {
                if (_duration > Duration.zero) {
                  setState(() => _position = _duration * fraction);
                }
                _revealChrome();
              },
              onScrubEnd: (fraction) {
                setState(() => _scrubbing = false);
                _seekToFraction(fraction);
                _revealChrome();
              },
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _BarButton(
                  icon: Icons.replay_5_rounded,
                  tooltip: LocaleKeys.document_plugins_video_rewind.tr(),
                  onPressed: () => _seekBy(-videoSeekStep),
                ),
                _BarButton(
                  icon: _completed
                      ? Icons.replay_rounded
                      : _playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                  tooltip: _playing
                      ? LocaleKeys.document_plugins_video_pause.tr()
                      : LocaleKeys.document_plugins_video_play.tr(),
                  onPressed: _togglePlayback,
                ),
                _BarButton(
                  icon: Icons.forward_5_rounded,
                  tooltip: LocaleKeys.document_plugins_video_fastForward.tr(),
                  onPressed: () => _seekBy(videoSeekStep),
                ),
                const SizedBox(width: 6),
                Text(
                  '${formatVideoDuration(_position)} / '
                  '${formatVideoDuration(_duration)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                _BarButton(
                  icon: Icons.settings_rounded,
                  tooltip: LocaleKeys.document_plugins_video_settings.tr(),
                  selected: _settingsPage != null,
                  onPressed: _openSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the played portion of the seek bar readable on the black picture,
/// whatever the theme's primary happens to be.
Color _accentColor(BuildContext context) {
  final primary = Theme.of(context).colorScheme.primary;
  return primary.computeLuminance() < 0.25 ? Colors.white : primary;
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.buffer,
    required this.accent,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  final Duration position;
  final Duration duration;
  final Duration buffer;
  final Color accent;
  final VoidCallback onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  bool _hovering = false;
  bool _dragging = false;

  double get _progress => _fractionOf(widget.position);
  double get _buffered => _fractionOf(widget.buffer);

  double _fractionOf(Duration value) {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) {
      return 0;
    }
    return (value.inMilliseconds / total).clamp(0.0, 1.0);
  }

  double _fractionAt(double dx, double width) =>
      width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final expanded = _hovering || _dragging;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                widget.onScrubEnd(_fractionAt(details.localPosition.dx, width)),
            onHorizontalDragStart: (details) {
              setState(() => _dragging = true);
              widget.onScrubStart();
              widget.onScrubUpdate(
                _fractionAt(details.localPosition.dx, width),
              );
            },
            onHorizontalDragUpdate: (details) => widget.onScrubUpdate(
              _fractionAt(details.localPosition.dx, width),
            ),
            onHorizontalDragEnd: (_) {
              setState(() => _dragging = false);
              widget.onScrubEnd(_progress);
            },
            onHorizontalDragCancel: () {
              setState(() => _dragging = false);
              widget.onScrubEnd(_progress);
            },
            child: SizedBox(
              height: 16,
              child: Center(
                child: AnimatedContainer(
                  duration: _fade,
                  height: expanded ? 5 : 3,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _track(width, 1, Colors.white.withValues(alpha: 0.24)),
                      _track(
                        width,
                        _buffered,
                        Colors.white.withValues(alpha: 0.42),
                      ),
                      _track(width, _progress, widget.accent),
                      Positioned(
                        left: (width * _progress) - 6,
                        top: expanded ? -3.5 : -4.5,
                        child: AnimatedScale(
                          duration: _fade,
                          scale: expanded ? 1 : 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: widget.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _track(double width, double fraction, Color color) => Container(
        width: width * fraction,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      );
}

class _CircleButton extends StatefulWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: _fade,
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: _hovering ? 0.72 : 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(widget.icon, color: Colors.white, size: 34),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _hovering || widget.selected;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: _fade,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: highlighted ? 0.16 : 0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

enum _SettingsPage { root, speed, quality }

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.page,
    required this.speed,
    required this.qualities,
    required this.selectedQualityId,
    required this.onPageChanged,
    required this.onSpeedSelected,
    required this.onQualitySelected,
  });

  final _SettingsPage page;
  final double speed;
  final List<VideoQualityOption> qualities;
  final String? selectedQualityId;
  final ValueChanged<_SettingsPage> onPageChanged;
  final ValueChanged<double> onSpeedSelected;
  final ValueChanged<String> onQualitySelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 232,
        constraints: const BoxConstraints(maxHeight: 232),
        decoration: BoxDecoration(
          color: const Color(0xF01A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: _fade,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: switch (page) {
            _SettingsPage.root => _buildRoot(),
            _SettingsPage.speed => _buildSpeed(),
            _SettingsPage.quality => _buildQuality(),
          },
        ),
      ),
    );
  }

  Widget _buildRoot() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SettingsRow(
          icon: Icons.slow_motion_video_rounded,
          label: LocaleKeys.document_plugins_video_playbackSpeed.tr(),
          value: formatPlaybackSpeed(speed),
          onTap: () => onPageChanged(_SettingsPage.speed),
        ),
        // A single resolution is not a choice, so it is not offered as one.
        if (qualities.length > 1)
          _SettingsRow(
            icon: Icons.hd_rounded,
            label: LocaleKeys.document_plugins_video_quality.tr(),
            value: _selectedQualityLabel,
            onTap: () => onPageChanged(_SettingsPage.quality),
          ),
      ],
    );
  }

  String get _selectedQualityLabel {
    for (final quality in qualities) {
      if (quality.id == selectedQualityId) {
        return quality.label;
      }
    }
    return '';
  }

  Widget _buildSpeed() {
    return _SettingsList(
      title: LocaleKeys.document_plugins_video_playbackSpeed.tr(),
      onBack: () => onPageChanged(_SettingsPage.root),
      children: [
        for (final option in videoPlaybackSpeeds)
          _SettingsOption(
            label: formatPlaybackSpeed(option),
            selected: option == speed,
            onTap: () => onSpeedSelected(option),
          ),
      ],
    );
  }

  Widget _buildQuality() {
    return _SettingsList(
      title: LocaleKeys.document_plugins_video_quality.tr(),
      onBack: () => onPageChanged(_SettingsPage.root),
      children: [
        for (final option in qualities)
          _SettingsOption(
            label: option.label,
            selected: option.id == selectedQualityId,
            onTap: () => onQualitySelected(option.id),
          ),
      ],
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({
    required this.title,
    required this.onBack,
    required this.children,
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onBack,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.62),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsOption extends StatelessWidget {
  const _SettingsOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
