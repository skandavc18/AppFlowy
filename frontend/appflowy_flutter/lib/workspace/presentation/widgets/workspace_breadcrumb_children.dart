import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// GetView returns one level of real children and enforces guest access plus
/// trash/private-section filtering in FolderManager.get_view_pb. A workspace
/// root is synthetic, so it uses the flat listing, filtered by its REAL id.
/// GetAllViews does not enforce guest sharing: never call it for a guest root.
Future<FlowyResult<List<ViewPB>, FlowyError>> loadWorkspaceBreadcrumbChildren({
  required WorkspaceItemRepository repository,
  required String parentId,
  required bool isWorkspaceRoot,
  required bool isGuest,
}) async {
  if (parentId.isEmpty || (isWorkspaceRoot && isGuest)) {
    return FlowyResult.failure(
      FlowyError(
        msg: isGuest
            ? LocaleKeys.document_mention_noAccess.tr()
            : LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      ),
    );
  }
  final result = await (isWorkspaceRoot
      ? repository.getAllViews()
      : repository.getChildren(parentId));
  return result.fold(
    (views) {
      final seen = <String>{};
      return FlowyResult.success(
        List<ViewPB>.unmodifiable([
          for (final view in views)
            if (view.parentViewId == parentId &&
                view.id.isNotEmpty &&
                view.id != parentId &&
                seen.add(view.id))
              ViewPB.fromBuffer(view.writeToBuffer())..freeze(),
        ]),
      );
    },
    FlowyResult.failure,
  );
}

/// Owns only a menu request, never a page, repository, or provider. Invalidating
/// a request also prevents its queued callbacks from navigating after rebinding.
class WorkspaceBreadcrumbMenuController {
  int _generation = 0;
  bool _disposed = false;
  Route<dynamic>? _route;

  void dismiss() {
    _generation++;
    final route = _route;
    _route = null;
    if (route != null) _removeRoute(route);
  }

  void dispose() {
    _disposed = true;
    dismiss();
  }

  Future<void> show({
    required BuildContext context,
    required ViewPB parent,
    required String workspaceId,
    required bool isGuest,
    required WorkspaceItemRepository repository,
    required bool Function() isCurrent,
    required ValueChanged<ViewPB> onSelected,
    List<ViewPB>? ancestors,
  }) async {
    if (_disposed || !context.mounted || !isCurrent()) return;
    dismiss();
    final generation = _generation;
    bool bindingIsCurrent() =>
        !_disposed && generation == _generation && isCurrent();

    try {
      final selected = await showAppMenuForWidget<ViewPB>(
        context: context,
        width: 280,
        placement: AppMenuPlacement.below,
        entries: [
          AppMenuCustom(
            builder: (menuContext) {
              final route = ModalRoute.of(menuContext);
              final covered =
                  route?.isActive == true && route?.isCurrent == false;
              if (!bindingIsCurrent() || covered) {
                if (covered && bindingIsCurrent()) {
                  _generation++;
                  _route = null;
                }
                if (route != null) _removeRoute(route);
                return const SizedBox.shrink();
              }
              _route = route;
              bool menuIsCurrent() =>
                  bindingIsCurrent() && route?.isCurrent == true;
              return _BreadcrumbChildrenMenu(
                parent: parent,
                workspaceId: workspaceId,
                isGuest: isGuest,
                repository: repository,
                ancestors: ancestors,
                isCurrent: menuIsCurrent,
                onSelected: (view) {
                  if (menuIsCurrent()) {
                    AppMenuScope.maybeOf(menuContext)?.close(view);
                  }
                },
              );
            },
          ),
        ],
      );
      // The route has already popped; check the binding, not isCurrent on the
      // retired route. No callback borrowed from an old page may run here.
      if (selected != null && bindingIsCurrent()) onSelected(selected);
    } finally {
      if (generation == _generation) {
        _route = null;
        _generation++;
      }
    }
  }

  void _removeRoute(Route<dynamic> route) {
    void remove() {
      final navigator = route.navigator;
      if (navigator != null && route.isActive) {
        if (route.isCurrent) {
          navigator.pop();
        } else {
          // Flutter 3.27 removeRoute does not complete popped. Complete ONLY
          // this owned AppMenu before removing it, so its toolbar hold is
          // released without popping a newer dialog above it.
          // ignore: invalid_use_of_protected_member
          route.didComplete(null);
          navigator.removeRoute(route);
        }
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
    } else {
      remove();
    }
  }
}

/// Saved identity takes precedence. defaultIcon already delegates to the real
/// WorkspaceItemIcon for files/collections; no surrogate folder glyphs here.
class WorkspaceBreadcrumbIcon extends StatelessWidget {
  const WorkspaceBreadcrumbIcon({
    super.key,
    required this.view,
    this.size = 17,
  });

  final ViewPB view;
  final double size;

  @override
  Widget build(BuildContext context) {
    final saved = view.icon.toEmojiIconData();
    if (saved.isNotEmpty) {
      return RawEmojiIconWidget(emoji: saved, emojiSize: size);
    }
    if (view.isSpace) {
      return SpaceIcon(
        dimension: size,
        svgSize: size * 0.65,
        space: view,
        cornerRadius: 4,
      );
    }
    return view.defaultIcon(size: Size.square(size));
  }
}

class _BreadcrumbChildrenMenu extends StatefulWidget {
  const _BreadcrumbChildrenMenu({
    required this.parent,
    required this.workspaceId,
    required this.isGuest,
    required this.repository,
    required this.isCurrent,
    required this.onSelected,
    this.ancestors,
  });

  final ViewPB parent;
  final String workspaceId;
  final bool isGuest;
  final WorkspaceItemRepository repository;
  final bool Function() isCurrent;
  final ValueChanged<ViewPB> onSelected;
  final List<ViewPB>? ancestors;

  @override
  State<_BreadcrumbChildrenMenu> createState() =>
      _BreadcrumbChildrenMenuState();
}

class _BreadcrumbChildrenMenuState extends State<_BreadcrumbChildrenMenu> {
  final _focus = FocusNode(debugLabel: 'workspace_breadcrumb_children');
  final _rowKeys = <int, GlobalKey>{};
  final _history = <(ViewPB, List<ViewPB>?)>[];
  late ViewPB _parent;
  List<ViewPB>? _ancestors;
  List<ViewPB> _views = const [];
  bool _busy = false;
  String? _error;
  int _highlighted = -1;
  int _readGeneration = 0;
  Timer? _deadline;

  bool get _current => mounted && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _parent = widget.parent;
    _ancestors = widget.ancestors;
    if (_ancestors != null) {
      _views = List.unmodifiable(_ancestors!);
    } else {
      unawaited(_load());
    }
    // AppMenu's outer focus handles static entries, not AppMenuCustom rows.
    // Explicitly focus this keyboard handler after the route's first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _readGeneration++;
    _deadline?.cancel();
    _focus.dispose();
    super.dispose();
  }

  int _beginRead() {
    final generation = ++_readGeneration;
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 15), () {
      if (!_canApply(generation)) return;
      _readGeneration++;
      _failed(LocaleKeys.error_loadingViewError.tr());
    });
    setState(() {
      _busy = true;
      _error = null;
      _highlighted = -1;
    });
    return generation;
  }

  bool _canApply(int generation) => _current && generation == _readGeneration;

  void _failed(String message) {
    _deadline?.cancel();
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  Future<void> _load() async {
    if (!_current) return;
    final generation = _beginRead();
    final parentId = _parent.id;
    try {
      final result = await loadWorkspaceBreadcrumbChildren(
        repository: widget.repository,
        parentId: parentId,
        isWorkspaceRoot: parentId == widget.workspaceId,
        isGuest: widget.isGuest,
      );
      if (!_canApply(generation)) return;
      _deadline?.cancel();
      result.fold(
        (views) => setState(() {
          _views = views;
          _busy = false;
        }),
        (error) => _failed(
          error.msg.isEmpty
              ? LocaleKeys.error_loadingViewError.tr()
              : error.msg,
        ),
      );
    } catch (_) {
      if (_canApply(generation)) {
        _failed(LocaleKeys.error_loadingViewError.tr());
      }
    }
  }

  Future<void> _choose(ViewPB view) async {
    if (!_current || _busy) return;
    if (view.id == widget.workspaceId) {
      if (!widget.isGuest) widget.onSelected(view);
      return;
    }
    final parentId = _ancestors == null ? _parent.id : null;
    final generation = _beginRead();
    try {
      final result = await widget.repository.getView(view.id);
      if (!_canApply(generation)) return;
      _deadline?.cancel();
      result.fold(
        (fresh) {
          if (fresh.id != view.id ||
              (parentId != null && fresh.parentViewId != parentId)) {
            _failed(LocaleKeys.workspaceFolderExplorer_itemUnavailable.tr());
          } else {
            widget.onSelected(fresh);
          }
        },
        (_) => _failed(LocaleKeys.workspaceFolderExplorer_itemUnavailable.tr()),
      );
    } catch (_) {
      if (_canApply(generation)) {
        _failed(LocaleKeys.error_loadingViewError.tr());
      }
    }
  }

  void _browse(ViewPB view) {
    if (!_current || _busy) return;
    _history.add((_parent, _ancestors));
    _parent = view;
    _ancestors = null;
    unawaited(_load());
  }

  void _back() {
    if (!_current || _history.isEmpty) return;
    _readGeneration++;
    _deadline?.cancel();
    final previous = _history.removeLast();
    _parent = previous.$1;
    _ancestors = previous.$2;
    if (_ancestors == null) {
      unawaited(_load());
    } else {
      setState(() {
        _views = List.unmodifiable(_ancestors!);
        _busy = false;
        _error = null;
        _highlighted = -1;
      });
    }
  }

  bool _canBrowse(ViewPB view) =>
      _ancestors != null ||
      view.isSpace ||
      view.canContainWorkspaceItems ||
      view.childViews.isNotEmpty;

  void _highlight(int index) {
    final generation = _readGeneration;
    setState(() => _highlighted = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canApply(generation)) return;
      final row = _rowKeys[index]?.currentContext;
      if (row != null) unawaited(Scrollable.ensureVisible(row));
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_current) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.escape) &&
        _history.isNotEmpty) {
      _back();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    final count = _busy
        ? 0
        : _error != null
            ? 1
            : _views.length;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end) {
      if (count > 0) {
        final backwards = key == LogicalKeyboardKey.arrowUp ||
            (key == LogicalKeyboardKey.tab &&
                HardwareKeyboard.instance.isShiftPressed);
        _highlight(
          key == LogicalKeyboardKey.home
              ? 0
              : key == LogicalKeyboardKey.end
                  ? count - 1
                  : _highlighted < 0
                      ? (backwards ? count - 1 : 0)
                      : (_highlighted + (backwards ? -1 : 1)) % count,
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_error != null && !_busy) {
        unawaited(_load());
      } else if (!_busy && _highlighted >= 0 && _highlighted < _views.length) {
        final view = _views[_highlighted];
        if (key == LogicalKeyboardKey.arrowRight) {
          if (_canBrowse(view)) _browse(view);
        } else {
          unawaited(_choose(view));
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Column(
          key: const ValueKey('breadcrumb-children-menu'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_history.isNotEmpty)
                  IconButton(
                    key: const ValueKey('breadcrumb-children-back'),
                    tooltip:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    style: WorkspaceChrome.controlStyle(context),
                    icon: const DSWorkspaceGlyph.named('caret-left', size: 16),
                    onPressed: _back,
                  ),
                Expanded(
                  child: AppMenuSectionLabel(
                    label: _ancestors == null
                        ? _parent.nameOrDefault
                        : LocaleKeys.workspaceChrome_ancestors.tr(),
                  ),
                ),
              ],
            ),
            if (_busy)
              AppMenuRow(
                key: const ValueKey('breadcrumb-children-loading'),
                label: LocaleKeys.editor_loading.tr(),
                enabled: false,
                iconWidget: const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              )
            else if (_error != null) ...[
              AppMenuRow(
                key: const ValueKey('breadcrumb-children-error'),
                label: _error!,
                enabled: false,
              ),
              KeyedSubtree(
                key: _rowKeys.putIfAbsent(0, GlobalKey.new),
                child: AppMenuRow(
                  key: const ValueKey('breadcrumb-children-retry'),
                  label: LocaleKeys.button_tryAgain.tr(),
                  icon: Icons.refresh_rounded,
                  tracksHover: true,
                  highlighted: _highlighted == 0,
                  onTap: () {
                    if (!_busy) unawaited(_load());
                  },
                ),
              ),
            ] else if (_views.isEmpty)
              AppMenuRow(
                key: const ValueKey('breadcrumb-children-empty'),
                label: LocaleKeys.workspaceFolderExplorer_emptyFolder.tr(),
                enabled: false,
              )
            else
              for (var i = 0; i < _views.length; i++) _buildRow(_views[i], i),
          ],
        ),
      );

  Widget _buildRow(ViewPB view, int index) {
    final generation = _readGeneration;
    return KeyedSubtree(
      key: _rowKeys.putIfAbsent(index, GlobalKey.new),
      child: Row(
        children: [
          Expanded(
            child: AppMenuRow(
              key: ValueKey('breadcrumb-child-${view.id}'),
              label: view.nameOrDefault,
              iconWidget: WorkspaceBreadcrumbIcon(view: view),
              highlighted: _highlighted == index,
              onHover: (_) {
                if (_canApply(generation)) {
                  setState(() => _highlighted = index);
                }
              },
              onTap: () {
                if (_canApply(generation)) unawaited(_choose(view));
              },
            ),
          ),
          if (_canBrowse(view))
            IconButton(
              key: ValueKey('breadcrumb-browse-${view.id}'),
              tooltip: view.nameOrDefault,
              style: WorkspaceChrome.controlStyle(context).copyWith(
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                fixedSize: const WidgetStatePropertyAll(Size(28, 32)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const DSWorkspaceGlyph.named('caret-right', size: 14),
              onPressed: () {
                if (_canApply(generation)) _browse(view);
              },
            ),
        ],
      ),
    );
  }
}
