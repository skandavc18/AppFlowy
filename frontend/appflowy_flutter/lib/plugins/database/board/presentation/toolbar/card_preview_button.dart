import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/card_preview.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

/// Chooses what the cards on this board show above their titles.
class CardPreviewButton extends StatelessWidget {
  const CardPreviewButton({super.key, required this.view, this.registry});

  final ViewPB view;
  final CardPreviewRegistry? registry;

  @override
  Widget build(BuildContext context) {
    final registry = this.registry ?? CardPreviewRegistry.instance;
    return ValueListenableBuilder<CardPreviewMode>(
      valueListenable: registry.notifierFor(view),
      builder: (context, mode, _) => Builder(
        builder: (buttonContext) => Semantics(
          label: LocaleKeys.cardPreview_tooltip.tr(),
          value: _labelOf(mode),
          button: true,
          child: FlowyTooltip(
            message: LocaleKeys.cardPreview_tooltip.tr(),
            child: FlowyIconButton(
              width: 24,
              icon: Icon(
                _iconOf(mode),
                size: 16,
                color: mode == CardPreviewMode.pageAndTitle ||
                        mode == CardPreviewMode.pageContent
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).iconTheme.color,
              ),
              hoverColor: AFThemeExtension.of(context).greyHover,
              radius: Corners.s4Border,
              onPressed: () => unawaited(_choose(buttonContext, registry)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choose(
    BuildContext context,
    CardPreviewRegistry registry,
  ) async {
    final mode = registry.modeFor(view);
    await showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuHeader(LocaleKeys.cardPreview_title.tr()),
        for (final choice in CardPreviewMode.values)
          AppMenuItem(
            label: _labelOf(choice),
            iconWidget: Semantics(
              button: true,
              selected: choice == mode,
              inMutuallyExclusiveGroup: true,
              child: Icon(_iconOf(choice)),
            ),
            selected: choice == mode,
            onSelected: () => unawaited(registry.set(view, choice)),
          ),
      ],
    );
  }

  static IconData _iconOf(CardPreviewMode mode) => switch (mode) {
        CardPreviewMode.pageAndTitle => Icons.sticky_note_2_rounded,
        CardPreviewMode.cover => Icons.image_rounded,
        CardPreviewMode.pageContent => Icons.article_rounded,
        CardPreviewMode.none => Icons.notes_rounded,
        CardPreviewMode.portrait => Icons.crop_portrait_rounded,
        CardPreviewMode.titleAndProperties => Icons.view_list_rounded,
      };

  static String _labelOf(CardPreviewMode mode) => switch (mode) {
        CardPreviewMode.pageAndTitle => LocaleKeys.gallery_facePage.tr(),
        CardPreviewMode.cover => LocaleKeys.gallery_faceCover.tr(),
        CardPreviewMode.pageContent => LocaleKeys.gallery_faceContent.tr(),
        CardPreviewMode.none => LocaleKeys.gallery_faceNone.tr(),
        CardPreviewMode.portrait => LocaleKeys.gallery_facePortrait.tr(),
        CardPreviewMode.titleAndProperties =>
          LocaleKeys.cardPreview_titleAndProperties.tr(),
      };
}
