import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_highlight.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ocr_find_session.dart';
import 'ocr_result.dart';
import 'ocr_service.dart';

/// Opens local text extraction, or goes straight to find without copying.
/// Completes after the route has closed, including targeted owner removal.
Future<void> showImageOcrOverlay(
  BuildContext context, {
  required ImageEditorSource source,
  required String name,
  bool find = false,
  String initialQuery = '',
  OcrService? service,
}) {
  if (!context.mounted) return Future.value();
  final route = _newRoute(
    context,
    source: source,
    name: name,
    find: find,
    initialQuery: initialQuery,
    service: service,
  );
  unawaited(Navigator.of(context, rootNavigator: true).push<void>(route));
  return route.completed.then<void>((_) {});
}

/// Optional source seam for image hosts; production uses ImageEditorSource.
typedef ImageOcrSourceBuilder = ImageEditorSource Function(
  ImageBlockData image,
);

/// Passive image-content boundary. Hover never requests focus or selects a
/// block. A gallery may resolve its nearest photo only when Find is invoked.
/// The owned popup is cancelled if its image/permissions/host become invalid.
class ImageOcrFindRegion extends StatefulWidget {
  const ImageOcrFindRegion({
    super.key,
    required this.child,
    required this.source,
    required this.name,
    this.service,
    this.enabled = true,
    this.isSelected,
    this.isAvailable,
    this.resolveSource,
    this.isSourceCurrent,
    this.debugLabel = 'Image OCR',
  });

  final Widget child;
  final ImageEditorSource source;
  final String name;
  final OcrService? service;
  final bool enabled;
  final bool Function()? isSelected;
  final bool Function()? isAvailable;
  final ImageEditorSource? Function()? resolveSource;
  final bool Function(ImageEditorSource)? isSourceCurrent;
  final String debugLabel;

  @override
  State<ImageOcrFindRegion> createState() => _ImageOcrFindRegionState();
}

class _ImageOcrFindRegionState extends State<ImageOcrFindRegion> {
  _ImageOcrRoute? _route;

  bool get _available =>
      mounted && widget.enabled && (widget.isAvailable?.call() ?? true);

  bool _current(ImageEditorSource source) =>
      _available &&
      (widget.isSourceCurrent?.call(source) ??
          _sameSource(widget.source, source));

  void _open() {
    if (!_available) return;
    final existing = _route;
    if (existing != null && existing.isActive) {
      existing.overlayKey.currentState?._openFind();
      return;
    }
    final source =
        widget.resolveSource == null ? widget.source : widget.resolveSource!();
    if (source == null || source.url.isEmpty || !_current(source)) return;
    if (source.type == CustomImageType.internal && source.userProfile == null) {
      return;
    }
    final route = _newRoute(
      context,
      source: source,
      name: widget.name,
      find: true,
      service: widget.service,
      isOwnerActive: () => _current(source),
    );
    _route = route;
    unawaited(Navigator.of(context, rootNavigator: true).push<void>(route));
    unawaited(
      route.completed.then<void>((_) {
        if (mounted && identical(_route, route)) {
          setState(() => _route = null);
        }
      }),
    );
    setState(() {});
  }

  void _dismiss() {
    final route = _route;
    _route = null;
    if (route == null) return;
    route.overlayKey.currentState?._stop();
    // Rebinding/unmount can happen during layout. Never mutate the Navigator
    // while it is building; a covered route is removed, not a newer dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) => route.dismiss());
  }

  @override
  void didUpdateWidget(ImageOcrFindRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final route = _route;
    if (route != null &&
        (!_current(route.source) || oldWidget.service != widget.service)) {
      _dismiss();
    }
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContextualFindRegion(
        enabled: _available,
        isSelected: widget.isSelected,
        onFind: _open,
        onDismiss: _dismiss,
        findOpen: _route?.isActive ?? false,
        debugLabel: widget.debugLabel,
        child: widget.child,
      );
}

bool _sameSource(ImageEditorSource a, ImageEditorSource b) =>
    identical(a, b) ||
    (a.runtimeType == ImageEditorSource &&
        b.runtimeType == ImageEditorSource &&
        a.url == b.url &&
        a.type == b.type &&
        a.userProfile == b.userProfile);

ImageEditorSource _readableSource(ImageEditorSource source) {
  // Preserve injected readers. Ordinary file URIs need decoding before IO;
  // external pictures must never receive workspace bearer credentials.
  if (source.runtimeType != ImageEditorSource) return source;
  final uri = Uri.tryParse(source.url);
  return ImageEditorSource(
    url: source.type == CustomImageType.local && uri?.isScheme('file') == true
        ? File.fromUri(uri!).path
        : source.url,
    type: source.type,
    userProfile:
        source.type == CustomImageType.internal ? source.userProfile : null,
  );
}

_ImageOcrRoute _newRoute(
  BuildContext context, {
  required ImageEditorSource source,
  required String name,
  required bool find,
  String initialQuery = '',
  OcrService? service,
  bool Function()? isOwnerActive,
}) =>
    _ImageOcrRoute(
      source: source,
      name: name,
      find: find,
      initialQuery: initialQuery,
      service: service,
      isOwnerActive: isOwnerActive,
      reduceMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
      themes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
    );

class _ImageOcrRoute extends PopupRoute<void> {
  _ImageOcrRoute({
    required this.source,
    required this.name,
    required this.find,
    required this.initialQuery,
    required this.service,
    required this.themes,
    required this.reduceMotion,
    this.isOwnerActive,
  });

  final ImageEditorSource source;
  final String name;
  final bool find;
  final String initialQuery;
  final OcrService? service;
  final CapturedThemes themes;
  final bool reduceMotion;
  final bool Function()? isOwnerActive;
  final overlayKey = GlobalKey<_ImageOcrOverlayState>();

  @override
  Color get barrierColor => Colors.transparent;
  @override
  bool get barrierDismissible => false; // The photo/panel own their hit bounds.
  @override
  String get barrierLabel => 'Close image text';
  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 140);
  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 90);

  void dismiss() {
    overlayKey.currentState?._stop();
    final owner = navigator;
    if (owner == null || !isActive) return;
    if (isCurrent) {
      owner.pop();
    } else {
      // Flutter 3.27 removeRoute does not complete popped. This is OUR route,
      // so completing its result here is legal and cannot pop another popup.
      didComplete(null);
      owner.removeRoute(this);
    }
  }

  @override
  bool didPop(void result) {
    overlayKey.currentState?._stop();
    return super.didPop(null);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      themes.wrap(
        ImageOcrOverlay(
          key: overlayKey,
          source: source,
          name: name,
          find: find,
          initialQuery: initialQuery,
          service: service,
          isOwnerActive: isOwnerActive,
        ),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      FadeTransition(
        // CurveTween owns no listeners (unlike creating a CurvedAnimation on
        // every build). No large blur/scale surface is animated over the app.
        opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: child,
      );
}

class ImageOcrOverlay extends StatefulWidget {
  const ImageOcrOverlay({
    super.key,
    required this.source,
    required this.name,
    this.find = false,
    this.initialQuery = '',
    this.service,
    this.isOwnerActive,
  });

  final ImageEditorSource source;
  final String name;
  final bool find;
  final String initialQuery;
  final OcrService? service;
  final bool Function()? isOwnerActive;

  @override
  State<ImageOcrOverlay> createState() => _ImageOcrOverlayState();
}

class _ImageOcrOverlayState extends State<ImageOcrOverlay> {
  late final _find = OcrFindSession(initialQuery: widget.initialQuery);
  final _contentFocus = FocusNode(debugLabel: 'Image OCR content');
  final _panelScroll = ScrollController();
  OcrCancellationToken? _scanToken;
  Animation<double>? _routeAnimation;
  ui.Image? _image;
  OcrResult? _result;
  OcrFailureKind? _error;
  String? _engine;
  String? _copyMessage;
  Timer? _copyAck;
  bool _scanning = true;
  bool _copying = false;
  bool _closing = false;
  bool _revealQueued = false;
  late bool _findOpen = widget.find;
  int _scanGeneration = 0;
  int _copyRevision = 0;
  double _rowExtent = 72;

  bool get _alive =>
      mounted && !_closing && (widget.isOwnerActive?.call() ?? true);
  bool _current(int generation) => _alive && generation == _scanGeneration;
  bool get _canInteract => _alive && ModalRoute.of(context)?.isCurrent != false;
  bool get _reducedMotion => MediaQuery.of(context).disableAnimations;
  bool get _hasText => _find.words.isNotEmpty;
  bool get _showMatches => _findOpen && _find.query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _find.addListener(_findChanged);
    unawaited(_scan());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_routeStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeStatus);
    }
  }

  void _routeStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) _stop();
  }

  @override
  void didUpdateWidget(ImageOcrOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameSource(oldWidget.source, widget.source) ||
        oldWidget.service != widget.service) {
      _retireImage();
      unawaited(_scan());
    }
    if (oldWidget.initialQuery != widget.initialQuery) {
      _find.findController.text = widget.initialQuery;
    }
    if (widget.find && !oldWidget.find) _openFind();
    if (!(widget.isOwnerActive?.call() ?? true)) _stop();
  }

  void _stop() {
    if (_closing) return;
    _closing = true;
    _scanGeneration++;
    _copyRevision++;
    _scanToken?.cancel();
    _copyAck?.cancel();
  }

  @override
  void dispose() {
    _stop();
    _routeAnimation?.removeStatusListener(_routeStatus);
    _find.removeListener(_findChanged);
    _find.dispose();
    _contentFocus.dispose();
    _panelScroll.dispose();
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  void _retireImage() {
    final previous = _image;
    _image = null;
    if (previous != null) {
      // RawImage must first detach from the old frame. A newer decode is never
      // allowed to dispose the image that another scan has already adopted.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  Future<void> _scan() async {
    if (!_alive) return;
    _scanToken?.cancel();
    final token = _scanToken = OcrCancellationToken();
    final generation = ++_scanGeneration;
    final requestedSource = widget.source;
    final service = widget.service ?? OcrService();
    setState(() {
      _scanning = true;
      _error = null;
      _engine = null;
      _result = null;
    });
    _find.setResult(null); // Keeps a query entered before OCR is ready.
    final deadline = Timer(const Duration(minutes: 4), () {
      if (!_current(generation)) return;
      setState(() {
        _error = OcrFailureKind.timedOut;
        _scanning = false;
      });
      token.cancel();
    });
    token.addListener(deadline.cancel);
    try {
      final source = _readableSource(requestedSource);
      // Avoid allocating a giant local payload before applying the byte cap.
      // Subclassed sources retain their existing in-memory/testing read seam.
      if (source.runtimeType == ImageEditorSource && !source.isRemote) {
        final length = await token.wait(File(source.url).length());
        if (length > maxOcrImageBytes) {
          throw const OcrUnavailableException(
            'This picture is too large for text recognition.',
            kind: OcrFailureKind.tooLarge,
          );
        }
      }
      final bytes = await token.wait(
        source.readBytes().timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw const OcrUnavailableException(
                'The picture took too long to load.',
                kind: OcrFailureKind.timedOut,
              ),
            ),
      );
      if (!_current(generation)) return;
      if (bytes.isEmpty || bytes.length > maxOcrImageBytes) {
        throw OcrUnavailableException(
          'This picture cannot be read.',
          kind: bytes.isEmpty
              ? OcrFailureKind.invalidImage
              : OcrFailureKind.tooLarge,
        );
      }
      final preview = await token.wait(
        _decodePreview(bytes),
        onDiscard: (preview) => preview.$1.dispose(),
      );
      if (!_current(generation)) {
        preview.$1.dispose();
        return;
      }
      _retireImage();
      setState(() => _image = preview.$1);
      final result = await token.wait(
        service.recognizeBytes(
          bytes,
          imageSize: preview.$2,
          cancellation: token,
          onEngineSelected: (name) {
            if (_current(generation) && !token.isCancelled) {
              setState(() => _engine = name);
            }
          },
        ),
      );
      if (!_current(generation) || token.isCancelled) return;
      setState(() {
        _result = result;
        _engine = result.engine;
        _scanning = false;
      });
      _find.setResult(result);
    } on OcrCancelledException {
      // Closing/rebinding is not a recognition failure.
    } on OcrUnavailableException catch (error) {
      if (_current(generation) && !token.isCancelled) {
        setState(() {
          _error = error.kind;
          _scanning = false;
        });
      }
    } catch (_) {
      if (_current(generation) && !token.isCancelled) {
        setState(() {
          _error = OcrFailureKind.failed;
          _scanning = false;
        });
      }
    } finally {
      deadline.cancel();
      token.removeListener(deadline.cancel);
    }
  }

  void _findChanged() {
    if (!_alive) return;
    _copyRevision++;
    _copyAck?.cancel();
    setState(() => _copyMessage = null);
    _revealSelection();
  }

  void _revealSelection() {
    if (_revealQueued) return;
    _revealQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealQueued = false;
      if (!_alive || !_panelScroll.hasClients || !_hasText) return;
      final int index;
      if (_showMatches) {
        index = _find.index;
      } else if (_find.selected.isNotEmpty) {
        index = _find.words[_find.selected.reduce(math.min)].line;
      } else {
        return;
      }
      if (index < 0) return;
      final position = _panelScroll.position;
      final top = index * _rowExtent;
      final bottom = top + _rowExtent;
      if (top >= position.pixels &&
          bottom <= position.pixels + position.viewportDimension) {
        return;
      }
      final target = (top - (position.viewportDimension - _rowExtent) / 2)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (_reducedMotion) {
        _panelScroll.jumpTo(target);
      } else {
        unawaited(
          _panelScroll.animateTo(
            target,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    });
  }

  void _openFind() {
    if (!_alive) return;
    setState(() => _findOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_alive && _findOpen && ModalRoute.of(context)?.isCurrent != false) {
        _find.findFocusNode.requestFocus();
      }
    });
    _revealSelection();
  }

  void _hideFind({bool restoreFocus = true}) {
    if (!_alive) return;
    setState(() => _findOpen = false);
    _find.findController.clear();
    if (restoreFocus) _contentFocus.requestFocus();
  }

  void _closeFindBar() {
    // The shared bar uses one onClose for its × and Escape. Keep × local, but
    // Escape closes this popup in one step, even while typing in the field.
    if (HardwareKeyboard.instance.logicalKeysPressed
        .contains(LogicalKeyboardKey.escape)) {
      _close();
    } else {
      _hideFind();
    }
  }

  void _close() {
    if (!_alive) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) return;
    _stop();
    if (route is _ImageOcrRoute) {
      route.dismiss();
    } else if (route!.navigator?.canPop() ?? false) {
      route.navigator!.pop();
    }
  }

  void _chooseWord(int index) {
    if (!_canInteract ||
        _scanning ||
        index < 0 ||
        index >= _find.words.length) {
      return;
    }
    _contentFocus.requestFocus();
    if (_findOpen) {
      final match = _find.matches.indexWhere(
        (match) => match.wordIndices.contains(index),
      );
      if (!_isMultiSelectHeld && match >= 0) {
        _find.selectMatch(match);
      } else {
        _find.selectWords([index], additive: _isMultiSelectHeld);
      }
    } else {
      _chooseLine(_find.words[index].line);
    }
  }

  void _chooseLine(int index) {
    if (!_canInteract ||
        _scanning ||
        index < 0 ||
        index >= (_result?.lines.length ?? 0)) {
      return;
    }
    _find.selectWords(_find.wordsInLine(index), additive: _isMultiSelectHeld);
    if (!_findOpen && !_isMultiSelectHeld) {
      unawaited(_copy(_result!.lines[index].text));
    }
  }

  Future<void> _copy(String text) async {
    if (!_canInteract || _scanning || _copying || text.isEmpty) return;
    final generation = _scanGeneration;
    final revision = _copyRevision;
    _copyAck?.cancel();
    setState(() {
      _copying = true;
      _copyMessage = null;
    });
    try {
      // Await a real platform acknowledgement. Merely navigating, selecting,
      // scanning, or searching must never replace the user's clipboard.
      await Clipboard.setData(ClipboardData(text: text))
          .timeout(const Duration(seconds: 8));
      if (_current(generation) && revision == _copyRevision) {
        setState(() => _copyMessage = 'Copied');
        _copyAck = Timer(const Duration(milliseconds: 1400), () {
          if (_alive) setState(() => _copyMessage = null);
        });
      }
    } catch (_) {
      if (_current(generation) && revision == _copyRevision) {
        setState(() => _copyMessage = 'Unable to copy text. Try again.');
      }
    } finally {
      if (_alive) setState(() => _copying = false);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_alive ||
        ModalRoute.of(context)?.isCurrent == false ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _close();
      return KeyEventResult.handled;
    }
    if (_findOpen &&
        event.logicalKey == LogicalKeyboardKey.f3 &&
        !keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed) {
      keyboard.isShiftPressed ? _find.previous() : _find.next();
      return KeyEventResult.handled;
    }
    // Native field Ctrl/Cmd+A/C stays native, including an empty selection.
    if (_find.findFocusNode.hasFocus ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed == keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      _find.selectAll();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      unawaited(
        _copy(
          !_findOpen && _find.selected.isEmpty
              ? _result?.text ?? ''
              : _find.selectedText,
        ),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _status {
    if (_scanning) {
      return _engine == null
          ? 'Preparing local text recognition…'
          : 'Reading with $_engine…';
    }
    final engine = _engine == null || _engine!.isEmpty ? 'Local OCR' : _engine!;
    if (_error != null) return 'Recognition did not complete · $engine';
    if (!_hasText) return 'No text recognized · $engine';
    if (_findOpen) {
      if (_find.invalid) return 'Invalid regular expression · $engine';
      if (_find.query.trim().isEmpty) {
        return 'Type to find in this picture · $engine';
      }
      if (_find.matches.isEmpty) return 'No matches · $engine';
      return '${_find.displayIndex} of ${_find.matches.length} matches · $engine';
    }
    return '${_result!.lines.length} text regions · $engine';
  }

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: ContextualFindRegion(
        onFind: _openFind,
        onDismiss: () => _hideFind(restoreFocus: false),
        findOpen: _findOpen,
        findFocusNode: _find.findFocusNode,
        enabled: !_closing,
        debugLabel: 'Image text popup',
        child: Focus(
          focusNode: _contentFocus,
          autofocus: !_findOpen,
          onKeyEvent: _onKey,
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const ValueKey('image-ocr-outside'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: ColoredBox(
                    color: EditorSurfaceStyle.canvasBackground(context)
                        .withValues(alpha: 0.76),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(
                      MediaQuery.sizeOf(context).width < 600 ? 12 : 28,
                    ),
                    child: Column(
                      children: [
                        _header(palette),
                        const SizedBox(height: 12),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final horizontal = constraints.maxWidth >= 760;
                              return Flex(
                                direction: horizontal
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: horizontal ? 7 : 5,
                                    child: _OcrPicture(
                                      key: const ValueKey('image-ocr-stage'),
                                      image: _image,
                                      session: _find,
                                      findOpen: _findOpen,
                                      palette: palette,
                                      onChooseWord: _chooseWord,
                                      onSelect: (indices) {
                                        if (!_alive) return;
                                        _contentFocus.requestFocus();
                                        _find.selectWords(
                                          indices,
                                          additive: _isMultiSelectHeld,
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: horizontal ? 16 : 0,
                                    height: horizontal ? 0 : 12,
                                  ),
                                  Expanded(
                                    flex: horizontal ? 3 : 4,
                                    child: _panel(palette),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _surface({required Widget child, Key? key}) => TextFieldTapRegion(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          child: DecoratedBox(
            key: key,
            decoration: BoxDecoration(
              color: FindBarPalette.of(context).surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: EditorSurfaceStyle.embedShadow(context),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      );

  Widget _header(FindBarPalette palette) => _surface(
        key: const ValueKey('image-ocr-header'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name.isEmpty ? 'Image text' : widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: MediaQuery.textScalerOf(context).scale(11.5) *
                              2.6,
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _status,
                              key: const ValueKey('image-ocr-status'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 11.5,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _button(
                    'image-ocr-find',
                    'Find in image',
                    Icons.search_rounded,
                    _openFind,
                  ),
                  _button(
                    'image-ocr-copy-selected',
                    'Copy selected text',
                    Icons.content_copy_rounded,
                    !_copying && _find.selected.isNotEmpty
                        ? () => unawaited(_copy(_find.selectedText))
                        : null,
                  ),
                  _button(
                    'image-ocr-copy-all',
                    'Copy all text',
                    Icons.copy_all_rounded,
                    !_copying && _hasText
                        ? () => unawaited(_copy(_result?.text ?? ''))
                        : null,
                  ),
                  _button(
                    'image-ocr-close',
                    'Close image text',
                    Icons.close_rounded,
                    _close,
                  ),
                ],
              ),
              // Reserve acknowledgement space: copying never resizes the photo
              // or moves a match while the pointer is selecting it.
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(11.5) + 5,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _copying ? 'Copying…' : _copyMessage ?? '',
                      key: const ValueKey('image-ocr-copy-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              if (_findOpen) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  // The popup's backdrop owns dismissal. Selecting a word or
                  // result inside this popup must keep the active query open.
                  child: TextEntryShortcuts(
                    child: FindReplaceBar(
                      dismissOnTapOutside: false,
                      findController: _find.findController,
                      findFocusNode: _find.findFocusNode,
                      options: _find.options,
                      onOptionsChanged: (value) => _find.options = value,
                      matchCount: _find.matches.length,
                      currentMatch: _find.displayIndex,
                      onPrevious: _find.matches.isEmpty ? null : _find.previous,
                      onNext: _find.matches.isEmpty ? null : _find.next,
                      onSubmitted: () =>
                          HardwareKeyboard.instance.isShiftPressed
                              ? _find.previous()
                              : _find.next(),
                      onClose: _closeFindBar,
                      queryInvalid: _find.invalid,
                      busy: _scanning,
                      hintText: 'Find in image',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _button(
    String key,
    String label,
    IconData icon,
    VoidCallback? onPressed,
  ) {
    final generation = _scanGeneration;
    return IconButton(
      key: ValueKey(key),
      tooltip: label,
      onPressed: onPressed == null
          ? null
          : () {
              if (_current(generation) && _canInteract) onPressed();
            },
      icon: Icon(icon, size: 17),
      style: IconButton.styleFrom(
        foregroundColor: FindBarPalette.of(context).textSecondary,
        hoverColor: FindBarPalette.of(context).hover,
        minimumSize: const Size.square(32),
        padding: const EdgeInsets.all(6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _panel(FindBarPalette palette) => _surface(
        key: const ValueKey('image-ocr-panel'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _rowExtent =
                math.max(72, MediaQuery.textScalerOf(context).scale(40) + 28);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (constraints.maxHeight >= 130)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _showMatches ? 'Matches' : 'Detected text',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        _button(
                          'image-ocr-select-all',
                          'Select all recognized text',
                          Icons.select_all_rounded,
                          _hasText ? _find.selectAll : null,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _scanning ||
                          _error != null ||
                          !_hasText ||
                          (_showMatches && _find.matches.isEmpty)
                      ? _message(palette)
                      : ListView.builder(
                          key: const ValueKey('image-ocr-results'),
                          controller: _panelScroll,
                          primary: false,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemExtent: _rowExtent,
                          itemCount: _showMatches
                              ? _find.matches.length
                              : _result!.lines.length,
                          itemBuilder: (context, index) {
                            final generation = _scanGeneration;
                            final result = _result;
                            final matches = _find.matches;
                            final findOpen = _findOpen;
                            final indices = _showMatches
                                ? _find.matches[index].wordIndices
                                : _find.wordsInLine(index).toList();
                            final line = indices.isEmpty
                                ? index
                                : _find.words[indices.first].line;
                            final selected = _showMatches
                                ? _find.index == index
                                : indices.isNotEmpty &&
                                    indices.every(_find.selected.contains);
                            final text = _showMatches
                                ? _find.textOfWords(indices)
                                : _result!.lines[index].text;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Semantics(
                                selected: selected,
                                child: TextButton(
                                  key: ValueKey('image-ocr-row-$index'),
                                  style: TextButton.styleFrom(
                                    alignment: Alignment.centerLeft,
                                    foregroundColor: palette.textPrimary,
                                    backgroundColor: selected
                                        ? palette.selected
                                        : palette.selected.withValues(alpha: 0),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    animationDuration: _reducedMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 90),
                                  ),
                                  onPressed: () {
                                    if (!_current(generation) ||
                                        !_canInteract ||
                                        !identical(_result, result) ||
                                        !identical(_find.matches, matches) ||
                                        _findOpen != findOpen) {
                                      return;
                                    }
                                    if (_showMatches) {
                                      _find.selectMatch(index);
                                    } else {
                                      _chooseLine(index);
                                    }
                                  },
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          height: 1.3,
                                        ),
                                      ),
                                      if (_showMatches)
                                        Text(
                                          'Line ${line + 1}',
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: palette.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (constraints.maxHeight >= 230)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _findOpen
                          ? 'Click or drag to select words. Copy only when you choose. '
                              'Enter / F3: next · Shift: previous'
                          : 'Click a text region to copy it. Ctrl or Shift adds to '
                              'the selection; drag to select words.',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );

  Widget _message(FindBarPalette palette) {
    final String message;
    final String hint;
    if (_scanning) {
      message =
          _engine == null ? 'Preparing the picture…' : 'Reading with $_engine…';
      hint = 'Recognition stays on this device. You can type a search now.';
    } else if (_error != null) {
      (message, hint) = switch (_error!) {
        OcrFailureKind.unavailable => (
            'No local OCR engine could read this picture.',
            'Install a Windows OCR language pack or Tesseract OCR, then try again.'
          ),
        OcrFailureKind.timedOut => (
            'Text recognition took too long.',
            'The scan was stopped. Try a smaller picture or retry.'
          ),
        OcrFailureKind.tooLarge => (
            'This picture is too large to scan.',
            'Use an image no larger than 32 MB.'
          ),
        OcrFailureKind.invalidImage || OcrFailureKind.failed => (
            'Text recognition failed.',
            'Check that the picture is available and readable, then try again.'
          ),
      };
    } else if (!_hasText) {
      message = 'No text was recognized in this picture.';
      hint = 'A clearer image or another installed OCR language may help.';
    } else {
      message = _find.invalid
          ? 'The regular expression is not valid.'
          : 'No matches.';
      hint = _find.invalid
          ? 'Complete the expression or turn off regexp mode.'
          : 'Try another query or change the matching options.';
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_scanning && !_reducedMotion)
            LinearProgressIndicator(
              color: palette.accent,
              backgroundColor: palette.field,
              minHeight: 2,
            ),
          const SizedBox(height: 12),
          Text(
            message,
            key: const ValueKey('image-ocr-message'),
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (!_scanning && (_error != null || !_hasText)) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              key: const ValueKey('image-ocr-retry'),
              onPressed: () => unawaited(_scan()),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Decode only a bounded display image; OCR still receives the original bytes
/// and source dimensions. All codec/descriptor/buffer handles have one owner.
Future<(ui.Image, Size)> _decodePreview(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size =
        Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    if (size.isEmpty || !size.isFinite) throw const FormatException();
    final scale = math.min(1.0, 2048 / math.max(size.width, size.height));
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (size.width * scale).round()),
      targetHeight: math.max(1, (size.height * scale).round()),
    );
    final frame = await codec.getNextFrame();
    return (frame.image, size);
  } catch (_) {
    throw const OcrUnavailableException(
      'This picture could not be decoded.',
      kind: OcrFailureKind.invalidImage,
    );
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

bool get _isMultiSelectHeld =>
    HardwareKeyboard.instance.isControlPressed ||
    HardwareKeyboard.instance.isMetaPressed ||
    HardwareKeyboard.instance.isShiftPressed;

class _OcrPicture extends StatefulWidget {
  const _OcrPicture({
    super.key,
    required this.image,
    required this.session,
    required this.findOpen,
    required this.palette,
    required this.onChooseWord,
    required this.onSelect,
  });

  final ui.Image? image;
  final OcrFindSession session;
  final bool findOpen;
  final FindBarPalette palette;
  final ValueChanged<int> onChooseWord;
  final ValueChanged<Iterable<int>> onSelect;

  @override
  State<_OcrPicture> createState() => _OcrPictureState();
}

class _OcrPictureState extends State<_OcrPicture> {
  Size _size = Size.zero;
  int? _hovered;
  Offset? _origin;
  Rect? _band;

  @override
  void didUpdateWidget(_OcrPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _hovered = null;
      _origin = null;
      _band = null;
    }
  }

  int? _wordAt(Offset point) {
    if (_size.isEmpty) return null;
    final normalized = Offset(point.dx / _size.width, point.dy / _size.height);
    for (final (index, word) in widget.session.words.indexed) {
      if (!word.bounds.isEmpty && word.bounds.contains(normalized)) {
        return index;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final image = widget.image;
          if (image == null || constraints.biggest.isEmpty) {
            return const SizedBox.shrink();
          }
          final scale = math.min(
            constraints.maxWidth / image.width,
            constraints.maxHeight / image.height,
          );
          _size = Size(image.width * scale, image.height * scale);
          final matched = widget.findOpen
              ? widget.session.matches
                  .expand((match) => match.wordIndices)
                  .toSet()
              : const <int>{};
          final active = widget.findOpen
              ? widget.session.currentMatch?.wordIndices.toSet() ??
                  const <int>{}
              : const <int>{};
          return Center(
            child: TextFieldTapRegion(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                child: SizedBox.fromSize(
                  key: const ValueKey('image-ocr-photo'),
                  size: _size,
                  child: MouseRegion(
                    opaque: false,
                    cursor: _hovered == null
                        ? SystemMouseCursors.precise
                        : SystemMouseCursors.text,
                    onHover: (event) {
                      final word = _wordAt(event.localPosition);
                      if (word != _hovered) setState(() => _hovered = word);
                    },
                    onExit: (_) => setState(() => _hovered = null),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (event) {
                        final word = _wordAt(event.localPosition);
                        if (word == null) {
                          widget.onSelect(const []);
                        } else {
                          widget.onChooseWord(word);
                        }
                      },
                      onPanStart: (event) {
                        _origin = event.localPosition;
                        setState(
                          () => _band = Rect.fromPoints(_origin!, _origin!),
                        );
                      },
                      onPanUpdate: (event) {
                        if (_origin == null) return;
                        setState(
                          () => _band =
                              Rect.fromPoints(_origin!, event.localPosition)
                                  .intersect(Offset.zero & _size),
                        );
                      },
                      onPanCancel: () => setState(() {
                        _origin = null;
                        _band = null;
                      }),
                      onPanEnd: (_) {
                        final band = _band;
                        setState(() {
                          _origin = null;
                          _band = null;
                        });
                        if (band == null || band.isEmpty) return;
                        widget.onSelect([
                          for (final (index, word)
                              in widget.session.words.indexed)
                            if (_scaledBounds(word.bounds, _size)
                                .overlaps(band))
                              index,
                        ]);
                      },
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('image-ocr-highlights'),
                          foregroundPainter: OcrHighlightPainter(
                            boxes: widget.session.words
                                .map((word) => word.bounds)
                                .toList(),
                            matched: matched,
                            active: active,
                            selected: widget.session.selected,
                            hovered: _hovered,
                            band: _band,
                            accent: widget.palette.accent,
                            matchColor: FindHighlightColors.match(
                              Theme.of(context).brightness,
                            ),
                            activeColor: FindHighlightColors.current(
                              Theme.of(context).brightness,
                            ),
                          ),
                          child: RepaintBoundary(
                            child: RawImage(
                              image: image,
                              fit: BoxFit.fill,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

Rect _scaledBounds(Rect bounds, Size size) => Rect.fromLTWH(
      bounds.left * size.width,
      bounds.top * size.height,
      bounds.width * size.width,
      bounds.height * size.height,
    );

/// Transparent at rest. Paints only matched/active/selected/hovered word boxes,
/// independently of the cached photo. Every input is immutable per frame.
class OcrHighlightPainter extends CustomPainter {
  OcrHighlightPainter({
    required this.boxes,
    required this.matched,
    required this.active,
    required this.selected,
    required this.hovered,
    required this.band,
    required this.accent,
    required this.matchColor,
    required this.activeColor,
  });

  final List<Rect> boxes;
  final Set<int> matched;
  final Set<int> active;
  final Set<int> selected;
  final int? hovered;
  final Rect? band;
  final Color accent;
  final Color matchColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < boxes.length; i++) {
      final current = active.contains(i);
      final selection = selected.contains(i);
      if (boxes[i].isEmpty ||
          (!matched.contains(i) && !current && !selection && hovered != i)) {
        continue;
      }
      final rect = RRect.fromRectAndRadius(
        _scaledBounds(boxes[i], size).inflate(1),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = current
              ? activeColor
              : matched.contains(i)
                  ? matchColor
                  : accent.withValues(alpha: selection ? 0.24 : 0.12),
      );
      if (current || selection) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = accent.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = current ? 1.5 : 1,
        );
      }
    }
    if (band != null) {
      canvas.drawRect(band!, Paint()..color = accent.withValues(alpha: 0.12));
      canvas.drawRect(
        band!,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OcrHighlightPainter oldDelegate) =>
      !listEquals(oldDelegate.boxes, boxes) ||
      !setEquals(oldDelegate.matched, matched) ||
      !setEquals(oldDelegate.active, active) ||
      !setEquals(oldDelegate.selected, selected) ||
      oldDelegate.hovered != hovered ||
      oldDelegate.band != band ||
      oldDelegate.accent != accent ||
      oldDelegate.matchColor != matchColor ||
      oldDelegate.activeColor != activeColor;
}
