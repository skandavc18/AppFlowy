import 'dart:async';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_scroll_physics.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Whether a message can be shown as its sender wrote it on this platform.
bool get canRenderEmailHtml =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// A message body, rendered.
///
/// The message itself can never run: every script is stripped out of it and
/// the document is served under a policy that gives scripts no source. The
/// renderer's own scripting stays on so AppFlowy can install its kinetic
/// scrolling next to the document — a host script is not subject to the page's
/// policy, and the message has no way to reach it.
///
/// The view is created once and reloaded as the reader moves between messages:
/// building and tearing down a platform view for every click is what takes the
/// Windows renderer down.
class EmailBodyView extends StatefulWidget {
  const EmailBodyView({
    super.key,
    required this.html,
    required this.theme,
  });

  final String html;
  final EmailTheme theme;

  @override
  State<EmailBodyView> createState() => _EmailBodyViewState();
}

class _EmailBodyViewState extends State<EmailBodyView> {
  /// A status listener attached while a route is already settling never fires,
  /// so the view is never left waiting on it alone.
  static const _readyBackstop = Duration(milliseconds: 320);

  /// A composition surface made in a degenerate box can fault the compositor.
  static const _minimumSurface = 64.0;

  final _viewportKey = GlobalKey();
  final _pending = <String>[];

  InAppWebViewController? _controller;
  Animation<double>? _routeAnimation;
  bool _ready = false;
  bool _closing = false;
  String? _loaded;

  bool _engineInstalled = false;
  bool _flushing = false;
  VelocityTracker? _tracker;
  PremiumScrollPhysicsConfig _physics = const PremiumScrollPhysicsConfig();
  bool _kinetic = true;

  bool get _alive => mounted && !_closing;

  /// The engine lives beside the document, so it only exists where the
  /// renderer can be scripted at all.
  bool get _drivesScrolling => Platform.isWindows;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchRouteAnimation();

    final behaviour = ScrollConfiguration.of(context);
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    final kinetic = behaviour is PremiumScrollBehavior
        ? behaviour.kineticEnabled
        : !reducedMotion;
    final physics = behaviour is PremiumScrollBehavior
        ? behaviour.config
        : const PremiumScrollPhysicsConfig();
    final reinstall = physics != _physics;
    final stop = _kinetic && !kinetic;
    _kinetic = kinetic;
    _physics = physics;
    if (_engineInstalled && (reinstall || stop)) {
      _queue(
        reinstall
            ? buildPremiumKineticScrollEngineScript(config: _physics)
            : buildPremiumKineticStopCommand(),
      );
    }
  }

  @override
  void didUpdateWidget(EmailBodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    // Every callback checks this: a platform call that lands after the native
    // view is gone is what takes the renderer down.
    _closing = true;
    _pending.clear();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _controller = null;
    super.dispose();
  }

  void _watchRouteAnimation() {
    if (_ready) {
      return;
    }
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _ready = true;
      return;
    }
    if (identical(animation, _routeAnimation)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation..addStatusListener(_onRouteStatus);
    Future<void>.delayed(_readyBackstop, _markReady);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _markReady();
      return;
    }
    // Tear the renderer down before the closing fade rather than during it.
    if (status == AnimationStatus.reverse && _alive && _ready) {
      _controller = null;
      _loaded = null;
      _engineInstalled = false;
      setState(() => _ready = false);
    }
  }

  void _markReady() {
    if (_alive && !_ready) {
      setState(() => _ready = true);
    }
  }

  Future<void> _load() async {
    final controller = _controller;
    if (!_alive || controller == null || _loaded == widget.html) {
      return;
    }
    _loaded = widget.html;
    _engineInstalled = false;
    _pending.clear();
    try {
      await controller.loadData(data: widget.html);
    } catch (_) {
      // A view that went away mid-load is not worth reporting.
    }
  }

  Future<bool> _installEngine(InAppWebViewController controller) async {
    if (_engineInstalled) {
      return true;
    }
    try {
      final installed = await controller.evaluateJavascript(
        source: '''
${buildPremiumKineticScrollEngineScript(config: _physics)}
typeof globalThis.$premiumKineticJavaScriptObjectName === 'object';
''',
      );
      _engineInstalled = installed == true;
      if (!_engineInstalled) {
        Log.warn('The message reader could not install kinetic scrolling');
      }
    } on PlatformException catch (error) {
      Log.warn('The message reader could not be scrolled: $error');
    }
    return _engineInstalled;
  }

  void _queue(String command) {
    if (!_drivesScrolling) {
      return;
    }
    _pending.add(command);
    if (!_flushing) {
      unawaited(_flush());
    }
  }

  Future<void> _flush() async {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      while (_alive && _pending.isNotEmpty) {
        final controller = _controller;
        if (controller == null) {
          _pending.clear();
          return;
        }
        if (!await _installEngine(controller)) {
          _pending.clear();
          return;
        }
        final batch = List<String>.of(_pending);
        _pending.clear();
        // A reload takes the engine with it and leaves no error behind, so the
        // batch reports whether it found one.
        final ran = await controller.evaluateJavascript(
          source: '''
(function () {
  if (!globalThis.$premiumKineticJavaScriptObjectName) {
    return false;
  }
${batch.join('\n')}
  return true;
})();
''',
        );
        if (ran != true) {
          _engineInstalled = false;
        }
      }
    } on PlatformException catch (error) {
      _pending.clear();
      Log.warn('The message reader could not be scrolled: $error');
    } finally {
      _flushing = false;
    }
  }

  Offset _localPosition(PointerEvent event) {
    final box = _viewportKey.currentContext?.findRenderObject();
    return box is RenderBox
        ? box.globalToLocal(event.position)
        : event.localPosition;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _queue(
      _kinetic
          ? buildPremiumKineticWheelCommand(
              event.scrollDelta,
              kind: event.kind,
              position: _localPosition(event),
            )
          : buildPremiumKineticPanCommand(
              event.scrollDelta,
              position: _localPosition(event),
            ),
    );
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _tracker = MacOSScrollViewFlingVelocityTracker(PointerDeviceKind.trackpad)
      ..addPosition(event.timeStamp, Offset.zero);
    if (_kinetic) {
      _queue(
        buildPremiumKineticBeginPanCommand(position: _localPosition(event)),
      );
    }
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _tracker ??=
        MacOSScrollViewFlingVelocityTracker(PointerDeviceKind.trackpad);
    _tracker!.addPosition(event.timeStamp, event.localPan);
    _queue(
      buildPremiumKineticPanCommand(
        -event.localPanDelta,
        position: _localPosition(event),
      ),
    );
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    final tracker = _tracker;
    _tracker = null;
    if (!_kinetic || tracker == null) {
      return;
    }
    _queue(
      buildPremiumKineticReleaseCommand(-tracker.getVelocity().pixelsPerSecond),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (!_ready ||
              constraints.maxWidth < _minimumSurface ||
              constraints.maxHeight < _minimumSurface) {
            return const SizedBox.expand();
          }
          return PremiumScrollExclusion(
            child: PdfEmbedScrollGuard(
              onPointerSignal: _onPointerSignal,
              onPointerPanZoomStart: _onPanZoomStart,
              onPointerPanZoomUpdate: _onPanZoomUpdate,
              onPointerPanZoomEnd: _onPanZoomEnd,
              child: SizedBox.expand(
                key: _viewportKey,
                child: InAppWebView(
                  initialData: InAppWebViewInitialData(data: widget.html),
                  initialSettings: InAppWebViewSettings(
                    // The message's own scripts are stripped out and forbidden
                    // by its policy; this is what lets AppFlowy's scrolling run
                    // beside the document.
                    javaScriptEnabled: _drivesScrolling,
                    supportZoom: false,
                    transparentBackground: true,
                    useShouldOverrideUrlLoading: true,
                    // The page is moved by the engine, not by the platform.
                    disableHorizontalScroll: _drivesScrolling,
                    disableVerticalScroll: _drivesScrolling,
                  ),
                  onWebViewCreated: (controller) {
                    if (!_alive) {
                      return;
                    }
                    _controller = controller;
                    _loaded = widget.html;
                  },
                  onLoadStop: (controller, _) async {
                    if (!_alive || controller != _controller) {
                      return;
                    }
                    _engineInstalled = false;
                    await _installEngine(controller);
                  },
                  shouldOverrideUrlLoading: (controller, action) async {
                    final uri = action.request.url;
                    if (uri == null) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    // The document itself is the only thing that renders here;
                    // following a link is the browser's job.
                    if (uri.scheme == 'about' || uri.scheme == 'data') {
                      return NavigationActionPolicy.ALLOW;
                    }
                    unawaited(afLaunchUrlString(uri.toString()));
                    return NavigationActionPolicy.CANCEL;
                  },
                  onCreateWindow: (controller, action) async {
                    final uri = action.request.url;
                    if (uri != null) {
                      unawaited(afLaunchUrlString(uri.toString()));
                    }
                    return true;
                  },
                  // Nothing in a message may ask for a camera or a location:
                  // the default response denies every resource.
                  onPermissionRequest: (_, __) async => PermissionResponse(),
                ),
              ),
            ),
          );
        },
      );
}

/// The strip above a blocked message offering to fetch what was held back.
class EmailRemoteContentBar extends StatelessWidget {
  const EmailRemoteContentBar({
    super.key,
    required this.count,
    required this.theme,
    required this.onLoad,
    required this.message,
    required this.actionLabel,
  });

  final int count;
  final EmailTheme theme;
  final VoidCallback onLoad;
  final String message;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: EmailMetrics.space3),
        padding: const EdgeInsets.fromLTRB(
          EmailMetrics.space3,
          EmailMetrics.space2,
          EmailMetrics.space2,
          EmailMetrics.space2,
        ),
        decoration: BoxDecoration(
          color: theme.accent.withValues(alpha: theme.isDark ? 0.16 : 0.09),
          borderRadius: BorderRadius.circular(EmailMetrics.controlRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.privacy_tip_rounded, size: 15, color: theme.accent),
            const SizedBox(width: EmailMetrics.space2),
            Expanded(
              child: Text(
                message,
                style: theme.meta.copyWith(color: theme.textBody, height: 1.4),
              ),
            ),
            const SizedBox(width: EmailMetrics.space2),
            EmailAction(
              icon: Icons.image_rounded,
              tooltip: actionLabel,
              theme: theme,
              label: actionLabel,
              active: true,
              onPressed: onLoad,
            ),
          ],
        ),
      );
}
