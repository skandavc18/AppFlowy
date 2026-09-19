import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_metadata.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:appflowy/workspace/application/providers/provider_view_factory.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// An optional host bridge for provider-backed items, called only on Copy/Share.
///
/// The host must resolve the ORIGINAL using its provider's own connection and
/// keep the local file alive until the action finishes. Return null if only a
/// thumbnail or display rendition is available. In particular, Google Photos'
/// materialize path can be a transcoded JPEG, so it is not unconditionally an
/// original-file resolver. No workspace profile or bearer is passed here.
typedef AlbumOriginalFileResolver = Future<File?> Function(AlbumMediaItem item);

/// Opens the album at [startId], filling the window.
Future<void> showAlbumLightbox({
  required BuildContext context,
  required AlbumController controller,
  required CollectionPalette palette,
  required String startId,
  ValueChanged<AlbumMediaItem>? onOpenInWorkspace,
  bool startSlideshow = false,
  bool startWithInfo = false,
  MediaActionService mediaActions = const MediaActionService(),
  AlbumOriginalFileResolver? resolveOriginalFile,
}) {
  // A dialog is outside the caller's page providers. Carry the live bloc, not a
  // profile snapshot, so cloud actions see renewal/sign-out while it is open.
  final workspace = context.read<UserWorkspaceBloc?>();
  return showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: child,
    ),
    pageBuilder: (_, __, ___) {
      final lightbox = AlbumLightbox(
        controller: controller,
        palette: palette,
        startId: startId,
        onOpenInWorkspace: onOpenInWorkspace,
        startSlideshow: startSlideshow,
        startWithInfo: startWithInfo,
        mediaActions: mediaActions,
        resolveOriginalFile: resolveOriginalFile,
      );
      return workspace == null
          ? lightbox
          : BlocProvider<UserWorkspaceBloc>.value(
              value: workspace,
              child: lightbox,
            );
    },
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
    this.mediaActions = const MediaActionService(),
    this.resolveOriginalFile,
  });

  final AlbumController controller;
  final CollectionPalette palette;
  final String startId;
  final ValueChanged<AlbumMediaItem>? onOpenInWorkspace;
  final bool startSlideshow;
  final bool startWithInfo;
  final MediaActionService mediaActions;
  final AlbumOriginalFileResolver? resolveOriginalFile;

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
  bool mediaActionActive = false;
  bool mediaActionFailed = false;
  Object? _mediaActionIdentity;
  MediaActionService? _mediaActions;
  int index = 0;
  List<int>? shuffleOrder;

  @override
  void initState() {
    super.initState();
    items = widget.controller.ordered;
    index = math.max(0, items.indexWhere((item) => item.id == widget.startId));
    pageController = PageController(initialPage: index);
    widget.controller.addListener(_onControllerChanged);
    if (items.isNotEmpty) {
      unawaited(widget.controller.ensureMetadata(items[index]));
    }
    showInfo = widget.startWithInfo;
    if (widget.startSlideshow) {
      _setPlaying(true);
    }
    _wakeChrome();
  }

  @override
  void didUpdateWidget(covariant AlbumLightbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      items = widget.controller.ordered;
      index =
          math.max(0, items.indexWhere((item) => item.id == widget.startId));
      shuffleOrder = null;
      final controller = widget.controller;
      final page = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(controller, widget.controller) &&
            pageController.hasClients &&
            items.isNotEmpty) {
          pageController.jumpToPage(page);
        }
      });
      final item = current;
      if (item != null) unawaited(controller.ensureMetadata(item));
      if (playing) _restartSlideTimer();
    }
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
    // Keep slideshow order stable, but adopt refreshed paths/names (a hosted
    // thumbnail can become local while this dialog is already open).
    final live = {for (final item in widget.controller.items) item.id: item};
    setState(() {
      items = [for (final item in items) live[item.id] ?? item];
    });
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
      // Only chrome descendants keep their strip revealed. The autofocus root
      // sits outside, so the ordinary three-second idle behavior still works.
      child: MediaActionReveal(
        visible: chromeVisible || mediaActionActive || mediaActionFailed,
        child: child,
      ),
    );
  }

  Widget _buildTopBar() {
    final item = current;
    final favourite =
        item != null && widget.controller.state.isFavourite(item.id);
    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(vertical: 6),
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
                    mainAxisSize: MainAxisSize.min,
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
                  icon: favourite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
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
          ),
          if (item != null)
            Padding(
              key: const ValueKey('album-media-actions'),
              padding: EdgeInsets.only(
                top: MediaQuery.textScalerOf(context).scale(10) * 1.2 + 10,
                bottom: 6,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Shortcuts(
                  // The reader's Space shortcut must not steal native button
                  // activation. Other keys still reach the lightbox normally.
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  },
                  child: _buildMediaActions(item),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaActions(AlbumMediaItem item) {
    final profile = context.select<UserWorkspaceBloc?, UserProfilePB?>(
      (bloc) => bloc?.state.userProfile,
    );
    final identity = _actionIdentity(item, profile);
    final source = _mediaSource(item, profile);
    if (_mediaActionIdentity != identity) {
      _mediaActionIdentity = identity;
      final wasFailed = mediaActionFailed;
      mediaActionFailed = false;
      // Failure pins already-visible chrome. A new target releases that pin
      // and starts a fresh idle period; ordinary slideshow changes do not wake.
      if (wasFailed) _wakeChrome();
      // A ViewPB is mutable even though AlbumMediaItem is immutable. Freeze a
      // private copy before a resolver can suspend and observe a later rename.
      final snapshot = AlbumMediaItem(
        view: ViewPB()
          ..mergeFromMessage(item.view)
          ..freeze(),
        kind: item.kind,
        path: item.path,
        index: item.index,
        byteSize: item.byteSize,
        modifiedAt: item.modifiedAt,
        unavailable: item.unavailable,
      );
      _mediaActions = _LightboxMediaActions(
        delegate: widget.mediaActions,
        item: snapshot,
        resolveOriginalFile: widget.resolveOriginalFile,
        isCurrent: () => _isCurrentAction(identity),
        canStart: () => !mediaActionActive,
        onActivity: _onMediaActionActivity,
        onFailure: () {
          if (mounted) {
            setState(() => mediaActionFailed = true);
            _wakeChrome();
          }
        },
      );
    }
    if (isProviderView(item.id) && widget.resolveOriginalFile == null) {
      // The synthetic view's storageUrl can be a cached thumbnail. Neither it
      // nor the workspace-file migrator proves where the original lives.
      return const _UnavailableAlbumMediaActions(
        reason: 'Original file unavailable in this album.',
      );
    }
    if (!widget.controller.items.any((live) => live.id == item.id) ||
        (!isProviderView(item.id) && source.source.isEmpty)) {
      return const _UnavailableAlbumMediaActions(reason: 'File unavailable.');
    }
    return MediaActionButtons(source: source, actions: _mediaActions!);
  }

  Object _actionIdentity(AlbumMediaItem item, UserProfilePB? profile) => (
        widget.controller,
        widget.mediaActions,
        widget.resolveOriginalFile,
        item.id,
        item.path,
        item.name,
        item.kind,
        item.byteSize,
        item.modifiedAt,
        item.unavailable,
        item.view.extra,
        _mediaSource(item, profile),
        // Account changes invalidate a pending provider resolution, but never
        // become provider download headers. Ordinary external files need none.
        isProviderView(item.id) ? (profile?.id, profile?.token) : null,
      );

  bool _isCurrentAction(Object identity) {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    final id = current?.id;
    // Read the live controller/profile even before their next widget frame.
    for (final item in widget.controller.items) {
      if (item.id == id) {
        return identity ==
            _actionIdentity(
              item,
              context.read<UserWorkspaceBloc?>()?.state.userProfile,
            );
      }
    }
    return false;
  }

  MediaActionSource _mediaSource(AlbumMediaItem item, UserProfilePB? profile) {
    if (isProviderView(item.id)) {
      // An unresolved provider item is deliberately NOT an actionable URL or
      // thumbnail path. The adapter must replace this with a local original.
      return MediaActionSource(
        source: '',
        name: item.name,
        isImage: item.kind == AlbumMediaKind.image,
      );
    }
    final stored = item.view.workspaceItem?.storageUrl;
    final source = stored == null || stored.isEmpty ? item.path : stored;
    final configured = getIt.isRegistered<AppFlowyCloudSharedEnv>()
        ? getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url
        : kAppflowyCloudUrl;
    final server = Uri.tryParse(configured);
    final uri = Uri.tryParse(source);
    // AlbumMediaItem has no CloudFile upload type. Remote provider paths may
    // be signed URLs: never infer workspace auth merely from !isLocal.
    final cloud = uri != null &&
        server != null &&
        (uri.isScheme('https') || uri.isScheme('http')) &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        uri.scheme == server.scheme &&
        uri.host == server.host &&
        uri.port == server.port &&
        uri.path.startsWith(
          '${server.path.replaceFirst(RegExp(r'/+$'), '')}/api/file_storage/',
        );
    return MediaActionSource.file(
      source: source,
      name: item.name,
      isImage: item.kind == AlbumMediaKind.image,
      uploadType: cloud ? FileUploadTypePB.CloudFile : null,
      userProfile: profile,
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
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
                onChanged: (transition) => _updateSlideshow(
                  slideshow.copyWith(transition: transition),
                ),
              ),
            ],
          ),
        ),
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
    if (page < 0 || page >= items.length) return;
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

  void _goTo(int target, {bool revealChrome = true}) {
    if (items.isEmpty) {
      return;
    }
    final resolved = target < 0
        ? (widget.controller.settings.slideshow.loop ? items.length - 1 : 0)
        : target >= items.length
            ? (widget.controller.settings.slideshow.loop ? 0 : items.length - 1)
            : target;
    if (resolved == index) {
      return;
    }
    if (revealChrome) _wakeChrome();
    if (MediaQuery.disableAnimationsOf(context)) {
      pageController.jumpToPage(resolved);
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
      _goTo(next, revealChrome: false);
      return;
    }
    if (index >= items.length - 1 &&
        !widget.controller.settings.slideshow.loop) {
      _setPlaying(false);
      return;
    }
    _goTo(index + 1, revealChrome: false);
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

  void _onMediaActionActivity(bool active) {
    if (!mounted) return;
    setState(() {
      mediaActionActive = active;
      if (active) mediaActionFailed = false;
    });
    // Pending work pins the chrome even if focus leaves for a native sheet;
    // completion starts a fresh idle period, leaving time to see feedback.
    _wakeChrome();
  }

  void _wakeChrome() {
    chromeTimer?.cancel();
    if (!chromeVisible) {
      setState(() => chromeVisible = true);
    }
    chromeTimer = Timer(_chromeIdle, () {
      if (mounted && !showInfo && !mediaActionActive && !mediaActionFailed) {
        setState(() => chromeVisible = false);
      }
    });
  }
}

/// Resolves a provider original before delegating to the existing IO boundary.
/// No preparation, clipboard formats or native sharing are reimplemented here.
class _LightboxMediaActions extends MediaActionService {
  const _LightboxMediaActions({
    required this.delegate,
    required this.item,
    required this.resolveOriginalFile,
    required this.isCurrent,
    required this.canStart,
    required this.onActivity,
    required this.onFailure,
  });

  final MediaActionService delegate;
  final AlbumMediaItem item;
  final AlbumOriginalFileResolver? resolveOriginalFile;
  final bool Function() isCurrent;
  final bool Function() canStart;
  final ValueChanged<bool> onActivity;
  final VoidCallback onFailure;

  Future<void> _run(
    MediaActionSource target,
    Future<void> Function(MediaActionSource original) operation,
  ) async {
    if (!isCurrent() || !canStart()) {
      throw StateError('The media action is no longer current.');
    }
    onActivity(true);
    try {
      var original = target;
      if (isProviderView(item.id)) {
        final file = await resolveOriginalFile?.call(item);
        final uri = file == null ? null : Uri.tryParse(file.path);
        if (file == null ||
            !p.isAbsolute(file.path) ||
            uri?.isScheme('http') == true ||
            uri?.isScheme('https') == true) {
          throw StateError('The original file is unavailable.');
        }
        original = MediaActionSource(
          source: file.path,
          name: target.name,
          isImage: target.isImage,
        );
      }
      // A delayed download must not copy/share after closing, changing album,
      // navigating, renewing credentials, or refreshing the displayed item.
      if (!isCurrent()) {
        throw StateError('The media action is no longer current.');
      }
      await operation(original);
      if (!isCurrent()) {
        throw StateError('The media action is no longer current.');
      }
    } catch (_) {
      if (isCurrent()) onFailure();
      // Shared buttons deliberately neither display nor log raw IO failures.
      rethrow;
    } finally {
      onActivity(false);
    }
  }

  @override
  Future<void> copy(MediaActionSource target) => _run(target, delegate.copy);

  @override
  Future<void> share(MediaActionSource target, {Rect? sharePositionOrigin}) =>
      _run(
        target,
        (original) => delegate.share(
          original,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
}

class _UnavailableAlbumMediaActions extends StatelessWidget {
  const _UnavailableAlbumMediaActions({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              reason,
              key: const ValueKey('album-original-unavailable'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          for (final copy in [true, false])
            SizedBox.square(
              dimension: 32,
              child: TooltipTheme(
                data: TooltipTheme.of(context)
                    .copyWith(excludeFromSemantics: true),
                child: IconButton(
                  key: ValueKey(copy ? 'media-copy' : 'media-share'),
                  tooltip:
                      '${copy ? LocaleKeys.editor_copy.tr() : LocaleKeys.button_share.tr()} — $reason',
                  onPressed: null,
                  padding: EdgeInsets.zero,
                  icon: Semantics(
                    label:
                        '${copy ? LocaleKeys.editor_copy.tr() : LocaleKeys.button_share.tr()} — $reason',
                    excludeSemantics: true,
                    child: Icon(
                      copy ? Icons.copy_rounded : Icons.ios_share_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
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
    if (!playing ||
        !isCurrent ||
        transition != AlbumSlideshowTransition.zoom ||
        MediaQuery.disableAnimationsOf(context)) {
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
    );
  }

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
