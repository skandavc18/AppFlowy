import 'package:flutter/material.dart';

import 'package:appflowy/plugins/database/board/presentation/board_style.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';

import '../card_cell_builder.dart';
import '../card_cell_skeleton/checkbox_card_cell.dart';
import '../card_cell_skeleton/checklist_card_cell.dart';
import '../card_cell_skeleton/date_card_cell.dart';
import '../card_cell_skeleton/media_card_cell.dart';
import '../card_cell_skeleton/number_card_cell.dart';
import '../card_cell_skeleton/relation_card_cell.dart';
import '../card_cell_skeleton/select_option_card_cell.dart';
import '../card_cell_skeleton/summary_card_cell.dart';
import '../card_cell_skeleton/text_card_cell.dart';
import '../card_cell_skeleton/time_card_cell.dart';
import '../card_cell_skeleton/timestamp_card_cell.dart';
import '../card_cell_skeleton/translate_card_cell.dart';
import '../card_cell_skeleton/url_card_cell.dart';

CardCellStyleMap desktopBoardCardCellStyleMap(BuildContext context) {
  final palette = boardPaletteOf(context);
  const EdgeInsetsGeometry padding = EdgeInsets.symmetric(vertical: 3);
  final TextStyle textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: 11.5,
        height: 1.35,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w500,
        color: palette.textSecondary,
        overflow: TextOverflow.ellipsis,
      );

  return {
    FieldType.Checkbox: CheckboxCardCellStyle(
      padding: padding,
      iconSize: const Size.square(16),
      showFieldName: true,
      textStyle: textStyle,
    ),
    FieldType.Checklist: ChecklistCardCellStyle(
      padding: padding,
      textStyle: textStyle.copyWith(color: palette.textMuted),
    ),
    FieldType.CreatedTime: TimestampCardCellStyle(
      padding: padding,
      textStyle: textStyle,
    ),
    FieldType.DateTime: DateCardCellStyle(
      padding: padding,
      textStyle: textStyle,
    ),
    FieldType.LastEditedTime: TimestampCardCellStyle(
      padding: padding,
      textStyle: textStyle,
    ),
    FieldType.MultiSelect: SelectOptionCardCellStyle(
      padding: padding,
      tagFontSize: 11,
      wrap: true,
      tagPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      tagRadius: BorderRadius.circular(999),
    ),
    FieldType.Number: NumberCardCellStyle(
      padding: padding,
      textStyle: textStyle,
    ),
    FieldType.RichText: TextCardCellStyle(
      padding: padding,
      textStyle: textStyle,
      maxLines: 2,
      titleTextStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
            fontSize: 14,
            height: 1.35,
            letterSpacing: -0.15,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
            overflow: TextOverflow.ellipsis,
          ),
    ),
    FieldType.SingleSelect: SelectOptionCardCellStyle(
      padding: padding,
      tagFontSize: 11,
      wrap: true,
      tagPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      tagRadius: BorderRadius.circular(999),
    ),
    FieldType.URL: URLCardCellStyle(
      padding: padding,
      textStyle: textStyle.copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
    ),
    FieldType.Relation: RelationCardCellStyle(
      padding: padding,
      wrap: true,
      textStyle: textStyle,
    ),
    FieldType.Summary: SummaryCardCellStyle(
      padding: padding,
      textStyle: textStyle,
    ),
    FieldType.Time: TimeCardCellStyle(
      padding: padding,
      textStyle: textStyle,
    ),
    FieldType.Translate: TranslateCardCellStyle(
      padding: padding,
      textStyle: textStyle,
    ),
    FieldType.Media: MediaCardCellStyle(
      padding: padding,
      textStyle: textStyle,
    ),
  };
}
