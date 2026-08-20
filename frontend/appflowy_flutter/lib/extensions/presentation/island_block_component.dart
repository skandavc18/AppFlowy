import 'dart:async';
import 'dart:convert';

import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/application/island_server.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

class ExtensionIslandBlockKeys {
  const ExtensionIslandBlockKeys._();

  static const String type = 'extension_island';

  /// Which extension owns the page being shown.
  static const String extensionId = 'extension';

  /// The folder under that extension's `web/`.
  static const String island = 'island';

  static const String width = 'width';
  static const String height = 'height';

  /// The block's own stored settings, handed to the page on start.
  static const String settings = 'settings';
}

Node extensionIslandNode({
  required String extensionId,
  required String island,
  double? width,
  double height = 360,
  Map<String, Object?> settings = const {},
}) =>
    Node(
      type: ExtensionIslandBlockKeys.type,
      attributes: {
        ExtensionIslandBlockKeys.extensionId: extensionId,
        ExtensionIslandBlockKeys.island: island,
        if (width != null) ExtensionIslandBlockKeys.width: width,
        ExtensionIslandBlockKeys.height: height,
        ExtensionIslandBlockKeys.settings: settings,
      },
    );

class ExtensionIslandBlockComponentBuilder extends BlockComponentBuilder {
  ExtensionIslandBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ExtensionIslandBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) =>
      node.children.isEmpty &&
      (node.attributes[ExtensionIslandBlockKeys.island] as String?)
              ?.isNotEmpty ==
          true;
}

/// An extension's own page, drawn by a renderer inside the document.
///
/// This is the escape hatch: anything a declarative widget cannot draw — a
/// candlestick chart, a canvas, a live dashboard — is HTML and JavaScript here,
/// under a policy that gives it no way out except the bridge.
class ExtensionIslandBlockComponent extends BlockComponentStatefulWidget {
  const ExtensionIslandBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ExtensionIslandBlockComponent> createState() =>
      _ExtensionIslandBlockComponentState();
}

class _ExtensionIslandBlockComponentState
    extends State<ExtensionIslandBlockComponent>
    with BlockComponentConfigurable {
  /// ⚠️ Below this a composition surface is degenerate and Windows faults in
  /// `dcomp.dll`. Nothing is built until the box is real.
  static const double minimumSurface = 64;

  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  InAppWebViewController? _controller;
  Uri? _url;
  String _problem = '';
  bool _loading = true;

  /// ⚠️ Every platform callback checks this. A late call into a view that is
  /// going away is an access violation in the Windows plugin.
  bool _closing = false;

  bool _routeSettled = false;
  Timer? _routeBackstop;
  Animation<double>? _routeAnimation;

  final Set<String> _watched = {};
  VoidCallback? _dataListener;

  String get _extensionId =>
      node.attributes[ExtensionIslandBlockKeys.extensionId] as String? ?? '';

  String get _island =>
      node.attributes[ExtensionIslandBlockKeys.island] as String? ?? '';

  Map<String, Object?> get _settings {
    final stored = node.attributes[ExtensionIslandBlockKeys.settings];
    return stored is Map ? Map<String, Object?>.from(stored) : {};
  }

  double? get _width =>
      (node.attributes[ExtensionIslandBlockKeys.width] as num?)?.toDouble();

  double get _height =>
      (node.attributes[ExtensionIslandBlockKeys.height] as num?)?.toDouble() ??
      360;

  @override
  void initState() {
    super.initState();
    _dataListener = _onDataChanged;
    ExtensionDataStore.instance.revision.addListener(_dataListener!);
    unawaited(_resolve());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ⚠️ Creating a platform view while a route is still animating takes the
    // Windows renderer down. A listener attached to a route that is already
    // settling never fires, so a timer backs it up.
    if (_routeSettled) {
      return;
    }
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _routeSettled = true;
      return;
    }
    _routeAnimation = animation..addListener(_onRouteChanged);
    _routeBackstop ??= Timer(const Duration(milliseconds: 450), () {
      if (mounted && !_routeSettled) {
        setState(() => _routeSettled = true);
      }
    });
  }

  void _onRouteChanged() {
    final animation = _routeAnimation;
    if (animation == null) {
      return;
    }
    if (animation.status == AnimationStatus.reverse) {
      // Tear down BEFORE the closing fade, never during it.
      _closing = true;
      _controller = null;
      return;
    }
    if (animation.status == AnimationStatus.completed && !_routeSettled) {
      if (mounted) {
        setState(() => _routeSettled = true);
      }
    }
  }

  @override
  void dispose() {
    _closing = true;
    _routeBackstop?.cancel();
    _routeAnimation?.removeListener(_onRouteChanged);
    final listener = _dataListener;
    if (listener != null) {
      ExtensionDataStore.instance.revision.removeListener(listener);
    }
    _controller = null;
    super.dispose();
  }

  Future<void> _resolve() async {
    final store = ExtensionStore.instance;
    await store.ensureLoaded();
    final extension = store.byId(_extensionId);
    if (extension == null) {
      _fail('There is no extension called "$_extensionId".');
      return;
    }
    if (!store.isEnabled(_extensionId)) {
      _fail('${extension.manifest.name} is turned off.');
      return;
    }
    final url =
        await IslandServer.of(_extensionId, extension.folder).urlFor(_island);
    if (url == null) {
      _fail('"$_island" has no index.html in ${extension.manifest.name}.');
      return;
    }
    if (!mounted || _closing) {
      return;
    }
    setState(() {
      _url = url;
      _problem = '';
    });
  }

  void _fail(String problem) {
    if (!mounted || _closing) {
      return;
    }
    setState(() {
      _problem = problem;
      _loading = false;
    });
  }

  void _onDataChanged() {
    if (_closing || _watched.isEmpty) {
      return;
    }
    for (final key in _watched) {
      unawaited(_pushData(key));
    }
  }

  Future<void> _pushData(String key) async {
    final controller = _controller;
    if (controller == null || _closing) {
      return;
    }
    final qualified = ExtensionDataStore.qualify(_extensionId, key);
    final value = ExtensionDataStore.instance.read(qualified);
    await _evaluate(
      '__afIslandData(${jsonEncode(key)}, ${jsonEncode(value)});',
    );
  }

  Future<void> _evaluate(String source) async {
    final controller = _controller;
    if (controller == null || _closing) {
      return;
    }
    try {
      await controller.evaluateJavascript(source: source);
    } on Object catch (error) {
      Log.warn('An island could not be reached: $error');
    }
  }

  Future<void> _onMessage(List<dynamic> arguments) async {
    if (_closing || arguments.isEmpty) {
      return;
    }
    final raw = arguments.first;
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) {
      return;
    }
    final message = Map<String, Object?>.from(decoded);

    switch (message['kind']) {
      case 'ready':
        await _evaluate(
          '__afIslandStart(${jsonEncode(_settings)}, '
          '${jsonEncode(_themeTokens())});',
        );
      case 'watch':
        final key = '${message['key'] ?? ''}';
        if (key.isNotEmpty && _watched.add(key)) {
          await _pushData(key);
        }
      case 'setting':
        _writeSetting('${message['key'] ?? ''}', message['value']);
      case 'call':
        await _runAction(message);
    }
  }

  Future<void> _runAction(Map<String, Object?> message) async {
    final id = '${message['id'] ?? ''}';
    final action = '${message['action'] ?? ''}';
    final args = message['args'];

    final run = await ActionScheduler.instance.runNow(
      extensionId: _extensionId,
      actionId: action,
      arguments: args is Map ? Map<String, Object?>.from(args) : const {},
      cause: ActionRunCause.island,
    );

    final ok = run.status == ActionRunStatus.ok ||
        run.status == ActionRunStatus.skipped;
    await _evaluate(
      '__afIslandResolve(${jsonEncode(id)}, $ok, '
      '${jsonEncode(ok ? run.status.name : run.message)});',
    );
  }

  void _writeSetting(String key, Object? value) {
    if (key.isEmpty || !mounted) {
      return;
    }
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction
      ..updateNode(node, {
        ExtensionIslandBlockKeys.settings: {..._settings, key: value},
      });
    unawaited(editorState.apply(transaction));
  }

  Map<String, String> _themeTokens() {
    final theme = Theme.of(context);
    // ⚠️ `Color.toARGB32()` does not exist in this Flutter version.
    String hex(Color color) {
      final r = (color.r * 255).round().clamp(0, 255);
      final g = (color.g * 255).round().clamp(0, 255);
      final b = (color.b * 255).round().clamp(0, 255);
      return '#'
          '${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}';
    }

    return {
      'background': hex(theme.colorScheme.surface),
      'surface': hex(theme.colorScheme.surfaceContainerLowest),
      'text': hex(theme.colorScheme.onSurface),
      'muted': hex(theme.colorScheme.onSurfaceVariant),
      'accent': hex(theme.colorScheme.primary),
      'error': hex(theme.colorScheme.error),
      'scheme': theme.brightness == Brightness.dark ? 'dark' : 'light',
    };
  }

  @override
  Widget build(BuildContext context) {
    Widget child = _buildStage(context);

    child = ResizableMedia(
      width: _width ?? double.infinity,
      height: _height,
      alignment: blockEmbedAlignment(node),
      onResize: (value) => _writeSize(ExtensionIslandBlockKeys.width, value),
      onResizeHeight: (value) =>
          _writeSize(ExtensionIslandBlockKeys.height, value),
      child: child,
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }
    return child;
  }

  void _writeSize(String key, double value) {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction..updateNode(node, {key: value});
    unawaited(editorState.apply(transaction));
  }

  Widget _buildStage(BuildContext context) {
    final theme = Theme.of(context);
    if (_problem.isNotEmpty) {
      return _IslandMessage(text: _problem, theme: theme);
    }

    final url = _url;
    if (url == null || !_routeSettled) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // ⚠️ A composition surface smaller than this faults on Windows.
        if (constraints.maxWidth < minimumSurface ||
            constraints.maxHeight < minimumSurface) {
          return const SizedBox.shrink();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              // ⚠️ NO key on this view. A changing key destroys and recreates
              // the composition surface, which is the documented Windows
              // renderer fault.
              PremiumScrollExclusion(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(url.toString())),
                  initialSettings: InAppWebViewSettings(
                    transparentBackground: true,
                    supportZoom: false,
                  ),
                  onWebViewCreated: (controller) {
                    if (_closing) {
                      return;
                    }
                    _controller = controller;
                    controller.addJavaScriptHandler(
                      handlerName: 'afIsland',
                      callback: _onMessage,
                    );
                  },
                  onLoadStop: (_, __) {
                    if (mounted && !_closing) {
                      setState(() => _loading = false);
                    }
                  },
                  onReceivedError: (_, __, error) {
                    _fail('The page could not be opened: ${error.description}');
                  },
                  // ⚠️ Left unanswered this null-dereferences in the Windows
                  // plugin and takes the renderer down.
                  onPermissionRequest: (_, request) async =>
                      PermissionResponse(resources: request.resources),
                ),
              ),
              if (_loading)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _IslandMessage extends StatelessWidget {
  const _IslandMessage({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.extension_off_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
