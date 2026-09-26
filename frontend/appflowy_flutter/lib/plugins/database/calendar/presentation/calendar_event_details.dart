import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_agenda_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Read an event with no external URL or row page. This does not call the new
/// reminder composer, which would create a second reminder rather than edit it.
Future<void> showCalendarEventDetails(
  BuildContext context, {
  required CalendarEvent event,
}) {
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration:
        WorkspaceTokens.motion(context, WorkspaceTokens.transitionDuration),
    pageBuilder: (dialogContext, _, __) => themes.wrap(
      Builder(
        builder: (context) => SafeArea(
          child: Dialog(
            backgroundColor: WorkspacePalette.of(context).surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkspaceTokens.dialogRadius),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(WorkspaceTokens.space6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title.isEmpty
                          ? LocaleKeys.calendar_defaultNewCalendarTitle.tr()
                          : event.title,
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.cardTitle,
                      ),
                    ),
                    const SizedBox(height: WorkspaceTokens.space2),
                    Text(
                      event.spansDays
                          ? '${DateFormat.yMMMd().format(event.startDay)} – ${DateFormat.yMMMd().format(event.endDay)}'
                          : DateFormat.yMMMMEEEEd().format(event.startDay),
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.metadata,
                      ),
                    ),
                    Text(
                      calendarAgendaTimeLabel(context, event),
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.metadata,
                      ),
                    ),
                    if (event.location.isNotEmpty) ...[
                      const SizedBox(height: WorkspaceTokens.space3),
                      Text(
                        event.location,
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.body,
                        ),
                      ),
                    ],
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: WorkspaceTokens.space3),
                      Text(
                        event.description,
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.body,
                        ),
                      ),
                    ],
                    const SizedBox(height: WorkspaceTokens.space4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          MaterialLocalizations.of(context).closeButtonLabel,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
