import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Carry out one dashboard action.
///
/// Actions are stored as data, so this is the single place that knows how to
/// perform one — a button, a card and a keyboard shortcut all end up here, and
/// a new action kind is added once.
Future<void> runDashboardAction(
  BuildContext context, {
  required DashboardController controller,
  required DashboardAction action,
}) async {
  switch (action.kind) {
    case DashboardActionKind.none:
      return;

    case DashboardActionKind.openUrl:
      if (action.target.isNotEmpty) {
        await afLaunchUrlString(action.target, context: context);
      }

    case DashboardActionKind.openPage:
      if (action.target.isEmpty) {
        return;
      }
      final result = await ViewBackendService.getView(action.target);
      if (!context.mounted) {
        return;
      }
      result.fold(
        (view) => context.read<TabsBloc>().openPlugin(view),
        (_) => showToastNotification(
          message: LocaleKeys.dashboard_action_targetMissing.tr(),
          type: ToastificationType.warning,
        ),
      );

    case DashboardActionKind.createPage:
      if (action.target.isEmpty) {
        return;
      }
      final name =
          action.value is String && (action.value! as String).isNotEmpty
              ? action.value! as String
              : LocaleKeys.menuAppHeader_defaultNewPageName.tr();
      final created = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        parentViewId: action.target,
        name: name,
      );
      if (!context.mounted) {
        return;
      }
      created.fold(
        (view) => context.read<TabsBloc>().openPlugin(view),
        (error) => showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        ),
      );

    case DashboardActionKind.createRow:
      if (action.target.isEmpty) {
        return;
      }
      final created = await RowBackendService.createRow(viewId: action.target);
      if (!context.mounted) {
        return;
      }
      created.fold(
        (_) => showToastNotification(
          message: LocaleKeys.dashboard_action_rowAdded.tr(),
        ),
        (error) => showToastNotification(
          message: error.msg,
          type: ToastificationType.error,
        ),
      );

    case DashboardActionKind.setVariable:
      if (action.variableKey.isNotEmpty) {
        controller.setValue(action.variableKey, action.value);
      }

    case DashboardActionKind.toggleVariable:
      if (action.variableKey.isNotEmpty) {
        controller.toggleValue(action.variableKey);
      }

    case DashboardActionKind.toggleSection:
      final section = controller.document.sectionById(action.target);
      if (section != null) {
        controller.edit(
          (document) => document
              .withSection(section.copyWith(collapsed: !section.collapsed)),
        );
      }

    case DashboardActionKind.copyText:
      await Clipboard.setData(ClipboardData(text: action.target));
      if (context.mounted) {
        showToastNotification(
          message: LocaleKeys.dashboard_action_copied.tr(),
        );
      }

    case DashboardActionKind.setReminder:
      await showReminderComposer(
        context,
        initialText: action.label,
        kind: ReminderKind.block,
      );

    case DashboardActionKind.refresh:
      controller.refresh();

    case DashboardActionKind.openModal:
      controller.openModal(
        action.target.isEmpty ? null : action.target,
      );
  }
}

/// The words shown for [kind] wherever an action is chosen.
String dashboardActionLabel(DashboardActionKind kind) => switch (kind) {
      DashboardActionKind.none => LocaleKeys.dashboard_action_none.tr(),
      DashboardActionKind.openPage => LocaleKeys.dashboard_action_openPage.tr(),
      DashboardActionKind.openUrl => LocaleKeys.dashboard_action_openUrl.tr(),
      DashboardActionKind.createPage =>
        LocaleKeys.dashboard_action_createPage.tr(),
      DashboardActionKind.createRow =>
        LocaleKeys.dashboard_action_createRow.tr(),
      DashboardActionKind.setVariable =>
        LocaleKeys.dashboard_action_setVariable.tr(),
      DashboardActionKind.toggleVariable =>
        LocaleKeys.dashboard_action_toggleVariable.tr(),
      DashboardActionKind.toggleSection =>
        LocaleKeys.dashboard_action_toggleSection.tr(),
      DashboardActionKind.copyText => LocaleKeys.dashboard_action_copyText.tr(),
      DashboardActionKind.setReminder =>
        LocaleKeys.dashboard_action_setReminder.tr(),
      DashboardActionKind.refresh => LocaleKeys.dashboard_action_refresh.tr(),
      DashboardActionKind.openModal =>
        LocaleKeys.dashboard_action_openModal.tr(),
    };

IconData dashboardActionIcon(DashboardActionKind kind) => switch (kind) {
      DashboardActionKind.none => Icons.block_rounded,
      DashboardActionKind.openPage => Icons.description_rounded,
      DashboardActionKind.openUrl => Icons.link_rounded,
      DashboardActionKind.createPage => Icons.note_add_rounded,
      DashboardActionKind.createRow => Icons.playlist_add_rounded,
      DashboardActionKind.setVariable => Icons.tune_rounded,
      DashboardActionKind.toggleVariable => Icons.toggle_on_rounded,
      DashboardActionKind.toggleSection => Icons.unfold_less_rounded,
      DashboardActionKind.copyText => Icons.content_copy_rounded,
      DashboardActionKind.setReminder => Icons.notifications_rounded,
      DashboardActionKind.refresh => Icons.refresh_rounded,
      DashboardActionKind.openModal => Icons.open_in_full_rounded,
    };
