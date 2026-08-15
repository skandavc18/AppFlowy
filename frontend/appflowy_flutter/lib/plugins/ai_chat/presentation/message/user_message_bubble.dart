import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_member_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../chat_avatar.dart';
import '../layout_define.dart';

class ChatUserMessageBubble extends StatefulWidget {
  const ChatUserMessageBubble({
    super.key,
    required this.message,
    required this.child,
    this.files = const [],
  });

  final Message message;
  final Widget child;
  final List<ChatFile> files;

  @override
  State<ChatUserMessageBubble> createState() => _ChatUserMessageBubbleState();
}

class _ChatUserMessageBubbleState extends State<ChatUserMessageBubble> {
  bool _hovered = false;

  Message get message => widget.message;
  List<ChatFile> get files => widget.files;

  @override
  Widget build(BuildContext context) {
    context
        .read<ChatMemberBloc>()
        .add(ChatMemberEvent.getMemberInfo(message.author.id));

    return MouseRegion(
      opaque: false,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: AIChatUILayout.messageMargin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (files.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(right: 32),
                child: _MessageFileList(files: files),
              ),
              const VSpace(6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Spacer(),
                SelectionContainer.disabled(
                  child: _CopyPromptButton(
                    visible: _hovered,
                    message: message,
                  ),
                ),
                _buildBubble(context),
                const HSpace(DesktopAIChatSizes.avatarAndChatBubbleSpacing),
                _buildAvatar(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return BlocBuilder<ChatMemberBloc, ChatMemberState>(
      builder: (context, state) {
        final member = state.members[message.author.id];
        return SelectionContainer.disabled(
          child: ChatUserAvatar(
            iconUrl: member?.info.avatarUrl ?? "",
            name: member?.info.name ?? "",
          ),
        );
      },
    );
  }

  Widget _buildBubble(BuildContext context) {
    return Flexible(
      flex: 5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16.0)),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Copies the question on its own, without the answer under it.
class _CopyPromptButton extends StatelessWidget {
  const _CopyPromptButton({required this.visible, required this.message});

  final bool visible;
  final Message message;

  @override
  Widget build(BuildContext context) {
    final text = message is TextMessage ? (message as TextMessage).text : '';
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 140),
      child: IgnorePointer(
        ignoring: !visible,
        child: FlowyTooltip(
          message: LocaleKeys.settings_menu_clickToCopy.tr(),
          child: FlowyIconButton(
            width: 26,
            hoverColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            icon: FlowySvg(
              FlowySvgs.copy_s,
              size: const Size.square(16),
              color: Theme.of(context).hintColor,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                showToastNotification(
                  message: LocaleKeys.message_copy_success.tr(),
                );
              }
            },
          ),
        ),
      ),
    );
  }
}

class _MessageFileList extends StatelessWidget {
  const _MessageFileList({required this.files});

  final List<ChatFile> files;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = files
        .map(
          (file) => _MessageFile(
            file: file,
          ),
        )
        .toList();

    return Wrap(
      direction: Axis.vertical,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: children,
    );
  }
}

class _MessageFile extends StatelessWidget {
  const _MessageFile({required this.file});

  final ChatFile file;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowySvg(
              FlowySvgs.page_m,
              size: const Size.square(16),
              color: Theme.of(context).hintColor,
            ),
            const HSpace(6),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: FlowyText(
                  file.fileName,
                  fontSize: 12,
                  maxLines: 6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
