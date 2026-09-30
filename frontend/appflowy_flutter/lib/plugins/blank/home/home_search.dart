import 'dart:math' as math;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

/// Where the search panel sits over the Home search bar: centred on it,
/// never off screen, and tall enough for results even near the bottom.
Rect homeSearchPanelRect({
  required Rect anchor,
  required Size viewport,
  double inset = WorkspaceTokens.space6,
  double margin = WorkspaceTokens.space4,
}) {
  final available = math.max(0.0, viewport.width - margin * 2);
  final width = math.min(
    available,
    math.min(1040.0, math.max(640.0, anchor.width + inset * 2)),
  );
  final left = (anchor.center.dx - width / 2)
      .clamp(margin, math.max(margin, viewport.width - margin - width))
      .toDouble();
  const preferredHeight = 600.0;
  const minimumHeight = 360.0;
  var top = math.max(margin, anchor.top - inset);
  var height = math.min(preferredHeight, viewport.height - margin - top);
  if (height < minimumHeight) {
    height =
        math.max(0.0, math.min(minimumHeight, viewport.height - margin * 2));
    top = math.max(margin, viewport.height - margin - height);
  }
  return Rect.fromLTWH(left, top, width, math.max(0.0, height));
}

Rect? _anchorRect(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Whether the workspace search can open from Home in this shell.
bool canShowHomeSearch(BuildContext context) =>
    context.read<CommandPaletteBloc?>() != null;

/// Opens the workspace search — the same results, filters, previews and
/// commands as the search popup — as a panel over the Home search bar.
Future<void> showHomeSearch(
  BuildContext context, {
  required GlobalKey anchorKey,
  String initialQuery = '',
  bool contents = false,
}) async {
  final bloc = context.read<CommandPaletteBloc?>();
  final initialRect = _anchorRect(anchorKey);
  if (bloc == null || bloc.isClosed || initialRect == null) return;
  final workspaceBloc = context.read<UserWorkspaceBloc?>();
  final spaceBloc = context.read<SpaceBloc?>();
  bloc.add(const CommandPaletteEvent.refreshCachedViews());
  final navigator = Navigator.of(context, rootNavigator: true);
  final palette = WorkspacePalette.of(context);
  await navigator.push<void>(
    _HomeSearchRoute(
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor: palette.shadow.withValues(alpha: palette.isDark ? .16 : .1),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      reduceMotion: WorkspaceTokens.motion(
            context,
            WorkspaceTokens.hoverDuration,
          ) ==
          Duration.zero,
      // Re-measured at layout, so a resized window keeps the panel on the bar.
      anchor: () => _anchorRect(anchorKey) ?? initialRect,
      builder: (context, size) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: bloc),
          if (workspaceBloc != null) BlocProvider.value(value: workspaceBloc),
          if (spaceBloc != null) BlocProvider.value(value: spaceBloc),
        ],
        child: CommandPaletteModal(
          shortcutBuilder: (child) => _HomeSearchShortcuts(child: child),
          initialQuery: initialQuery,
          initialFilter:
              contents ? const CommandPaletteFilter(pageContents: true) : null,
          anchoredSize: size,
        ),
      ),
    ),
  );
}

/// The palette shortcut closes this panel rather than stacking a second
/// search over it.
class _HomeSearchShortcuts extends StatelessWidget {
  const _HomeSearchShortcuts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          SingleActivator(
            LogicalKeyboardKey.keyP,
            control: !UniversalPlatform.isMacOS,
            meta: UniversalPlatform.isMacOS,
          ): () {
            final route = ModalRoute.of(context);
            if (route != null && route.isCurrent) route.navigator?.pop();
          },
        },
        child: child,
      );
}

class _HomeSearchRoute extends PopupRoute<void> {
  _HomeSearchRoute({
    required this.themes,
    required Color barrierColor,
    required String barrierLabel,
    required this.reduceMotion,
    required this.anchor,
    required this.builder,
  })  : _barrierColor = barrierColor,
        _barrierLabel = barrierLabel;

  final CapturedThemes themes;
  final bool reduceMotion;
  final Rect Function() anchor;
  final Widget Function(BuildContext context, Size size) builder;
  final Color _barrierColor;
  final String _barrierLabel;

  @override
  Color? get barrierColor => _barrierColor;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => _barrierLabel;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 150);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      themes.wrap(
        // A layout callback reads the bar after it has been laid out.
        LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            final rect = homeSearchPanelRect(
              anchor: anchor(),
              viewport: viewport,
              inset: viewport.width < 640
                  ? WorkspaceTokens.space4
                  : WorkspaceTokens.space6,
            );
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: builder(context, rect.size),
                ),
              ],
            );
          },
        ),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final progress = Curves.easeOutCubic.transform(animation.value);
          return Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, -6 * (1 - progress)),
              child: child,
            ),
          );
        },
      );
}

/// A native-looking search field on the page. It opens the workspace search
/// in place, carrying over whatever was typed while it had focus.
class HomeSearchBar extends StatefulWidget {
  const HomeSearchBar({super.key, required this.onSearch});

  /// Null when this shell cannot search; the bar is then shown disabled.
  final void Function(GlobalKey anchor, String initialQuery, bool contents)?
      onSearch;

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  final _anchor = GlobalKey(debugLabel: 'Home search bar');
  final _focusNode = FocusNode(debugLabel: 'Home search bar');
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _open({String initialQuery = '', bool contents = false}) =>
      widget.onSearch?.call(_anchor, initialQuery, contents);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.onSearch == null) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _open();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final character = event.character;
    if (character != null &&
        character.trim().isNotEmpty &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        character.runes.every((rune) => rune >= 0x20 && rune != 0x7F)) {
      // Typing starts a search with that very letter, like a real field.
      _open(initialQuery: character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final enabled = widget.onSearch != null;
    final active = enabled && (_hovered || _focused);
    final radius = BorderRadius.circular(28);
    final hint = WorkspaceTypography.style(
      context,
      WorkspaceTextRole.body,
      color: palette.mutedText,
    ).copyWith(fontSize: 15);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: LocaleKeys.landing_searchLabel.tr(),
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: enabled,
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.text : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            key: const ValueKey('home-search-bar'),
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _open : null,
            child: AnimatedContainer(
              key: _anchor,
              duration: WorkspaceTokens.motion(
                context,
                WorkspaceTokens.hoverDuration,
              ),
              curve: WorkspaceTokens.curve,
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 8, 6),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: radius,
                border: Border.all(
                  color: _focused
                      ? palette.focus
                      : active
                          ? palette.secondaryText.withValues(alpha: 0.35)
                          : palette.border,
                  width: _focused ? 1.5 : 1,
                ),
                boxShadow: palette.elevation(raised: active),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final roomy = constraints.maxWidth >=
                      MediaQuery.textScalerOf(context).scale(480);
                  return Row(
                    children: [
                      WorkspaceGlyph(
                        Icons.search_rounded,
                        size: 20,
                        color: palette.secondaryText,
                      ),
                      const SizedBox(width: WorkspaceTokens.space3),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            LocaleKeys.landing_searchHint.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: hint,
                          ),
                        ),
                      ),
                      if (roomy && enabled) ...[
                        const SizedBox(width: WorkspaceTokens.space2),
                        Tooltip(
                          message: LocaleKeys.landing_deepSearchTooltip.tr(),
                          child: TextButton.icon(
                            key: const ValueKey('home-search-deep'),
                            onPressed: () => _open(contents: true),
                            style: TextButton.styleFrom(
                              foregroundColor: palette.secondaryText,
                              backgroundColor: palette.hover,
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: WorkspaceTokens.space3,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: WorkspaceTypography.style(
                                context,
                                WorkspaceTextRole.metadata,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                            icon: WorkspaceGlyph(
                              Icons.manage_search_rounded,
                              size: 16,
                              color: palette.secondaryText,
                            ),
                            label: Text(LocaleKeys.landing_deepSearch.tr()),
                          ),
                        ),
                        const SizedBox(width: WorkspaceTokens.space2),
                        ExcludeSemantics(
                          child: _Keycap(
                            label: UniversalPlatform.isMacOS ? '⌘ P' : 'Ctrl P',
                          ),
                        ),
                        const SizedBox(width: WorkspaceTokens.space2),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Keycap extends StatelessWidget {
  const _Keycap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: WorkspaceTypography.style(context, WorkspaceTextRole.caption),
        ),
      ),
    );
  }
}
