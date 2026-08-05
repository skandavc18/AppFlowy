import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/email/email_account_dialog.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/collection/views/email/email_host.dart';
import 'package:appflowy/plugins/collection/views/email/email_import.dart';
import 'package:appflowy/plugins/collection/views/email/email_message_list.dart';
import 'package:appflowy/plugins/collection/views/email/email_reader.dart';
import 'package:appflowy/plugins/collection/views/email/email_toolbar.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/email/email_controller.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The mailbox as three panes: where the mail comes from, what is in it, and
/// the message itself.
class EmailThreePaneView extends StatefulWidget {
  const EmailThreePaneView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  State<EmailThreePaneView> createState() => _EmailThreePaneViewState();
}

class _EmailThreePaneViewState extends State<EmailThreePaneView> {
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
            return _EmptyMailbox(
              theme: theme,
              collection: widget.collection,
              controller: controller,
            );
          }

          final open = controller.activeMessage;
          return LayoutBuilder(
            builder: (context, constraints) {
              // A rail and a reading pane are only worth their room when there
              // is room; below that the mailbox gives everything to the list.
              final showRail = constraints.maxWidth >= 1020;
              final showReader = controller.settings.showReadingPane &&
                  constraints.maxWidth >= 760;

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
                      trailing: [
                        EmailAction(
                          icon: Icons.file_download_outlined,
                          tooltip: LocaleKeys.collections_email_import.tr(),
                          theme: theme,
                          onPressed: () => importMailWithFeedback(
                            context,
                            collection: widget.collection.collectionView,
                          ),
                        ),
                        EmailAction(
                          icon: controller.settings.showReadingPane
                              ? Icons.vertical_split_rounded
                              : Icons.view_headline_rounded,
                          tooltip:
                              LocaleKeys.collections_email_readingPane.tr(),
                          theme: theme,
                          active: controller.settings.showReadingPane,
                          onPressed: () => controller.setShowReadingPane(
                            show: !controller.settings.showReadingPane,
                          ),
                        ),
                      ],
                    ),
                    const EmailGap(size: EmailMetrics.space2),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showRail) ...[
                            SizedBox(
                              width: EmailMetrics.railWidth,
                              child: EmailSenderRail(
                                controller: controller,
                                theme: theme,
                              ),
                            ),
                            const EmailGap(),
                          ],
                          SizedBox(
                            width: showReader ? EmailMetrics.listWidth : null,
                            child: showReader ? _list(controller, theme) : null,
                          ),
                          if (!showReader)
                            Expanded(child: _list(controller, theme)),
                          if (showReader) ...[
                            const EmailGap(),
                            Expanded(
                              child: EmailPanel(
                                child: open == null
                                    ? EmailEmptyState(
                                        icon: Icons.drafts_rounded,
                                        title: LocaleKeys
                                            .collections_email_nothingOpen
                                            .tr(),
                                        theme: theme,
                                        message: LocaleKeys
                                            .collections_email_nothingOpenHint
                                            .tr(),
                                      )
                                    : EmailReader(
                                        key: ValueKey(open.id),
                                        message: open,
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

  Widget _list(EmailController controller, EmailTheme theme) => EmailPanel(
        child: EmailMessageList(
          controller: controller,
          theme: theme,
          onOpen: (id) => unawaitedOpen(controller, id),
        ),
      );
}

/// What a mailbox shows before anything has been put in it.
class _EmptyMailbox extends StatelessWidget {
  const _EmptyMailbox({
    required this.theme,
    required this.collection,
    required this.controller,
  });

  final EmailTheme theme;
  final CollectionViewContext collection;
  final EmailController controller;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(EmailMetrics.gutter),
        child: EmailPanel(
          child: EmailEmptyState(
            icon: Icons.mail_rounded,
            title: LocaleKeys.collections_email_empty.tr(),
            theme: theme,
            message: LocaleKeys.collections_email_emptyHint.tr(),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmailAction(
                  icon: Icons.cloud_sync_rounded,
                  tooltip: LocaleKeys.collections_email_connect.tr(),
                  theme: theme,
                  label: LocaleKeys.collections_email_connect.tr(),
                  active: true,
                  size: 32,
                  onPressed: () => syncMailWithFeedback(
                    context,
                    controller: controller,
                  ),
                ),
                const SizedBox(width: EmailMetrics.space2),
                EmailAction(
                  icon: Icons.file_download_outlined,
                  tooltip: LocaleKeys.collections_email_import.tr(),
                  theme: theme,
                  label: LocaleKeys.collections_email_import.tr(),
                  size: 32,
                  onPressed: () => importMailWithFeedback(
                    context,
                    collection: collection.collectionView,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Opening a message is a future nobody waits on: the list has already moved.
void unawaitedOpen(EmailController controller, String id) {
  controller.open(id).ignore();
}
