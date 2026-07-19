import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    hide QuoteBlockKeys, quoteNode;
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:easy_localization/easy_localization.dart';

export 'align_option_action.dart';
export 'color_option_action.dart';
export 'depth_option_action.dart';
export 'divider_option_action.dart';
export 'turn_into_option_action.dart';

enum EditorOptionActionType {
  turnInto,
  color,
  align,
  depth;

  Set<String> get supportTypes {
    switch (this) {
      case EditorOptionActionType.turnInto:
        return {
          ParagraphBlockKeys.type,
          HeadingBlockKeys.type,
          QuoteBlockKeys.type,
          CalloutBlockKeys.type,
          BulletedListBlockKeys.type,
          NumberedListBlockKeys.type,
          TodoListBlockKeys.type,
          ToggleListBlockKeys.type,
          SubPageBlockKeys.type,
        };
      case EditorOptionActionType.color:
        return {
          ParagraphBlockKeys.type,
          HeadingBlockKeys.type,
          BulletedListBlockKeys.type,
          NumberedListBlockKeys.type,
          QuoteBlockKeys.type,
          TodoListBlockKeys.type,
          CalloutBlockKeys.type,
          OutlineBlockKeys.type,
          ToggleListBlockKeys.type,
        };
      case EditorOptionActionType.align:
        return {
          ImageBlockKeys.type,
          SimpleTableBlockKeys.type,
        };
      case EditorOptionActionType.depth:
        return {
          OutlineBlockKeys.type,
        };
    }
  }
}

enum OptionAction {
  addAbove,
  addBelow,
  delete,
  cut,
  copy,
  paste,
  duplicate,
  turnInto,
  moveUp,
  moveDown,
  splitIntoColumns,
  stackColumns,
  copyLinkToBlock,

  /// callout background color
  color,
  divider,
  align,

  // Outline block
  depth,

  // Simple table
  setToPageWidth,
  distributeColumnsEvenly;

  FlowySvgData get svg {
    switch (this) {
      case OptionAction.addAbove:
        return FlowySvgs.table_insert_above_s;
      case OptionAction.addBelow:
        return FlowySvgs.table_insert_below_s;
      case OptionAction.delete:
        return FlowySvgs.trash_s;
      case OptionAction.cut:
        return FlowySvgs.m_table_quick_action_cut_s;
      case OptionAction.copy:
        return FlowySvgs.copy_s;
      case OptionAction.paste:
        return FlowySvgs.m_table_quick_action_paste_s;
      case OptionAction.duplicate:
        return FlowySvgs.copy_s;
      case OptionAction.turnInto:
        return FlowySvgs.turninto_s;
      case OptionAction.moveUp:
        return FlowySvgs.arrow_up_s;
      case OptionAction.moveDown:
        return FlowySvgs.arrow_down_s;
      case OptionAction.splitIntoColumns:
      case OptionAction.stackColumns:
        return FlowySvgs.slash_menu_icon_two_columns_s;
      case OptionAction.color:
        return const FlowySvgData('editor/color');
      case OptionAction.divider:
        return const FlowySvgData('editor/divider');
      case OptionAction.align:
        return FlowySvgs.m_aa_bulleted_list_s;
      case OptionAction.depth:
        return FlowySvgs.tag_s;
      case OptionAction.copyLinkToBlock:
        return FlowySvgs.share_tab_copy_s;
      case OptionAction.setToPageWidth:
        return FlowySvgs.table_set_to_page_width_s;
      case OptionAction.distributeColumnsEvenly:
        return FlowySvgs.table_distribute_columns_evenly_s;
    }
  }

  String get description {
    switch (this) {
      case OptionAction.addAbove:
        return LocaleKeys.button_insertAbove.tr();
      case OptionAction.addBelow:
        return LocaleKeys.button_insertBelow.tr();
      case OptionAction.delete:
        return LocaleKeys.document_plugins_optionAction_delete.tr();
      case OptionAction.cut:
        return LocaleKeys.document_plugins_contextMenu_cut.tr();
      case OptionAction.copy:
        return LocaleKeys.document_plugins_contextMenu_copy.tr();
      case OptionAction.paste:
        return LocaleKeys.document_plugins_contextMenu_paste.tr();
      case OptionAction.duplicate:
        return LocaleKeys.document_plugins_optionAction_duplicate.tr();
      case OptionAction.turnInto:
        return LocaleKeys.document_plugins_optionAction_turnInto.tr();
      case OptionAction.moveUp:
        return LocaleKeys.document_plugins_optionAction_moveUp.tr();
      case OptionAction.moveDown:
        return LocaleKeys.document_plugins_optionAction_moveDown.tr();
      case OptionAction.splitIntoColumns:
        return '${LocaleKeys.document_slashMenu_name_twoColumns.tr()} (split)';
      case OptionAction.stackColumns:
        return 'Stack columns vertically';
      case OptionAction.color:
        return LocaleKeys.document_plugins_optionAction_color.tr();
      case OptionAction.align:
        return LocaleKeys.document_plugins_optionAction_align.tr();
      case OptionAction.depth:
        return LocaleKeys.document_plugins_optionAction_depth.tr();
      case OptionAction.copyLinkToBlock:
        return LocaleKeys.document_plugins_optionAction_copyLinkToBlock.tr();
      case OptionAction.divider:
        throw UnsupportedError('Divider does not have description');
      case OptionAction.setToPageWidth:
        return LocaleKeys
            .document_plugins_simpleTable_moreActions_setToPageWidth
            .tr();
      case OptionAction.distributeColumnsEvenly:
        return LocaleKeys
            .document_plugins_simpleTable_moreActions_distributeColumnsWidth
            .tr();
    }
  }
}
