import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/email/email_chrome.dart';
import 'package:appflowy/plugins/collection/views/email/email_host.dart';
import 'package:appflowy/plugins/collection/views/email/email_message_list.dart';
import 'package:appflowy/plugins/collection/views/email/email_reader.dart';
import 'package:appflowy/plugins/collection/views/email/email_three_pane_view.dart';
import 'package:appflowy/plugins/collection/views/email/email_toolbar.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/email/email_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The mailbox at its densest: one line a message, the whole of a busy folder
/// visible at once, and the message opened underneath rather than beside.
class EmailCompactView extends StatefulWidget {
  const EmailCompactView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  State<EmailCompactView> createState() => _EmailCompactViewState();
}

class _EmailCompactViewState extends State<EmailCompactView> {
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
                  icon: Icons.list_alt_rounded,
                  title: LocaleKeys.collections_email_empty.tr(),
                  theme: theme,
                  message: LocaleKeys.collections_email_emptyHint.tr(),
                ),
              ),
            );
          }

          // The compact reading is what the view is for, so it opens that way
          // whatever the mailbox was last left at.
          final open = controller.activeMessage;
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
                      icon: Icons.density_small_rounded,
                      tooltip: LocaleKeys.collections_email_densityCompact.tr(),
                      theme: theme,
                      active:
                          controller.settings.density == EmailDensity.compact,
                      onPressed: () => controller.setDensity(
                        controller.settings.density == EmailDensity.compact
                            ? EmailDensity.comfortable
                            : EmailDensity.compact,
                      ),
                    ),
                  ],
                ),
                const EmailGap(size: EmailMetrics.space2),
                Expanded(
                  flex: open == null ? 1 : 3,
                  child: EmailPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ColumnHeadings(theme: theme),
                        Expanded(
                          child: EmailMessageList(
                            controller: controller,
                            theme: theme,
                            padding: const EdgeInsets.fromLTRB(
                              EmailMetrics.space2,
                              0,
                              EmailMetrics.space2,
                              EmailMetrics.space2,
                            ),
                            onOpen: (id) => unawaitedOpen(controller, id),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (open != null) ...[
                  const EmailGap(),
                  Expanded(
                    flex: 2,
                    child: EmailPanel(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: EmailReader(
                              key: ValueKey(open.id),
                              message: open,
                              controller: controller,
                              theme: theme,
                            ),
                          ),
                          Positioned(
                            top: EmailMetrics.space2,
                            right: EmailMetrics.space2,
                            child: EmailAction(
                              icon: Icons.close_rounded,
                              tooltip: LocaleKeys.collections_email_closeMessage
                                  .tr(),
                              theme: theme,
                              onPressed: () => controller.select(null),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
}

/// The heading strip a dense list needs so its columns can be read.
class _ColumnHeadings extends StatelessWidget {
  const _ColumnHeadings({required this.theme});

  final EmailTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          EmailMetrics.space4,
          EmailMetrics.space3,
          EmailMetrics.space4,
          EmailMetrics.space2,
        ),
        child: Row(
          children: [
            const SizedBox(width: EmailMetrics.unreadDot + EmailMetrics.space1),
            SizedBox(
              width: 148,
              child: Text(
                LocaleKeys.collections_email_columnFrom.tr(),
                style: theme.sectionLabel,
              ),
            ),
            const SizedBox(width: EmailMetrics.space3),
            Expanded(
              child: Text(
                LocaleKeys.collections_email_columnSubject.tr(),
                style: theme.sectionLabel,
              ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                LocaleKeys.collections_email_columnDate.tr(),
                textAlign: TextAlign.right,
                style: theme.sectionLabel,
              ),
            ),
          ],
        ),
      );
}
