import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/collection/views/email/email_host.dart';
import 'package:appflowy/plugins/collection/views/email/email_message_list.dart';
import 'package:appflowy/plugins/collection/views/email/email_reader.dart';
import 'package:appflowy/plugins/collection/views/email/email_three_pane_view.dart';
import 'package:appflowy/plugins/collection/views/email/email_toolbar.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/email/email_controller.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The mailbox read as conversations: replies gathered with what they answer,
/// and a whole exchange read downwards like a transcript.
class EmailConversationView extends StatefulWidget {
  const EmailConversationView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  State<EmailConversationView> createState() => _EmailConversationViewState();
}

class _EmailConversationViewState extends State<EmailConversationView> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EmailHost(
        collection: widget.collection,
        builder: (context, controller, theme) {
          if (controller.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(EmailMetrics.gutter),
              child: EmailPanel(
                child: EmailEmptyState(
                  icon: Icons.forum_rounded,
                  title: LocaleKeys.collections_email_empty.tr(),
                  theme: theme,
                  message: LocaleKeys.collections_email_emptyHint.tr(),
                ),
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final showReader = constraints.maxWidth >= 860;
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  EmailMetrics.gutter,
                  EmailMetrics.space2,
                  EmailMetrics.gutter,
                  EmailMetrics.space5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EmailToolbar(
                      controller: controller,
                      theme: theme,
                      searchController: _search,
                      showGrouping: false,
                      trailing: [
                        EmailChip(
                          label: LocaleKeys.collections_email_threadCount
                              .tr(args: ['${controller.threads.length}']),
                          theme: theme,
                          icon: Icons.forum_rounded,
                        ),
                      ],
                    ),
                    const EmailGap(size: EmailMetrics.space2),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width:
                                showReader ? EmailMetrics.listWidth + 40 : null,
                            child: showReader
                                ? _threads(context, controller, theme)
                                : null,
                          ),
                          if (!showReader)
                            Expanded(
                              child: _threads(context, controller, theme),
                            ),
                          if (showReader) ...[
                            const EmailGap(),
                            Expanded(
                              child: EmailPanel(
                                child: EmailConversationReader(
                                  controller: controller,
                                  theme: theme,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

  Widget _threads(
    BuildContext context,
    EmailController controller,
    EmailTheme theme,
  ) =>
      EmailPanel(
        child: EmailMessageList(
          controller: controller,
          theme: theme,
          threaded: true,
          onOpen: (id) => unawaitedOpen(controller, id),
        ),
      );
}
