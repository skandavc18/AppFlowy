import 'package:intl/intl.dart';

import 'workflow_services.dart';

/// What a trigger hands its workflow, kind by kind. Every payload is plain
/// JSON so it survives a delay step being written to disk.

Map<String, Object?> clockPayload(DateTime at) => {
      'time': DateFormat('HH:mm').format(at),
      'date': DateFormat('yyyy-MM-dd').format(at),
      'weekday': DateFormat('EEEE', 'en_US').format(at),
    };

Map<String, Object?> manualTriggerPayload(DateTime at) => {
      'startedAt': at.toIso8601String(),
    };

Map<String, Object?> scheduleTriggerPayload(DateTime at) => {
      ...clockPayload(at),
      'scheduledAt': at.toIso8601String(),
    };

Map<String, Object?> feedTriggerPayload(
  WorkflowFeed feed,
  WorkflowFeedItem item,
) =>
    {
      'title': item.title,
      'link': item.link,
      'summary': item.summary,
      'image': item.image,
      'publishedAt': item.publishedAt?.toIso8601String() ?? '',
      'feedTitle': feed.title,
    };

Map<String, Object?> rowTriggerPayload(
  WorkflowRowData row, {
  required bool isNew,
}) =>
    {
      'rowId': row.id,
      'fields': row.cells,
      'modifiedAt': row.modifiedAt > 0
          ? stampToDate(row.modifiedAt).toIso8601String()
          : '',
      'isNew': isNew,
    };

Map<String, Object?> pageTriggerPayload(
  WorkflowPageInfo page,
  String parentId,
) =>
    {
      'id': page.id,
      'name': page.name,
      'createdAt': page.createdAt?.toIso8601String() ?? '',
      'parentId': parentId,
      'layout': page.layout,
    };

/// The backend stamps rows in seconds; some older paths used milliseconds.
DateTime stampToDate(int stamp) => stamp > 100000000000
    ? DateTime.fromMillisecondsSinceEpoch(stamp)
    : DateTime.fromMillisecondsSinceEpoch(stamp * 1000);
