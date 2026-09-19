import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Where a row's discussion lives.
///
/// A comment is not a property of the row and not a paragraph of its page, so
/// it is kept in one block of the row's own document. That block never renders
/// itself — this section is what draws it — which keeps the thread out of the
/// page body while still letting it sync and travel with the row.
abstract final class RowCommentKeys {
  static const String type = 'row_comments';
  static const String comments = 'comments';
}

/// One thing somebody said about a row.
@immutable
class RowComment {
  const RowComment({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.authorId = '',
    this.avatar = '',
  });

  final String id;
  final String author;
  final String authorId;
  final String avatar;
  final String text;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'author': author,
        if (authorId.isNotEmpty) 'author_id': authorId,
        if (avatar.isNotEmpty) 'avatar': avatar,
        'text': text,
        'created_at': createdAt.toIso8601String(),
      };

  static RowComment? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final text = value['text'];
    if (text is! String || text.trim().isEmpty) {
      return null;
    }
    return RowComment(
      id: value['id'] is String ? value['id'] as String : '',
      author: value['author'] is String ? value['author'] as String : '',
      authorId:
          value['author_id'] is String ? value['author_id'] as String : '',
      avatar: value['avatar'] is String ? value['avatar'] as String : '',
      text: text,
      createdAt: DateTime.tryParse('${value['created_at']}') ?? DateTime(1970),
    );
  }
}

/// The comments a document is carrying.
List<RowComment> rowCommentsOf(Document document) {
  final node = rowCommentNodeOf(document);
  final stored = node?.attributes[RowCommentKeys.comments];
  if (stored is! List) {
    return const [];
  }
  return [
    for (final entry in stored)
      if (RowComment.fromJson(entry) case final comment?) comment,
  ];
}

/// The block a row's comments are kept in, if it has been made yet.
Node? rowCommentNodeOf(Document document) {
  for (final node in document.root.children) {
    if (node.type == RowCommentKeys.type) {
      return node;
    }
  }
  return null;
}

/// Keeps the editor from drawing the block the comments are stored in.
class RowCommentsBlockComponentBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) =>
      _RowCommentsBlockComponent(
        key: blockComponentContext.node.key,
        node: blockComponentContext.node,
      );
}

class _RowCommentsBlockComponent extends BlockComponentStatelessWidget {
  const _RowCommentsBlockComponent({
    super.key,
    required super.node,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// How long ago something was said, in words.
String rowCommentAgo(DateTime when, {DateTime? now}) {
  final gap = (now ?? DateTime.now()).difference(when);
  if (gap.inMinutes < 1) {
    return LocaleKeys.grid_row_commentJustNow.tr();
  }
  if (gap.inHours < 1) {
    return LocaleKeys.grid_row_commentMinutes.tr(args: ['${gap.inMinutes}']);
  }
  if (gap.inDays < 1) {
    return LocaleKeys.grid_row_commentHours.tr(args: ['${gap.inHours}']);
  }
  if (gap.inDays < 30) {
    return LocaleKeys.grid_row_commentDays.tr(args: ['${gap.inDays}']);
  }
  return DateFormat.yMMMd().format(when);
}

/// The thread under a row's properties.
class RowCommentSection extends StatefulWidget {
  const RowCommentSection({
    super.key,
    required this.editorState,
    this.userProfile,
    this.padding = const EdgeInsets.fromLTRB(40, 0, 60, 0),
  });

  final EditorState editorState;
  final UserProfilePB? userProfile;
  final EdgeInsets padding;

  @override
  State<RowCommentSection> createState() => _RowCommentSectionState();
}

class _RowCommentSectionState extends State<RowCommentSection> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final FocusScopeNode _scope = FocusScopeNode();

  bool _writing = false;

  // Some table views pass the workspace bloc through their popup overlay but
  // omit its optional profile argument. Use the same session identity for the
  // avatar, new comments and ownership checks, without another backend read.
  UserProfilePB? get _userProfile =>
      widget.userProfile ??
      context.read<UserWorkspaceBloc?>()?.state.userProfile;

  @override
  void dispose() {
    _scope.dispose();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_writing) {
      return;
    }
    _controller.clear();
    // Cancel may itself hold keyboard focus, rather than the text field.
    _scope.unfocus();
  }

  Future<void> _write(List<RowComment> comments) async {
    final document = widget.editorState.document;
    final payload = [for (final comment in comments) comment.toJson()];
    final existing = rowCommentNodeOf(document);
    final transaction = widget.editorState.transaction;
    if (existing == null) {
      // The thread goes after the page, never before it: a document whose
      // first node draws nothing has nowhere to put the caret.
      transaction.insertNode(
        [document.root.children.length],
        Node(
          type: RowCommentKeys.type,
          attributes: {RowCommentKeys.comments: payload},
        ),
      );
    } else {
      transaction.updateNode(existing, {RowCommentKeys.comments: payload});
    }
    // The thread is not where the caret was, so the selection is left alone.
    transaction.afterSelection = widget.editorState.selection;
    await widget.editorState.apply(transaction);
  }

  Future<void> _post() async {
    final draft = _controller.text;
    final text = draft.trim();
    if (_writing || text.isEmpty) {
      return;
    }
    final profile = _userProfile;
    final comment = RowComment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      author: profile?.name ?? '',
      authorId: profile?.id.toString() ?? '',
      avatar: profile?.iconUrl ?? '',
      text: text,
      createdAt: DateTime.now(),
    );
    setState(() => _writing = true);
    try {
      await _write([...rowCommentsOf(widget.editorState.document), comment]);
      if (mounted && _controller.text == draft) {
        _controller.clear();
      }
    } finally {
      if (mounted) {
        setState(() => _writing = false);
      }
    }
  }

  Future<void> _remove(RowComment comment) async {
    if (_writing || !_isMine(comment)) {
      return;
    }
    setState(() => _writing = true);
    try {
      final left = rowCommentsOf(widget.editorState.document)
          .where((other) => other.id != comment.id)
          .toList();
      await _write(left);
    } finally {
      if (mounted) {
        setState(() => _writing = false);
      }
    }
  }

  bool _isMine(RowComment comment) =>
      comment.authorId.isNotEmpty &&
      comment.authorId == _userProfile?.id.toString();

  @override
  Widget build(BuildContext context) {
    final profile = widget.userProfile ??
        context.select<UserWorkspaceBloc?, UserProfilePB?>(
          (bloc) => bloc?.state.userProfile,
        );
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final muted = palette?.textMuted ?? theme.hintColor;
    final comments = rowCommentsOf(widget.editorState.document);
    final idCounts = <String, int>{};
    for (final comment in comments) {
      idCounts.update(comment.id, (count) => count + 1, ifAbsent: () => 1);
    }

    // The composer is a text field living inside the editor, which sees
    // Backspace and Enter first. Dropping the selection while it has focus is
    // what lets those keys reach the field.
    return FocusScope(
      node: _scope,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          widget.editorState.selection = null;
        }
      },
      child: Padding(
        key: const ValueKey('row-comments-section'),
        padding: widget.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Semantics(
                header: true,
                child: Text(
                  LocaleKeys.grid_row_comments.tr(),
                  key: const ValueKey('row-comments-heading'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.4,
                    color: muted,
                  ),
                ),
              ),
            ),
            if (comments.isNotEmpty)
              Column(
                key: const ValueKey('row-comments-thread'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, comment) in comments.indexed)
                    _CommentRow(
                      // Legacy/malformed entries still render independently;
                      // valid IDs retain hover/focus state across deletions.
                      key: comment.id.isNotEmpty && idCounts[comment.id] == 1
                          ? ValueKey(comment.id)
                          : ValueKey((comment.id, index)),
                      comment: comment,
                      busy: _writing,
                      onDelete:
                          _isMine(comment) ? () => _remove(comment) : null,
                    ),
                ],
              ),
            if (comments.isNotEmpty) const SizedBox(height: 6),
            _Composer(
              controller: _controller,
              focusNode: _focus,
              busy: _writing,
              userProfile: profile,
              onSubmit: _post,
              onCancel: _cancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
    super.key,
    required this.comment,
    required this.busy,
    this.onDelete,
  });

  final RowComment comment;
  final bool busy;
  final VoidCallback? onDelete;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final muted = palette?.textMuted ?? theme.hintColor;
    final comment = widget.comment;
    // Keep the action in the focus order without invisible mouse targets.
    // Assistive navigation has no hover, so its actions stay discoverable.
    final showActions =
        _hovered || _focused || MediaQuery.accessibleNavigationOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Padding(
          key: ValueKey('row-comment-${comment.id}'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(name: comment.author, url: comment.avatar),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                comment.author.isEmpty
                                    ? LocaleKeys.grid_row_commentSomebody.tr()
                                    : comment.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: palette?.textPrimary ??
                                      theme.colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                rowCommentAgo(comment.createdAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11.5,
                                  height: 1.5,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.onDelete != null)
                          IgnorePointer(
                            ignoring: !showActions,
                            child: AnimatedOpacity(
                              key:
                                  ValueKey('row-comment-actions-${comment.id}'),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                              opacity: showActions ? 1 : 0,
                              child: IconButton(
                                key: ValueKey(
                                  'row-comment-delete-${comment.id}',
                                ),
                                tooltip: LocaleKeys.button_delete.tr(),
                                onPressed: widget.busy ? null : widget.onDelete,
                                style: _commentButtonStyle(context).copyWith(
                                  minimumSize: const WidgetStatePropertyAll(
                                    Size.square(28),
                                  ),
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.all(5),
                                  ),
                                  iconSize: const WidgetStatePropertyAll(16),
                                ),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      comment.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        height: 1.5,
                        color:
                            palette?.textPrimary ?? theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSubmit,
    required this.onCancel,
    this.userProfile,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final UserProfilePB? userProfile;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final muted = palette?.textMuted ?? theme.hintColor;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppFlowyMotion.gentle;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        // Include the buttons: Tab must not close an empty focused composer.
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final active = _focused || value.text.isNotEmpty || widget.busy;
            final empty = value.text.trim().isEmpty;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: widget.focusNode.requestFocus,
              child: TextFieldTapRegion(
                child: Row(
                  key: const ValueKey('row-comment-composer'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _Avatar(
                        key: const ValueKey('row-comment-composer-avatar'),
                        name: widget.userProfile?.name ?? '',
                        url: widget.userProfile?.iconUrl ?? '',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        key: const ValueKey('row-comment-input-surface'),
                        constraints: const BoxConstraints(minHeight: 40),
                        alignment: Alignment.topLeft,
                        // Writing stays on the page itself: no filled card,
                        // focus outline or padding shift when the caret lands.
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DefaultTextEditingShortcuts(
                              child: TextField(
                                key: const ValueKey('row-comment-input'),
                                controller: widget.controller,
                                focusNode: widget.focusNode,
                                readOnly: widget.busy,
                                // Keep multiline input enabled before the
                                // focus rebuild, or the first paste loses its
                                // newlines to the single-line formatter.
                                maxLines: 6,
                                minLines: 1,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 13.5,
                                  height: 1.4,
                                  color: palette?.textPrimary ??
                                      theme.colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  isCollapsed: true,
                                  filled: false,
                                  hoverColor: Colors.transparent,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  hintText:
                                      LocaleKeys.grid_row_commentHint.tr(),
                                  hintMaxLines: 1,
                                  hintStyle:
                                      theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ),
                            _CommentActionReveal(
                              duration: duration,
                              child: active
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          TextButton(
                                            key: const ValueKey(
                                              'row-comment-cancel',
                                            ),
                                            onPressed: widget.busy
                                                ? null
                                                : widget.onCancel,
                                            style: _commentButtonStyle(context),
                                            child: Text(
                                              LocaleKeys.button_cancel.tr(),
                                            ),
                                          ),
                                          IconButton(
                                            key: const ValueKey(
                                              'row-comment-post',
                                            ),
                                            tooltip: LocaleKeys
                                                .grid_row_commentPost
                                                .tr(),
                                            onPressed: empty || widget.busy
                                                ? null
                                                : widget.onSubmit,
                                            style: _commentButtonStyle(
                                              context,
                                              primary: true,
                                            ).copyWith(
                                              minimumSize:
                                                  const WidgetStatePropertyAll(
                                                Size.square(28),
                                              ),
                                              maximumSize:
                                                  const WidgetStatePropertyAll(
                                                Size.square(28),
                                              ),
                                              padding:
                                                  const WidgetStatePropertyAll(
                                                EdgeInsets.all(5),
                                              ),
                                              shape:
                                                  const WidgetStatePropertyAll(
                                                CircleBorder(),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.arrow_upward_rounded,
                                              size: 17,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// AnimatedSize cannot safely finish a zero-duration layout animation on the
/// current Flutter version. Reduced motion shows the actions directly instead.
class _CommentActionReveal extends StatelessWidget {
  const _CommentActionReveal({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => duration == Duration.zero
      ? child
      : AnimatedSize(
          duration: duration,
          curve: AppFlowyMotion.standardCurve,
          alignment: Alignment.topCenter,
          child: child,
        );
}

ButtonStyle _commentButtonStyle(BuildContext context, {bool primary = false}) {
  final theme = Theme.of(context);
  final palette = theme.extension<PremiumThemeExtension>();
  final muted = palette?.textMuted ?? theme.hintColor;
  final accent = palette?.accent ?? theme.colorScheme.primary;
  final focusRing = palette?.focusRing ?? theme.focusColor;
  final foreground = WidgetStateProperty.resolveWith<Color>(
    (states) => states.contains(WidgetState.disabled)
        ? muted.withValues(alpha: 0.6)
        : primary
            ? theme.colorScheme.onPrimary
            : muted,
  );
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    splashFactory: NoSplash.splashFactory,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120),
    textStyle: WidgetStatePropertyAll(
      theme.textTheme.labelMedium?.copyWith(fontSize: 12.5, height: 1.2),
    ),
    foregroundColor: foreground,
    iconColor: foreground,
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return accent.withValues(alpha: primary ? 0.08 : 0);
      }
      if (primary) {
        return states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)
            ? Color.alphaBlend(
                theme.colorScheme.onSurface.withValues(alpha: 0.08),
                accent,
              )
            : accent;
      }
      if (states.contains(WidgetState.pressed)) {
        return palette?.pressed ?? theme.highlightColor;
      }
      if (states.contains(WidgetState.hovered)) {
        return palette?.hover ?? theme.hoverColor;
      }
      return accent.withValues(alpha: 0);
    }),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.focused)
            ? focusRing
            : focusRing.withValues(alpha: 0),
      ),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({super.key, required this.name, required this.url});

  final String name;
  final String url;

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      iconUrl: url,
      name: name,
      size: AFAvatarSize.s,
    );
  }
}
