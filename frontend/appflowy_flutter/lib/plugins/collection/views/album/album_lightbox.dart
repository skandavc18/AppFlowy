import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_metadata.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the album at [startId], filling the window.
Future<void> showAlbumLightbox({
  required BuildContext context,
  required AlbumController controller,
  required CollectionPalette palette,
  required String startId,
  ValueChanged<AlbumMediaItem>? onOpenInWorkspace,
  bool startSlideshow = false,
  bool startWithInfo = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
    pageBuilder: (_, __, ___) => AlbumLightbox(
      controller: controller,
      palette: palette,
      startId: startId,
      onOpenInWorkspace: onOpenInWorkspace,
      startSlideshow: startSlideshow,
      startWithInfo: startWithInfo,
    ),
  );
}

class AlbumLightbox extends StatefulWidget {
  const AlbumLightbox({
    super.key,
    required this.controller,
    required this.palette,
    required this.startId,
    this.onOpenInWorkspace,
    this.startSlideshow = false,
    this.startWithInfo = false,
  });

  final AlbumController controller;
  final CollectionPalette palette;
  final String startId;
  final ValueChanged<AlbumMediaItem>? onOpenInWorkspace;
  final bool startSlideshow;
  final bool startWithInfo;

  @override
  State<AlbumLightbox> createState() => _AlbumLightboxState();
}

class _AlbumLightboxState extends State<AlbumLightbox> {
  static const _chromeIdle = Duration(seconds: 3);

  late final PageController pageController;
  late List<AlbumMediaItem> items;
  final FocusNode focusNode = FocusNode(debugLabel: 'album-lightbox');
  Timer? slideTimer;
  Timer? chromeTimer;
  bool playing = false;
  bool showInfo = false;
  bool chromeVisible = true;
  int index = 0;
  List<int>? shuffleOrder;

  @override
  void initState() {
    super.initState();
    items = widget.controller.ordered;
    index = math.max(0, items.indexWhere((item) => item.id == widget.startId));
    pageController = PageController(initialPage: index);
    widget.controller.addListener(_onControllerChanged);
    unawaited(widget.controller.ensureMetadata(items[index]));
    showInfo = widget.startWithInfo;
    if (widget.startSlideshow) {
      _setPlaying(true);
    }
    _wakeChrome();
  }

  @override
  void dispose() {
    slideTimer?.cancel();
    chromeTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    pageController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  AlbumMediaItem? get current =>
      index >= 0 && index < items.length ? items[index] : null;

  AlbumMediaMetadata get metadata {
    final item = current;
    return item == null
        ? AlbumMediaMetadata.pending
        : widget.controller.metadataFor(item);
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
          const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
          const SingleActivator(LogicalKeyboardKey.space): _togglePlaying,
          const SingleActivator(LogicalKeyboardKey.keyI): _toggleInfo,
          const SingleActivator(LogicalKeyboardKey.escape): _close,
        },
        child: Focus(
          focusNode: focusNode,
          autofocus: true,
          child: MouseRegion(
            opaque: false,
            onHover: (_) => _wakeChrome(),
            child: Row(
              children: [
                Expanded(child: _buildStage()),
                if (showInfo)
                  _AlbumInfoPanel(
                    item: current,
                    metadata: metadata,
                    palette: widget.palette,
                    onClose: _toggleInfo,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: pageController,
            itemCount: items.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, page) => _AlbumStagePage(
              item: items[page],
              transition: widget.controller.settings.slideshow.transition,
              playing: playing,
              isCurrent: page == index,
            ),
          ),
        ),
        _chrome(_buildTopBar(), alignment: Alignment.topCenter),
        _chrome(_buildBottomBar(), alignment: Alignment.bottomCenter),
        _chrome(
          _NavigationArrow(
            icon: Icons.chevron_left_rounded,
            tooltip: LocaleKeys.collections_album_previous.tr(),
            onPressed: index > 0 ? _previous : null,
          ),
          alignment: Alignment.centerLeft,
        ),
        _chrome(
          _NavigationArrow(
            icon: Icons.chevron_right_rounded,
            tooltip: LocaleKeys.collections_album_next.tr(),
            onPressed: index < items.length - 1 ? _next : null,
          ),
          alignment: Alignment.centerRight,
        ),
      ],
    );
  }

  Widget _chrome(Widget child, {required Alignment alignment}) {
    return Align(
      alignment: alignment,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        opacity: chromeVisible ? 1 : 0,
        child: IgnorePointer(ignoring: !chromeVisible, child: child),
      ),
    );
  }

  Widget _buildTopBar() {
    final item = current;
    final favourite =
        item != null && widget.controller.state.isFavourite(item.id);
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.62),
            Colors.black.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        children: [
          _LightboxButton(
            icon: Icons.close_rounded,
            tooltip: LocaleKeys.collections_album_close.tr(),
            onPressed: _close,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${index + 1} / ${items.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          _LightboxButton(
            icon: favourite ? Icons.star_rounded : Icons.star_border_rounded,
            tooltip: favourite
                ? LocaleKeys.collections_album_unfavourite.tr()
                : LocaleKeys.collections_album_favourite.tr(),
            selected: favourite,
            onPressed: item == null
                ? null
                : () => widget.controller.toggleFavourite(item.id),
          ),
          _LightboxButton(
            icon: Icons.info_outline_rounded,
            tooltip: showInfo
                ? LocaleKeys.collections_album_hideInfo.tr()
                : LocaleKeys.collections_album_info.tr(),
            selected: showInfo,
            onPressed: _toggleInfo,
          ),
          if (widget.onOpenInWorkspace != null)
            _LightboxButton(
              icon: Icons.open_in_new_rounded,
              tooltip: LocaleKeys.collections_album_openInWorkspace.tr(),
              onPressed: item == null
                  ? null
                  : () {
                      Navigator.of(context).maybePop();
                      widget.onOpenInWorkspace!(item);
                    },
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final slideshow = widget.controller.settings.slideshow;
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.62),
            Colors.black.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LightboxButton(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: playing
                ? LocaleKeys.collections_album_stopSlideshow.tr()
                : LocaleKeys.collections_album_playSlideshow.tr(),
            selected: playing,
            onPressed: _togglePlaying,
          ),
          const SizedBox(width: 6),
          _LightboxButton(
            icon: Icons.shuffle_rounded,
            tooltip: LocaleKeys.collections_album_shuffle.tr(),
            selected: slideshow.shuffle,
            onPressed: () => _updateSlideshow(
              slideshow.copyWith(shuffle: !slideshow.shuffle),
            ),
          ),
          _LightboxButton(
            icon: Icons.repeat_rounded,
            tooltip: LocaleKeys.collections_album_loop.tr(),
            selected: slideshow.loop,
            onPressed: () =>
                _updateSlideshow(slideshow.copyWith(loop: !slideshow.loop)),
          ),
          const SizedBox(width: 12),
          _IntervalStepper(
            seconds: slideshow.seconds,
            onChanged: (seconds) =>
                _updateSlideshow(slideshow.copyWith(seconds: seconds)),
          ),
          const SizedBox(width: 12),
          _TransitionPicker(
            transition: slideshow.transition,
            onChanged: (transition) =>
                _updateSlideshow(slideshow.copyWith(transition: transition)),
          ),
        ],
      ),
    );
  }

  void _updateSlideshow(AlbumSlideshowSettings slideshow) {
    widget.controller.updateSettings(
      widget.controller.settings.copyWith(slideshow: slideshow),
    );
    if (playing) {
      _restartSlideTimer();
    }
  }

  void _onPageChanged(int page) {
    setState(() => index = page);
    final item = current;
    if (item != null) {
      widget.controller.select(item.id);
      unawaited(widget.controller.ensureMetadata(item));
    }
    if (playing) {
      _restartSlideTimer();
    }
  }

  void _previous() => _goTo(index - 1);
  void _next() => _goTo(index + 1);

  void _goTo(int target) {
    if (items.isEmpty) {
      return;
    }
    final resolved = target < 0
        ? (widget.controller.settings.slideshow.loop ? items.length - 1 : 0)
        : target >= items.length
            ? (widget.controller.settings.slideshow.loop
                ? 0
                : items.length - 1)
            : target;
    if (resolved == index) {
      return;
    }
    unawaited(
      pageController.animateToPage(
        resolved,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _advanceSlide() {
    if (items.isEmpty) {
      return;
    }
    if (widget.controller.settings.slideshow.shuffle) {
      final order = shuffleOrder ??= _buildShuffleOrder();
      final position = order.indexOf(index);
      final next = order[(position + 1) % order.length];
      _goTo(next);
      return;
    }
    if (index >= items.length - 1 &&
        !widget.controller.settings.slideshow.loop) {
      _setPlaying(false);
      return;
    }
    _goTo(index + 1);
  }

  List<int> _buildShuffleOrder() {
    final order = List<int>.generate(items.length, (index) => index)..shuffle();
    // Start from wherever the reader already is.
    final position = order.indexOf(index);
    if (position > 0) {
      order
        ..removeAt(position)
        ..insert(0, index);
    }
    return order;
  }

  void _togglePlaying() => _setPlaying(!playing);

  void _setPlaying(bool value) {
    setState(() {
      playing = value;
      shuffleOrder = null;
    });
    if (value) {
      _restartSlideTimer();
    } else {
      slideTimer?.cancel();
      slideTimer = null;
      _wakeChrome();
    }
  }

  void _restartSlideTimer() {
    slideTimer?.cancel();
    slideTimer = Timer.periodic(
      widget.controller.settings.slideshow.interval,
      (_) => _advanceSlide(),
    );
  }

  void _toggleInfo() {
    setState(() => showInfo = !showInfo);
    _wakeChrome();
  }

  void _close() => unawaited(Navigator.of(context).maybePop());

  void _wakeChrome() {
    chromeTimer?.cancel();
    if (!chromeVisible) {
      setState(() => chromeVisible = true);
    }
    chromeTimer = Timer(_chromeIdle, () {
      if (mounted && !showInfo) {
        setState(() => chromeVisible = false);
      }
    });
  }
}

class _AlbumStagePage extends StatelessWidget {
  const _AlbumStagePage({
    required this.item,
    required this.transition,
    required this.playing,
    required this.isCurrent,
  });

  final AlbumMediaItem item;
  final AlbumSlideshowTransition transition;
  final bool playing;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final child = item.kind == AlbumMediaKind.image
        ? _buildPicture()
        : Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: item.kind == AlbumMediaKind.audio ? 560 : 1180,
              ),
              child: FileMediaPlayer(
                key: ValueKey('album-player-${item.id}'),
                url: item.path,
                name: item.name,
                kind: item.kind == AlbumMediaKind.audio
                    ? FileMediaKind.audio
                    : FileMediaKind.video,
              ),
            ),
          );
    if (!playing || !isCurrent || transition != AlbumSlideshowTransition.zoom) {
      return child;
    }
    // A slow drift gives a slideshow its life; it is only worth running on
    // the slide actually being shown.
    return TweenAnimationBuilder<double>(
      key: ValueKey('album-zoom-${item.id}'),
      tween: Tween(begin: 1, end: 1.08),
      duration: const Duration(seconds: 12),
      builder: (context, scale, leaf) =>
          Transform.scale(scale: scale, child: leaf),
      child: child,
    );  }

  Widget _buildPicture() {
    if (!item.isLocal) {
      return const Center(
        child: Icon(Icons.cloud_off_rounded, size: 32, color: Colors.white38),
      );
    }
    return Center(
      child: InteractiveViewer(
        maxScale: 6,
        child: Image.file(
          File(item.path),
          errorBuilder: (context, _, __) => const Icon(
            Icons.broken_image_rounded,
            size: 32,
            color: Colors.white38,
          ),
        ),
      ),
    );
  }
}

class _AlbumInfoPanel extends StatelessWidget {
  const _AlbumInfoPanel({
    required this.item,
    required this.metadata,
    required this.palette,
    required this.onClose,
  });

  final AlbumMediaItem? item;
  final AlbumMediaMetadata metadata;
  final CollectionPalette palette;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final exif = metadata.exif;
    final rows = <(String, String)>[
      if (metadata.capturedAt != null)
        (
          LocaleKeys.collections_album_taken.tr(),
          DateFormat.yMMMMd().add_jm().format(metadata.capturedAt!),
        ),
      if (exif.cameraName != null)
        (LocaleKeys.collections_album_camera.tr(), exif.cameraName!),
      if (exif.lens != null)
        (LocaleKeys.collections_album_lens.tr(), exif.lens!),
      if (exif.exposureSummary != null)
        (LocaleKeys.collections_album_exposure.tr(), exif.exposureSummary!),
      if (metadata.dimensionsLabel != null)
        (
          LocaleKeys.collections_album_dimensions.tr(),
          metadata.dimensionsLabel!,
        ),
      if (metadata.byteSize != null)
        (
          LocaleKeys.collections_album_fileSize.tr(),
          albumFileSizeLabel(metadata.byteSize!),
        ),
    ];

    return Container(
      width: 306,
      color: const Color(0xFF15171A),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleKeys.collections_album_info.tr(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _LightboxButton(
                  icon: Icons.close_rounded,
                  tooltip: LocaleKeys.collections_album_close.tr(),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (item != null)
              Text(
                item!.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              Text(
                LocaleKeys.collections_album_noExif.tr(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  height: 1.5,
                ),
              )
            else
              for (final row in rows) _InfoRow(label: row.$1, value: row.$2),
            if (exif.hasLocation) ...[
              const SizedBox(height: 18),
              _LocationSection(
                latitude: exif.latitude!,
                longitude: exif.longitude!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 9.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationSection extends StatelessWidget {
  const _LocationSection({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  String get _label =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoRow(
          label: LocaleKeys.collections_album_location.tr(),
          value: _label,
        ),
        Row(
          children: [
            _TextAction(
              label: LocaleKeys.collections_album_copyCoordinates.tr(),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: _label));
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text(
                        LocaleKeys.collections_album_coordinatesCopied.tr(),
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 14),
            _TextAction(
              label: LocaleKeys.collections_album_openInMaps.tr(),
              onTap: () => unawaited(
                launchUrl(
                  Uri.parse(
                    'https://www.openstreetmap.org/?mlat=$latitude&mlon=$longitude#map=15/$latitude/$longitude',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF89B0F5),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LightboxButton extends StatefulWidget {
  const _LightboxButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  State<_LightboxButton> createState() => _LightboxButtonState();
}

class _LightboxButtonState extends State<_LightboxButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? Colors.white.withValues(alpha: 0.28)
        : widget.selected
            ? const Color(0xFF89B0F5)
            : Colors.white.withValues(alpha: hovered ? 1 : 0.78);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: hovered && enabled
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(widget.icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _NavigationArrow extends StatelessWidget {
  const _NavigationArrow({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: _LightboxButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

class _IntervalStepper extends StatelessWidget {
  const _IntervalStepper({required this.seconds, required this.onChanged});

  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LightboxButton(
          icon: Icons.remove_rounded,
          tooltip: LocaleKeys.collections_album_secondsPerSlide.tr(),
          onPressed: seconds > AlbumSlideshowSettings.minimumSeconds
              ? () => onChanged(seconds - 1)
              : null,
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${seconds}s',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
            ),
          ),
        ),
        _LightboxButton(
          icon: Icons.add_rounded,
          tooltip: LocaleKeys.collections_album_secondsPerSlide.tr(),
          onPressed: seconds < AlbumSlideshowSettings.maximumSeconds
              ? () => onChanged(seconds + 1)
              : null,
        ),
      ],
    );
  }
}

class _TransitionPicker extends StatelessWidget {
  const _TransitionPicker({
    required this.transition,
    required this.onChanged,
  });

  final AlbumSlideshowTransition transition;
  final ValueChanged<AlbumSlideshowTransition> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final value in AlbumSlideshowTransition.values)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: value == transition
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    albumTransitionLabel(value),
                    style: TextStyle(
                      color: Colors.white
                          .withValues(alpha: value == transition ? 1 : 0.6),
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
