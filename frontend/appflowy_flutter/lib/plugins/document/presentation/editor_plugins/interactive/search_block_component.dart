import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_text.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Where a search block looks.
enum SearchScope {
  /// The page the block is on. Results open at the paragraph they were found
  /// in.
  page,

  /// Every page, file, table and collection in the workspace, matched on name.
  workspace;

  static SearchScope fromValue(Object? value) => SearchScope.values.firstWhere(
        (s) => s.name == value,
        orElse: () => SearchScope.page,
      );

  String get label => switch (this) {
        SearchScope.page => LocaleKeys.interactive_search_scopePage.tr(),
        SearchScope.workspace =>
          LocaleKeys.interactive_search_scopeWorkspace.tr(),
      };

  IconData get icon => switch (this) {
        SearchScope.page => Icons.article_rounded,
        SearchScope.workspace => Icons.workspaces_rounded,
      };
}

class SearchBlockKeys {
  const SearchBlockKeys._();

  static const String type = 'interactive_search';

  static const String placeholder = 'placeholder';

  /// One of [SearchScope].
  static const String scope = 'scope';
}

Node searchNode({SearchScope scope = SearchScope.page}) => Node(
      type: SearchBlockKeys.type,
      attributes: {
        SearchBlockKeys.scope: scope.name,
        InteractiveBlockKeys.size: InteractiveSize.medium.name,
      },
    );

/// One paragraph a query was found in.
@immutable
class PageSearchHit {
  const PageSearchHit({
    required this.path,
    required this.text,
    required this.start,
    required this.end,
  });

  final Path path;
  final String text;
  final int start;
  final int end;
}

/// Every match of [query] in the page, in reading order.
///
/// Pure, so the block's behaviour can be tested without an editor on screen.
List<PageSearchHit> searchDocument(
  Node root,
  String query, {
  int limit = 40,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const [];
  }
  final hits = <PageSearchHit>[];

  void walk(Node node) {
    if (hits.length >= limit) {
      return;
    }
    final delta = node.delta;
    if (delta != null) {
      final text = delta.toPlainText();
      for (final match in findMatches(text, trimmed, const FindOptions())) {
        hits.add(
          PageSearchHit(
            path: node.path,
            text: text,
            start: match.start,
            end: match.end,
          ),
        );
        if (hits.length >= limit) {
          return;
        }
      }
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  for (final child in root.children) {
    walk(child);
  }
  return hits;
}

/// The words either side of a match, so a result reads as a sentence.
String searchHitSnippet(PageSearchHit hit, {int radius = 34}) {
  final from = (hit.start - radius).clamp(0, hit.text.length);
  final to = (hit.end + radius).clamp(0, hit.text.length);
  final buffer = StringBuffer();
  if (from > 0) {
    buffer.write('…');
  }
  buffer.write(hit.text.substring(from, to).replaceAll('\n', ' '));
  if (to < hit.text.length) {
    buffer.write('…');
  }
  return buffer.toString();
}

/// The objects whose name matches [query], best first.
///
/// A name that starts with the query beats one that merely contains it, and a
/// shorter name beats a longer one that matched the same way. Pure, so the
/// ranking can be tested without a workspace.
List<ViewPB> rankWorkspaceMatches(
  List<ViewPB> views,
  String query, {
  int limit = 40,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return const [];
  }

  final scored = <(int, int, ViewPB)>[];
  for (final view in views) {
    final name = view.name.toLowerCase();
    if (name.isEmpty) {
      continue;
    }
    final at = name.indexOf(needle);
    if (at < 0) {
      continue;
    }
    // 0 exact, 1 starts with, 2 starts a word, 3 anywhere.
    final rank = name == needle
        ? 0
        : at == 0
            ? 1
            : _startsAWord(name, at)
                ? 2
                : 3;
    scored.add((rank, name.length, view));
  }

  scored.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    if (byRank != 0) {
      return byRank;
    }
    final byLength = a.$2.compareTo(b.$2);
    return byLength != 0 ? byLength : a.$3.name.compareTo(b.$3.name);
  });

  return scored.take(limit).map((entry) => entry.$3).toList();
}

bool _startsAWord(String name, int at) {
  final before = name.codeUnitAt(at - 1);
  return before == 0x20 || // space
      before == 0x2D || // -
      before == 0x5F || // _
      before == 0x2E || // .
      before == 0x2F; // /
}

class SearchBlockComponentBuilder extends BlockComponentBuilder {
  SearchBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return SearchBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class SearchBlockComponent extends BlockComponentStatefulWidget {
  const SearchBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<SearchBlockComponent> createState() => SearchBlockComponentState();
}

class SearchBlockComponentState extends State<SearchBlockComponent>
    with BlockComponentConfigurable, InteractiveBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  static const int _shown = 6;

  final FocusNode _focus = FocusNode(debugLabel: 'interactive search');

  String _query = '';
  bool _focused = false;
  bool _hovered = false;

  /// Every object in the workspace, read once and then filtered here, so
  /// typing does not fire a request per keystroke.
  List<ViewPB> _workspace = const [];
  bool _loadingWorkspace = false;
  bool _loadedWorkspace = false;

  SearchScope get _scope =>
      SearchScope.fromValue(node.attributes[SearchBlockKeys.scope]);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Opens the field. `/search` calls it so the block lands ready to type.
  void focusField() {
    _focus.requestFocus();
    unawaited(_ensureWorkspace());
  }

  Future<void> _ensureWorkspace() async {
    if (_scope != SearchScope.workspace ||
        _loadedWorkspace ||
        _loadingWorkspace) {
      return;
    }
    _loadingWorkspace = true;
    final result = await const WorkspaceItemService().getAllViews();
    if (!mounted) {
      return;
    }
    setState(() {
      _loadingWorkspace = false;
      _loadedWorkspace = true;
      _workspace = result.fold((views) => views, (_) => const <ViewPB>[]);
    });
  }

  List<PageSearchHit> get _pageHits =>
      searchDocument(editorState.document.root, _query);

  List<ViewPB> get _workspaceHits => rankWorkspaceMatches(_workspace, _query);

  void _openHit(PageSearchHit hit) {
    editorState.updateSelectionWithReason(
      Selection(
        start: Position(path: hit.path, offset: hit.start),
        end: Position(path: hit.path, offset: hit.end),
      ),
      reason: SelectionUpdateReason.uiEvent,
    );
  }

  void _openView(ViewPB view) => context.read<TabsBloc>().openPlugin(view);

  List<AppMenuEntry> _menu() => interactiveMenuEntries(
        extra: [
          AppMenuItem(
            label: LocaleKeys.interactive_search_scope.tr(),
            icon: Icons.travel_explore_rounded,
            subtitle: _scope.label,
            submenu: [
              for (final scope in SearchScope.values)
                AppMenuItem(
                  label: scope.label,
                  icon: scope.icon,
                  selected: scope == _scope,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({SearchBlockKeys.scope: scope.name})
                        .then((_) => _ensureWorkspace()),
                  ),
                ),
            ],
          ),
          if (_scope == SearchScope.workspace)
            AppMenuItem(
              label: LocaleKeys.interactive_search_refresh.tr(),
              icon: Icons.refresh_rounded,
              onSelected: () {
                _loadedWorkspace = false;
                unawaited(_ensureWorkspace());
              },
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final tone = accent.resolve(palette);

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel: LocaleKeys.interactive_search_name.tr(),
        menuBuilder: _menu,
        child: InteractiveFocusGuard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              MouseRegion(
                opaque: false,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: InteractiveFieldSurface(
                  focused: _focused,
                  hovered: _hovered,
                  palette: palette,
                  height: 44,
                  radius: 999,
                  accent: tone.strong,
                  fill: Color.alphaBlend(
                    tone.strong.withValues(
                      alpha: accent == InteractiveAccent.neutral
                          ? (palette.isDark ? 0.06 : 0.035)
                          : (palette.isDark ? 0.12 : 0.07),
                    ),
                    palette.surface,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: InteractiveMetrics.hover,
                        curve: InteractiveMetrics.curve,
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: tone.strong
                              .withValues(alpha: _focused ? 0.20 : 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          size: 16,
                          color: tone.strong,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InteractiveEditableText(
                          focusNode: _focus,
                          value: '',
                          palette: palette,
                          hint: stringAttribute(
                            SearchBlockKeys.placeholder,
                            fallback: _scope == SearchScope.page
                                ? LocaleKeys.interactive_search_hintPage.tr()
                                : LocaleKeys.interactive_search_hintWorkspace
                                    .tr(),
                          ),
                          style: InteractiveType.body(palette)
                              .copyWith(fontSize: 14.5),
                          onLiveChanged: (value) {
                            setState(() => _query = value);
                            unawaited(_ensureWorkspace());
                          },
                          onFocusChanged: (value) {
                            setState(() => _focused = value);
                            if (value) {
                              unawaited(_ensureWorkspace());
                            }
                          },
                          onChanged: (_) {},
                          onSubmitted: (_) {
                            if (_scope == SearchScope.workspace) {
                              final hits = _workspaceHits;
                              if (hits.isNotEmpty) {
                                _openView(hits.first);
                              }
                            } else {
                              final hits = _pageHits;
                              if (hits.isNotEmpty) {
                                _openHit(hits.first);
                              }
                            }
                          },
                        ),
                      ),
                      if (_query.isNotEmpty)
                        InteractiveIconButton(
                          icon: Icons.cancel_rounded,
                          tooltip: LocaleKeys.interactive_input_clear.tr(),
                          palette: palette,
                          iconSize: 15,
                          onPressed: () => setState(() => _query = ''),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 8, left: 4),
                          child: Text(
                            _scope.label,
                            style: InteractiveType.caption(palette)
                                .copyWith(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: InteractiveMetrics.reveal,
                curve: InteractiveMetrics.curve,
                alignment: Alignment.topCenter,
                child: _buildResults(palette, tone),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(InteractivePalette palette, InteractiveTone tone) {
    if (_query.trim().isEmpty) {
      return const SizedBox(width: double.infinity);
    }

    if (_scope == SearchScope.workspace && !_loadedWorkspace) {
      return _Panel(
        palette: palette,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tone.strong,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              LocaleKeys.interactive_search_loading.tr(),
              style: InteractiveType.caption(palette),
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[];
    int total;

    if (_scope == SearchScope.page) {
      final hits = _pageHits;
      total = hits.length;
      for (final hit in hits.take(_shown)) {
        rows.add(
          _ResultRow(
            title: searchHitSnippet(hit),
            palette: palette,
            leading: Icon(
              Icons.subject_rounded,
              size: 15,
              color: palette.textMuted,
            ),
            onTap: () => _openHit(hit),
          ),
        );
      }
    } else {
      final hits = _workspaceHits;
      total = hits.length;
      for (final view in hits.take(_shown)) {
        rows.add(
          _ResultRow(
            title: view.name.isEmpty
                ? LocaleKeys.interactive_search_untitled.tr()
                : view.name,
            palette: palette,
            leading: WorkspaceItemIcon.fromView(
              view: view,
              size: 16,
              color: palette.textSecondary,
            ),
            onTap: () => _openView(view),
          ),
        );
      }
    }

    if (rows.isEmpty) {
      return _Panel(
        palette: palette,
        child: Row(
          children: [
            Icon(Icons.search_off_rounded, size: 15, color: palette.textMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _scope == SearchScope.page
                    ? LocaleKeys.interactive_search_noResults.tr()
                    : LocaleKeys.interactive_search_noWorkspaceResults.tr(),
                style: InteractiveType.caption(palette),
              ),
            ),
          ],
        ),
      );
    }

    return _Panel(
      palette: palette,
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...rows,
          if (total > _shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Text(
                LocaleKeys.interactive_search_more
                    .tr(args: ['${total - _shown}']),
                style: InteractiveType.caption(palette),
              ),
            ),
        ],
      ),
    );
  }
}

/// The soft card the results are listed on.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
  });

  final InteractivePalette palette;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: palette.isDark ? 0.30 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -12,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _ResultRow extends StatefulWidget {
  const _ResultRow({
    required this.title,
    required this.palette,
    required this.leading,
    required this.onTap,
  });

  final String title;
  final InteractivePalette palette;
  final Widget leading;
  final VoidCallback onTap;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: InteractiveMetrics.hover,
          curve: InteractiveMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(width: 18, child: Center(child: widget.leading)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InteractiveType.body(palette).copyWith(fontSize: 13),
                ),
              ),
              AnimatedOpacity(
                duration: InteractiveMetrics.hover,
                opacity: _hovered ? 1 : 0,
                child: Icon(
                  Icons.north_east_rounded,
                  size: 14,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
