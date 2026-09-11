import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/templates/presentation/template_card.dart';
import 'package:appflowy/plugins/templates/presentation/template_preview.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/template_service.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What "apply a template here" means for the thing it was asked of.
enum _Applying {
  /// Lay the arrangement over a page, dashboard or canvas.
  over,

  /// Build the template inside a folder or a collection.
  inside,
}

/// Whether the sidebar should offer this view a template at all.
bool canApplyTemplateTo(ViewPB view) =>
    TemplateRegistry.applicableTo(view).isNotEmpty || view.isWorkspaceFolder;

/// Offers the templates that suit [view], and applies the chosen one.
Future<void> showApplyTemplateDialog(
  BuildContext context,
  ViewPB view,
) async {
  final overlay = TemplateRegistry.applicableTo(view);
  // A page is laid over; a folder is filled. Preferring the overlay is what
  // makes "apply a template to this page" mean what it looks like it means.
  final applying = overlay.isNotEmpty
      ? _Applying.over
      : view.isWorkspaceFolder
          ? _Applying.inside
          : null;
  if (applying == null) {
    showSnackBarMessage(context, LocaleKeys.templates_nothingApplies.tr());
    return;
  }

  final choices = applying == _Applying.over ? overlay : TemplateRegistry.all();
  final tabs = context.read<TabsBloc>();
  final chosen = await showDialog<WorkspaceTemplate>(
    context: context,
    builder: (_) => _ApplyTemplateDialog(
      view: view,
      choices: choices,
      applying: applying,
    ),
  );
  if (chosen == null || !context.mounted) {
    return;
  }

  if (applying == _Applying.inside) {
    final outcome = await TemplateService.create(
      parentViewId: view.id,
      template: chosen,
    );
    if (!context.mounted) {
      return;
    }
    if (outcome == null) {
      showSnackBarMessage(context, LocaleKeys.templates_failed.tr());
      return;
    }
    showSnackBarMessage(
      context,
      LocaleKeys.templates_created.tr(args: [chosen.label()]),
    );
    tabs.openPlugin(outcome.primary);
    return;
  }

  final applied = await TemplateService.applyTo(view: view, template: chosen);
  if (!context.mounted) {
    return;
  }
  showSnackBarMessage(
    context,
    applied ? _saidWhatHappened(chosen) : LocaleKeys.templates_applyFailed.tr(),
  );
}

String _saidWhatHappened(WorkspaceTemplate template) {
  final name = template.label();
  return switch (template.kind) {
    TemplateKind.dashboard =>
      LocaleKeys.templates_appliedDashboard.tr(args: [name]),
    TemplateKind.canvas => LocaleKeys.templates_appliedCanvas.tr(args: [name]),
    _ => LocaleKeys.templates_appliedPage.tr(args: [name]),
  };
}

class _ApplyTemplateDialog extends StatelessWidget {
  const _ApplyTemplateDialog({
    required this.view,
    required this.choices,
    required this.applying,
  });

  final ViewPB view;
  final List<WorkspaceTemplate> choices;
  final _Applying applying;

  /// A dashboard is replaced and a page is only added to. Saying which before
  /// the press is the difference between a template and a surprise.
  String get _warning {
    if (applying == _Applying.inside) {
      return '';
    }
    return choices.first.kind == TemplateKind.page
        ? LocaleKeys.templates_addsToTheEnd.tr()
        : LocaleKeys.templates_replacesArrangement.tr();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final body = applying == _Applying.inside
        ? LocaleKeys.templates_body.tr()
        : '${LocaleKeys.templates_applyBody.tr()} $_warning';

    return Dialog(
      backgroundColor: palette.surface,
      insetPadding: const EdgeInsets.all(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LocaleKeys.templates_applyTitle.tr(args: [view.name]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.title(palette, size: 17),
              ),
              const SizedBox(height: 5),
              Text(
                body,
                style: DashboardType.caption(palette).copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisExtent: 112,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: choices.length,
                  itemBuilder: (_, index) => TemplateCard(
                    template: choices[index],
                    palette: palette,
                    compact: true,
                    onChosen: () async {
                      final missing = missingExtensionsFor(choices[index]);
                      if (missing.isNotEmpty) {
                        showSnackBarMessage(
                          context,
                          missing.length == 1
                              ? LocaleKeys.templates_needsExtension
                                  .tr(args: [missing.single])
                              : LocaleKeys.templates_needsExtensions
                                  .tr(args: [missing.join(', ')]),
                        );
                        return;
                      }
                      final wanted = await showTemplatePreview(
                        context,
                        choices[index],
                        confirmLabel: applying == _Applying.inside
                            ? LocaleKeys.templates_use.tr()
                            : LocaleKeys.templates_apply.tr(),
                      );
                      if (wanted && context.mounted) {
                        Navigator.of(context).pop(choices[index]);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
