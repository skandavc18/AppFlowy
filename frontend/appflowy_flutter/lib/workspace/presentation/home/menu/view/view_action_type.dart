import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum ViewMoreActionType {
  delete,
  favorite,
  unFavorite,
  duplicate,
  copyTo,
  cut,
  pasteInto,
  copyLink, // not supported yet.
  rename,
  moveTo,
  openInNewTab,
  changeIcon,
  collapseAllPages, // including sub pages
  divider,
  lastModified,
  created,
  lockPage,
  turnIntoDashboard,
  turnIntoCanvas,
  leaveSharedPage;

  static const disableInLockedView = [
    delete,
    rename,
    moveTo,
    cut,
    pasteInto,
    changeIcon,
  ];
}

extension ViewMoreActionTypeExtension on ViewMoreActionType {
  String get name {
    switch (this) {
      case ViewMoreActionType.delete:
        return LocaleKeys.disclosureAction_delete.tr();
      case ViewMoreActionType.favorite:
        return LocaleKeys.disclosureAction_favorite.tr();
      case ViewMoreActionType.unFavorite:
        return LocaleKeys.disclosureAction_unfavorite.tr();
      case ViewMoreActionType.duplicate:
        return LocaleKeys.disclosureAction_duplicate.tr();
      case ViewMoreActionType.copyTo:
        return LocaleKeys.workspaceFolderExplorer_copyTo.tr();
      case ViewMoreActionType.cut:
        return LocaleKeys.workspaceFolderExplorer_cut.tr();
      case ViewMoreActionType.pasteInto:
        return LocaleKeys.workspaceFolderExplorer_pasteInto.tr();
      case ViewMoreActionType.copyLink:
        return LocaleKeys.disclosureAction_copyLink.tr();
      case ViewMoreActionType.rename:
        return LocaleKeys.disclosureAction_rename.tr();
      case ViewMoreActionType.moveTo:
        return LocaleKeys.disclosureAction_moveTo.tr();
      case ViewMoreActionType.openInNewTab:
        return LocaleKeys.disclosureAction_openNewTab.tr();
      case ViewMoreActionType.changeIcon:
        return LocaleKeys.disclosureAction_changeIcon.tr();
      case ViewMoreActionType.collapseAllPages:
        return LocaleKeys.disclosureAction_collapseAllPages.tr();
      case ViewMoreActionType.lockPage:
        return LocaleKeys.disclosureAction_lockPage.tr();
      case ViewMoreActionType.turnIntoDashboard:
        return LocaleKeys.dashboard_turnInto.tr();
      case ViewMoreActionType.turnIntoCanvas:
        return LocaleKeys.canvas_turnInto.tr();
      case ViewMoreActionType.leaveSharedPage:
        return 'Leave';
      case ViewMoreActionType.divider:
      case ViewMoreActionType.lastModified:
      case ViewMoreActionType.created:
        return '';
    }
  }

  /// One Material glyph per action, so the sidebar menu shares its icon family
  /// with every other menu in the application.
  IconData get leftIcon {
    switch (this) {
      case ViewMoreActionType.delete:
        return Icons.delete_outline_rounded;
      case ViewMoreActionType.favorite:
        return Icons.star_border_rounded;
      case ViewMoreActionType.unFavorite:
        return Icons.star_rounded;
      case ViewMoreActionType.duplicate:
        return Icons.control_point_duplicate_rounded;
      case ViewMoreActionType.copyTo:
        return Icons.copy_rounded;
      case ViewMoreActionType.cut:
        return Icons.content_cut_rounded;
      case ViewMoreActionType.pasteInto:
        return Icons.content_paste_rounded;
      case ViewMoreActionType.rename:
        return Icons.drive_file_rename_outline_rounded;
      case ViewMoreActionType.moveTo:
        return Icons.drive_file_move_rounded;
      case ViewMoreActionType.openInNewTab:
        return Icons.open_in_new_rounded;
      case ViewMoreActionType.changeIcon:
        return Icons.emoji_emotions_rounded;
      case ViewMoreActionType.collapseAllPages:
        return Icons.unfold_less_rounded;
      case ViewMoreActionType.lockPage:
        return Icons.lock_outline_rounded;
      case ViewMoreActionType.turnIntoDashboard:
        return Icons.dashboard_rounded;
      case ViewMoreActionType.turnIntoCanvas:
        return Icons.dashboard_customize_rounded;
      case ViewMoreActionType.leaveSharedPage:
        return Icons.logout_rounded;
      case ViewMoreActionType.divider:
      case ViewMoreActionType.lastModified:
      case ViewMoreActionType.copyLink:
      case ViewMoreActionType.created:
        throw UnsupportedError('No left icon for $this');
    }
  }

  Widget get rightIcon {
    switch (this) {
      case ViewMoreActionType.changeIcon:
      case ViewMoreActionType.moveTo:
      case ViewMoreActionType.favorite:
      case ViewMoreActionType.unFavorite:
      case ViewMoreActionType.duplicate:
      case ViewMoreActionType.copyTo:
      case ViewMoreActionType.cut:
      case ViewMoreActionType.pasteInto:
      case ViewMoreActionType.copyLink:
      case ViewMoreActionType.rename:
      case ViewMoreActionType.openInNewTab:
      case ViewMoreActionType.collapseAllPages:
      case ViewMoreActionType.divider:
      case ViewMoreActionType.delete:
      case ViewMoreActionType.lastModified:
      case ViewMoreActionType.created:
      case ViewMoreActionType.lockPage:
      case ViewMoreActionType.turnIntoDashboard:
      case ViewMoreActionType.turnIntoCanvas:
      case ViewMoreActionType.leaveSharedPage:
        return const SizedBox.shrink();
    }
  }
}
