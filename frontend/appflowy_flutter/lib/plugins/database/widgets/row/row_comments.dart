import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

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

  bool _composing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focus.hasFocus != _composing) {
      setState(() => _composing = _focus.hasFocus);
    }
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
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _post() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    final profile = widget.userProfile;
    final comment = RowComment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      author: profile?.name ?? '',
      authorId: profile?.id.toString() ?? '',
      avatar: profile?.iconUrl ?? '',
      text: text,
      createdAt: DateTime.now(),
    );
    _controller.clear();
    await _write([...rowCommentsOf(widget.editorState.document), comment]);
  }

  Future<void> _remove(RowComment comment) async {
    final left = rowCommentsOf(widget.editorState.document)
        .where((other) => other.id != comment.id)
        .toList();
    await _write(left);
  }

  bool _isMine(RowComment comment) =>
      comment.authorId.isNotEmpty &&
      comment.authorId == widget.userProfile?.id.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final muted = palette?.textMuted ?? theme.hintColor;
    final comments = rowCommentsOf(widget.editorState.document);

    // The composer is a text field living inside the editor, which sees
    // Backspace and Enter first. Dropping the selection while it has focus is
    // what lets those keys reach the field.
    return FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          widget.editorState.selection = null;
        }
      },
      child: Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.mode_comment_outlined, size: 13, color: muted),
                  const SizedBox(width: 7),
                  Text(
                    LocaleKeys.grid_row_comments.tr().toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: muted,
                    ),
                  ),
                  if (comments.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _CountPill(count: comments.length),
                  ],
                ],
              ),
            ),
            if (comments.isNotEmpty)
              ViewerCard(
                color: palette?.floatingSurface ?? theme.cardColor,
                borderRadius: BorderRadius.circular(_cardRadius),
                reactsToPointer: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < comments.length; i++)
                        _CommentRow(
                          comment: comments[i],
                          first: i == 0,
                          onDelete: _isMine(comments[i])
                              ? () => _remove(comments[i])
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            if (comments.isNotEmpty) const SizedBox(height: 10),
            _Composer(
              controller: _controller,
              focusNode: _focus,
              expanded: _composing || _controller.text.isNotEmpty,
              userProfile: widget.userProfile,
              onSubmit: _post,
              onCancel: () {
                _controller.clear();
                _focus.unfocus();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The radius the comment cards share with the rest of the row page.
const double _cardRadius = 14;

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: (palette?.mutedSurface ?? theme.dividerColor)
            .withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: palette?.textMuted ?? theme.hintColor,
        ),
      ),
    );
  }
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
    required this.comment,
    required this.first,
    this.onDelete,
  });

  final RowComment comment;
  final bool first;
  final VoidCallback? onDelete;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final muted = palette?.textMuted ?? theme.hintColor;
    final hover = palette?.hover ?? theme.hoverColor;
    final comment = widget.comment;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.first)
            Divider(
              height: 1,
              thickness: 1,
              color: (palette?.border ?? theme.dividerColor)
                  .withValues(alpha: 0.28),
            ),
          AnimatedContainer(
            duration: AppFlowyMotion.gentle,
            curve: AppFlowyMotion.standardCurve,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.fromLTRB(8, 9, 8, 10),
            decoration: BoxDecoration(
              color: hover.withValues(alpha: _hovered ? 0.55 : 0),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(name: comment.author, url: comment.avatar),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The name and the age keep to themselves so the free
                      // space falls between them and the delete button.
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    comment.author.isEmpty
                                        ? LocaleKeys.grid_row_commentSomebody
                                            .tr()
                                        : comment.author,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  rowCommentAgo(comment.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.3,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.onDelete != null)
                            AnimatedOpacity(
                              duration: AppFlowyMotion.gentle,
                              opacity: _hovered ? 1 : 0,
                              child: IgnorePointer(
                                ignoring: !_hovered,
                                child: _CommentIconButton(
                                  icon: Icons.delete_outline_rounded,
                                  onTap: widget.onDelete!,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comment.text,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.55,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentIconButton extends StatefulWidget {
  const _CommentIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_CommentIconButton> createState() => _CommentIconButtonState();
}

class _CommentIconButtonState extends State<_CommentIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final hover = palette?.hover ?? theme.hoverColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppFlowyMotion.gentle,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: hover.withValues(alpha: _hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            widget.icon,
            size: 15,
            color: palette?.textMuted ?? theme.hintColor,
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
    required this.expanded,
    required this.onSubmit,
    required this.onCancel,
    this.userProfile,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool expanded;
  final UserProfilePB? userProfile;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final muted = palette?.textMuted ?? theme.hintColor;
    final active = widget.expanded;
    final empty = widget.controller.text.trim().isEmpty;
    final accent = theme.colorScheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.focusNode.requestFocus,
        child: ViewerCard(
          color: palette?.floatingSurface ?? theme.cardColor,
          borderRadius: BorderRadius.circular(_cardRadius),
          elevation:
              active ? ViewerCardElevation.raised : ViewerCardElevation.resting,
          reactsToPointer: false,
          child: AnimatedContainer(
            duration: AppFlowyMotion.gentle,
            curve: AppFlowyMotion.standardCurve,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_cardRadius),
              border: Border.all(
                color: accent.withValues(
                  alpha: active ? 0.5 : (_hovered ? 0.18 : 0),
                ),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(
                  name: widget.userProfile?.name ?? '',
                  url: widget.userProfile?.iconUrl ?? '',
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          maxLines: active ? 6 : 1,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.55,
                            color: theme.colorScheme.onSurface,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            isCollapsed: true,
                            filled: false,
                            hoverColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: LocaleKeys.grid_row_commentHint.tr(),
                            hintStyle: TextStyle(
                              fontSize: 13.5,
                              height: 1.55,
                              color: muted,
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: AppFlowyMotion.gentle,
                          curve: AppFlowyMotion.standardCurve,
                          alignment: Alignment.topCenter,
                          child: active
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      _ComposerButton(
                                        label: LocaleKeys.button_cancel.tr(),
                                        onTap: widget.onCancel,
                                      ),
                                      const SizedBox(width: 6),
                                      _ComposerButton(
                                        label: LocaleKeys.grid_row_commentPost
                                            .tr(),
                                        primary: true,
                                        onTap: empty ? null : widget.onSubmit,
                                      ),
                                    ],
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
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
}

class _ComposerButton extends StatefulWidget {
  const _ComposerButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  State<_ComposerButton> createState() => _ComposerButtonState();
}

class _ComposerButtonState extends State<_ComposerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.extension<PremiumThemeExtension>();
    final muted = palette?.textMuted ?? theme.hintColor;
    final hover = palette?.hover ?? theme.hoverColor;
    final enabled = widget.onTap != null;
    final accent = theme.colorScheme.primary;

    final background = widget.primary
        ? accent.withValues(
            alpha: enabled ? (_hovered ? 0.92 : 1) : 0.28,
          )
        : hover.withValues(alpha: _hovered ? 1 : 0);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppFlowyMotion.gentle,
          curve: AppFlowyMotion.standardCurve,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: widget.primary
                  ? theme.colorScheme.onPrimary
                      .withValues(alpha: enabled ? 1 : 0.75)
                  : muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.url});

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
