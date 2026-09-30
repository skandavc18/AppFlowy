import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/blank/home/home_agenda.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_card.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Home's editorial voice: a system serif for the clock and page titles.
/// No font is bundled for it; each platform's own serif is used.
TextStyle homeSerif(TextStyle base) => base.copyWith(
      fontFamily: 'Georgia',
      fontFamilyFallback: const [
        'Cambria',
        'Times New Roman',
        'Noto Serif',
        'DejaVu Serif',
        'Liberation Serif',
        'serif',
      ],
      fontVariations: const [],
    );

/// Today's time and date.
class HomeClock extends StatelessWidget {
  const HomeClock({
    super.key,
    required this.now,
    required this.formatTime,
    this.alignment = CrossAxisAlignment.end,
  });

  final DateTime now;
  final String Function(DateTime time) formatTime;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return Semantics(
      container: true,
      label: '${formatTime(now)}, ${DateFormat.yMMMMEEEEd().format(now)}',
      child: ExcludeSemantics(
        child: Column(
          key: const ValueKey('home-clock'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: alignment,
          children: [
            Text(
              formatTime(now),
              style: homeSerif(
                WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.pageTitle,
                  color: palette.primaryText,
                ),
              ).copyWith(
                fontSize: 34,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.5,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat.MMMMEEEEd().format(now),
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small caps label that names a block on Home.
class HomeEyebrow extends StatelessWidget {
  const HomeEyebrow({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.trailing,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final tint = color ?? palette.secondaryText;
    return Row(
      children: [
        if (icon != null) ...[
          WorkspaceGlyph(icon!, size: 14, color: tint),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.caption,
              color: tint,
            ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8),
          ),
        ),
        if (trailing != null && trailing!.isNotEmpty)
          Flexible(
            child: Text(
              '  ·  $trailing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.caption,
              ),
            ),
          ),
      ],
    );
  }
}

/// A quiet, rounded action in a block's own colour.
class HomeTintedButton extends StatelessWidget {
  const HomeTintedButton({
    super.key,
    required this.label,
    required this.icon,
    required this.tint,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: tint,
          backgroundColor: tint.withValues(alpha: 0.1),
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const StadiumBorder(),
          textStyle: WorkspaceTypography.style(
            context,
            WorkspaceTextRole.metadata,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        icon: WorkspaceGlyph(icon, size: 15, color: tint),
        label: Text(label),
      );
}

/// The page worked on most recently, with a way straight back into it.
class HomeResumeCard extends StatelessWidget {
  const HomeResumeCard({
    super.key,
    required this.entry,
    required this.caption,
    required this.details,
    required this.loadPreview,
    required this.onOpen,
    required this.onOpenInNewTab,
    this.userProfile,
  });

  final ViewGalleryEntry? entry;
  final String caption;
  final String details;
  final Future<FolderGalleryPreview> Function(ViewGalleryEntry entry)
      loadPreview;
  final VoidCallback onOpen;
  final VoidCallback? onOpenInNewTab;
  final UserProfilePB? userProfile;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final entry = this.entry;
    if (entry == null) {
      return Column(
        key: const ValueKey('home-resume'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeEyebrow(
            label: LocaleKeys.landing_resume.tr(),
            icon: Icons.restore_rounded,
          ),
          const SizedBox(height: 8),
          Text(
            LocaleKeys.landing_resumeEmpty.tr(),
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.body,
              color: palette.mutedText,
            ),
          ),
        ],
      );
    }
    final view = entry.view;
    final preview = loadPreview(entry);
    // A banner, not a stamp: page previews stay legible at the rail's width.
    const thumbnailHeight = 112.0;
    return Column(
      key: const ValueKey('home-resume'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        HomeEyebrow(
          label: LocaleKeys.landing_resume.tr(),
          icon: Icons.restore_rounded,
          color: palette.accent,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: thumbnailHeight,
          child: ExcludeSemantics(
            child: FolderGalleryPreviewThumbnail(
              item: WorkspaceExplorerItem.fromView(view),
              view: view,
              preview: preview,
              userProfile: userProfile,
              height: thumbnailHeight,
              borderRadius: BorderRadius.circular(12),
              compact: true,
              lightweight: true,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 6),
              child: ViewGalleryIcon(view: view),
            ),
            Expanded(
              child: Text(
                view.nameOrDefault,
                key: const ValueKey('home-resume-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: homeSerif(
                  WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.section,
                  ),
                ).copyWith(fontSize: 19, height: 1.25),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FutureBuilder<FolderGalleryPreview>(
          future: preview,
          builder: (context, snapshot) {
            // The banner above already shows the page's opening lines.
            final data = snapshot.data;
            final stats = [
              caption,
              details,
              if (data != null && data.wordCount > 0)
                LocaleKeys.landing_wordCount.tr(
                  args: [NumberFormat.decimalPattern().format(data.wordCount)],
                ),
              if (data != null && data.readingMinutes > 0)
                LocaleKeys.landing_readTime
                    .tr(args: ['${data.readingMinutes}']),
            ].where((part) => part.isNotEmpty).join('  ·  ');
            return stats.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    stats,
                    key: const ValueKey('home-resume-stats'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.metadata,
                    ),
                  );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: WorkspaceTokens.space2,
          runSpacing: WorkspaceTokens.space2,
          children: [
            FilledButton.icon(
              key: const ValueKey('home-resume-continue'),
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.north_east_rounded, size: 16),
              label: Text(LocaleKeys.landing_continueWorking.tr()),
            ),
            if (onOpenInNewTab != null)
              TextButton(
                onPressed: onOpenInNewTab,
                style: TextButton.styleFrom(
                  foregroundColor: palette.secondaryText,
                  minimumSize: const Size(0, 34),
                  shape: const StadiumBorder(),
                ),
                child: Text(LocaleKeys.landing_openInNewTab.tr()),
              ),
          ],
        ),
      ],
    );
  }
}

/// One event or reminder: a coloured mark (round for events, square for
/// reminders), its title and when, and the one action that fits it.
class HomeAgendaRow extends StatelessWidget {
  const HomeAgendaRow({
    super.key,
    required this.item,
    required this.subtitle,
    required this.onOpen,
    this.onComplete,
    this.overdue = false,
  });

  final HomeAgendaItem item;
  final String subtitle;
  final VoidCallback onOpen;

  /// Marks a reminder done; events only open.
  final VoidCallback? onComplete;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final reminder = item.reminder;
    final dot = item.color ??
        (reminder == null
            ? palette.accent
            : reminder.priority.tint(palette.accent) ?? palette.success);
    final title = item.title.isEmpty ? '—' : item.title;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('home-agenda-${item.id}'),
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dot,
                  shape:
                      reminder == null ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius:
                      reminder == null ? null : BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.body,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.metadata,
                        color: overdue ? palette.destructive : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (reminder != null && onComplete != null)
                IconButton(
                  key: ValueKey('home-agenda-done-${item.id}'),
                  tooltip: LocaleKeys.landing_markDone.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: onComplete,
                  icon: WorkspaceGlyph(
                    Icons.check_circle_outline_rounded,
                    color: palette.success,
                  ),
                )
              else
                IconButton(
                  tooltip: LocaleKeys.landing_open.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpen,
                  icon: WorkspaceGlyph(
                    Icons.north_east_rounded,
                    size: 16,
                    color: palette.secondaryText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pages one click away: favorites (pinned first) or, failing that, recents.
class HomeQuickJump extends StatelessWidget {
  const HomeQuickJump({
    super.key,
    required this.entries,
    required this.onOpen,
    this.alignment = WrapAlignment.start,
  });

  final List<ViewGalleryEntry> entries;
  final ValueChanged<ViewGalleryEntry> onOpen;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return Wrap(
      key: const ValueKey('home-quick-jump'),
      alignment: alignment,
      spacing: WorkspaceTokens.space2,
      runSpacing: WorkspaceTokens.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 4),
          child: Text(
            LocaleKeys.landing_quickJump.tr(),
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.metadata,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        for (final entry in entries)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: TextButton(
              key: ValueKey('home-quick-jump-${entry.id}'),
              onPressed: () => onOpen(entry),
              style: TextButton.styleFrom(
                foregroundColor: palette.primaryText,
                backgroundColor: palette.surface,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 12, 4),
                shape: StadiumBorder(side: BorderSide(color: palette.border)),
                textStyle: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                  color: palette.primaryText,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ViewGalleryIcon(view: entry.view, size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      entry.view.nameOrDefault,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.pinned) ...[
                    const SizedBox(width: 4),
                    WorkspaceGlyph(
                      Icons.push_pin_rounded,
                      size: 12,
                      color: palette.mutedText,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
