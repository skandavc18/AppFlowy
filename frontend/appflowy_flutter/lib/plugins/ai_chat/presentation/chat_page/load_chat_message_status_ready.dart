import 'dart:async';

import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/ai_chat/application/ai_chat_prelude.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_text_selection.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_message_selector_banner.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_animation_list_widget.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_footer.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/chat_message_widget.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_page/text_message_widget.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_welcome_page.dart';
import 'package:appflowy/plugins/ai_chat/presentation/scroll_to_bottom.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart' hide ChatMessage;
import 'package:universal_platform/universal_platform.dart';

class LoadChatMessageStatusReady extends StatelessWidget {
  const LoadChatMessageStatusReady({
    super.key,
    required this.view,
    required this.userProfile,
    required this.chatController,
  });

  final ViewPB view;
  final UserProfilePB userProfile;
  final ChatController chatController;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: chatController.operationsStream,
      builder: (context, _) {
        // A conversation that has not started yet reads better with the
        // composer in the middle of the page; it settles to the bottom as soon
        // as there is something to read above it.
        final isNew =
            UniversalPlatform.isDesktop && isNewChat(chatController);

        return Column(
          children: [
            _buildHeader(context),
            if (isNew) ...[
              Expanded(child: _buildGreeting(context)),
              _buildFooter(context),
              Expanded(child: _buildSuggestions(context)),
            ] else ...[
              _buildBody(context),
              _buildFooter(context),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGreeting(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: _wrapConstraints(
        Padding(
          padding: const EdgeInsets.only(bottom: 26.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FlowySvg(
                FlowySvgs.app_logo_xl,
                size: Size.square(36),
                blendMode: null,
              ),
              const VSpace(18),
              Text(
                LocaleKeys.chat_questionDetail.tr(args: [userProfile.name]),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: _wrapConstraints(
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            for (final question in ChatWelcomePage.desktopItems)
              WelcomeSampleQuestion(
                question: question,
                onSelected: (question) => _ask(context, question),
              ),
          ],
        ),
      ),
    );
  }

  void _ask(BuildContext context, String question) {
    final prompt = context.read<AIPromptInputBloc>().state;
    context.read<ChatBloc>().add(
          ChatEvent.sendMessage(
            message: question,
            format:
                prompt.showPredefinedFormats ? prompt.predefinedFormat : null,
          ),
        );
  }

  Widget _buildHeader(BuildContext context) {
    return ChatMessageSelectorBanner(
      view: view,
      allMessages: chatController.messages,
    );
  }

  Widget _buildBody(BuildContext context) {
    final bool enableAnimation = true;
    return Expanded(
      child: Align(
        alignment: Alignment.topCenter,
        child: _wrapConstraints(
          CallbackShortcuts(
            bindings: {
              // The prompt input holds the keyboard focus, so the selection's
              // own copy shortcut never fires. One binding here serves the
              // whole conversation.
              const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                  () => unawaited(ChatTextSelection.instance.copy()),
              const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () =>
                  unawaited(ChatTextSelection.instance.copy()),
            },
            child: SelectionArea(
              onSelectionChanged: (content) =>
                  ChatTextSelection.instance.report(content?.plainText),
              child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
              ),
              child: Chat(
                chatController: chatController,
                user: User(id: userProfile.id.toString()),
                darkTheme: ChatTheme.fromThemeData(Theme.of(context)),
                theme: ChatTheme.fromThemeData(Theme.of(context)),
                builders: Builders(
                  // we have a custom input builder, so we don't need the default one
                  inputBuilder: (_) => const SizedBox.shrink(),
                  textMessageBuilder: (
                    context,
                    message,
                  ) =>
                      TextMessageWidget(
                    message: message,
                    userProfile: userProfile,
                    view: view,
                    enableAnimation: enableAnimation,
                  ),
                  chatMessageBuilder: (
                    context,
                    message,
                    animation,
                    child,
                  ) =>
                      ChatMessage(
                    message: message,
                    padding: const EdgeInsets.symmetric(vertical: 18.0),
                    child: child,
                  ),
                  scrollToBottomBuilder: (
                    context,
                    animation,
                    onPressed,
                  ) =>
                      CustomScrollToBottom(
                    animation: animation,
                    onPressed: onPressed,
                  ),
                  chatAnimatedListBuilder: (
                    context,
                    scrollController,
                    itemBuilder,
                  ) =>
                      ChatAnimationListWidget(
                    userProfile: userProfile,
                    scrollController: scrollController,
                    itemBuilder: itemBuilder,
                    enableReversedList: !enableAnimation,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return _wrapConstraints(
      ChatFooter(view: view),
    );
  }

  Widget _wrapConstraints(Widget child) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 784),
      margin: UniversalPlatform.isDesktop
          ? const EdgeInsets.symmetric(horizontal: 60.0)
          : null,
      child: child,
    );
  }
}
