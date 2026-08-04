import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:flutter/foundation.dart';

/// How far apart two ticks of the timeline stand.
enum TimelineScale {
  day('day', 1),
  week('week', 7),
  month('month', 30),
  quarter('quarter', 91),
  year('year', 365);

  const TimelineScale(this.id, this.days);

  final String id;

  /// Roughly how many days one tick covers. Rough is right: the timeline is
  /// read, not surveyed, and a month that is sometimes 30 days keeps every
  /// column the same width.
  final int days;

  TimelineScale get closer {
    final at = TimelineScale.values.indexOf(this);
    return TimelineScale
        .values[(at - 1).clamp(0, TimelineScale.values.length - 1)];
  }

  TimelineScale get further {
    final at = TimelineScale.values.indexOf(this);
    return TimelineScale
        .values[(at + 1).clamp(0, TimelineScale.values.length - 1)];
  }

  static TimelineScale fromId(String? id) {
    for (final scale in TimelineScale.values) {
      if (scale.id == id) {
        return scale;
      }
    }
    return TimelineScale.month;
  }
}

/// The shape a timeline is read in.
///
/// A schedule answers "how long does this take and does it clash"; a story
/// answers "what happened, in order". They are different questions, so the
/// timeline offers both rather than compromising on one drawing.
enum TimelineFlow {
  /// A spine down the middle with events alternating either side.
  vertical('vertical'),

  /// A track running left to right with events hung above and below it.
  horizontal('horizontal'),

  /// The dated grid: bars across a ruler, dragged to reschedule.
  schedule('schedule');

  const TimelineFlow(this.id);

  final String id;

  static TimelineFlow fromId(String? id) {
    for (final flow in TimelineFlow.values) {
      if (flow.id == id) {
        return flow;
      }
    }
    return TimelineFlow.vertical;
  }
}

/// How a table is laid out in time.
@immutable
class TimelineSpec {
  const TimelineSpec({
    this.startColumn = '',
    this.endColumn = '',
    this.titleColumn = '',
    this.colorColumn = '',
    this.propertyColumns = const [],
    this.scale = TimelineScale.month,
    this.showMilestones = true,
    this.flow = TimelineFlow.vertical,
  });

  /// When a row begins and ends. Empty means the timeline works it out from
  /// the table's own date columns.
  final String startColumn;
  final String endColumn;

  final String titleColumn;

  /// The column whose value decides an event's colour, usually a status.
  final String colorColumn;

  /// The columns worth showing when an event is hovered.
  final List<String> propertyColumns;

  final TimelineScale scale;

  /// Whether a row with a beginning but no end is drawn as a point in time.
  final bool showMilestones;

  final TimelineFlow flow;

  TimelineSpec copyWith({
    String? startColumn,
    String? endColumn,
    String? titleColumn,
    String? colorColumn,
    List<String>? propertyColumns,
    TimelineScale? scale,
    bool? showMilestones,
    TimelineFlow? flow,
  }) =>
      TimelineSpec(
        startColumn: startColumn ?? this.startColumn,
        endColumn: endColumn ?? this.endColumn,
        titleColumn: titleColumn ?? this.titleColumn,
        colorColumn: colorColumn ?? this.colorColumn,
        propertyColumns: propertyColumns ?? this.propertyColumns,
        scale: scale ?? this.scale,
        showMilestones: showMilestones ?? this.showMilestones,
        flow: flow ?? this.flow,
      );

  TableReadSpec get readSpec => TableReadSpec(
        titleColumn: titleColumn,
        propertyColumns: propertyColumns,
        startColumn: startColumn,
        endColumn: endColumn,
      );

  Map<String, dynamic> toJson() => {
        if (startColumn.isNotEmpty) 'start': startColumn,
        if (endColumn.isNotEmpty) 'end': endColumn,
        if (titleColumn.isNotEmpty) 'title': titleColumn,
        if (colorColumn.isNotEmpty) 'color': colorColumn,
        if (propertyColumns.isNotEmpty) 'properties': propertyColumns,
        if (scale != TimelineScale.month) 'scale': scale.id,
        if (!showMilestones) 'milestones': false,
        if (flow != TimelineFlow.vertical) 'flow': flow.id,
      };

  static TimelineSpec fromJson(Map<String, dynamic> values) => TimelineSpec(
        startColumn: values['start'] as String? ?? '',
        endColumn: values['end'] as String? ?? '',
        titleColumn: values['title'] as String? ?? '',
        colorColumn: values['color'] as String? ?? '',
        propertyColumns: _strings(values['properties']),
        scale: TimelineScale.fromId(values['scale'] as String?),
        showMilestones: values['milestones'] != false,
        flow: TimelineFlow.fromId(values['flow'] as String?),
      );

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.whereType<String>())
      : const <String>[];

  @override
  bool operator ==(Object other) =>
      other is TimelineSpec &&
      other.startColumn == startColumn &&
      other.endColumn == endColumn &&
      other.titleColumn == titleColumn &&
      other.colorColumn == colorColumn &&
      listEquals(other.propertyColumns, propertyColumns) &&
      other.scale == scale &&
      other.showMilestones == showMilestones &&
      other.flow == flow;

  @override
  int get hashCode => Object.hash(
        startColumn,
        endColumn,
        titleColumn,
        colorColumn,
        Object.hashAll(propertyColumns),
        scale,
        showMilestones,
        flow,
      );
}

/// How wide a reading of the table is, and where every row sits inside it.
///
/// This is pure arithmetic on days: the widget only has to draw what it is
/// told, and the placement can be tested without a screen.
@immutable
class TimelineWindow {
  const TimelineWindow({
    required this.first,
    required this.last,
    required this.dayWidth,
  });

  final DateTime first;
  final DateTime last;

  /// How many pixels one day occupies.
  final double dayWidth;

  /// How many days the window covers, never fewer than one.
  int get days {
    final span = last.difference(first).inDays + 1;
    return span < 1 ? 1 : span;
  }

  double get width => days * dayWidth;

  /// Where a moment sits, measured from the left edge.
  double xOf(DateTime when) => when.difference(first).inHours / 24 * dayWidth;

  /// The moment at a distance from the left edge.
  DateTime whenAt(double x) =>
      first.add(Duration(minutes: (x / dayWidth * 24 * 60).round()));
}

/// One row, placed in time.
@immutable
class TimelineEvent {
  const TimelineEvent({
    required this.rowId,
    required this.start,
    required this.end,
    required this.lane,
    required this.isMilestone,
  });

  final String rowId;
  final DateTime start;
  final DateTime end;

  /// Which row of the timeline it was put on so it does not sit on top of
  /// anything else.
  final int lane;

  final bool isMilestone;
}

/// The window that holds every dated row, with a margin either side so the
/// first and last events are not against the edge.
TimelineWindow timelineWindowFor(
  Iterable<DateTime> moments, {
  required double dayWidth,
  int margin = 7,
}) {
  DateTime? first;
  DateTime? last;
  for (final moment in moments) {
    if (first == null || moment.isBefore(first)) {
      first = moment;
    }
    if (last == null || moment.isAfter(last)) {
      last = moment;
    }
  }
  final today = DateTime.now();
  final from = (first ?? today).subtract(Duration(days: margin));
  final to = (last ?? today).add(Duration(days: margin));
  return TimelineWindow(
    first: DateTime(from.year, from.month, from.day),
    last: DateTime(to.year, to.month, to.day),
    dayWidth: dayWidth,
  );
}

/// Puts events on lanes so that none of them overlap.
///
/// The first lane that is free at an event's start takes it, which is the
/// arrangement a reader expects: earlier rows stay near the top and the
/// timeline only grows as deep as it has to.
List<TimelineEvent> layOutTimeline(
  List<({String rowId, DateTime start, DateTime? end})> rows, {
  required double dayWidth,
  double minimumEventWidth = 120,
}) {
  final sorted = [...rows]..sort((a, b) => a.start.compareTo(b.start));
  // A short event still needs room for its name, so it claims a little more
  // time than it occupies when deciding what it overlaps.
  final minimumDays = dayWidth <= 0 ? 1.0 : minimumEventWidth / dayWidth;
  final laneEnds = <DateTime>[];
  final events = <TimelineEvent>[];

  for (final row in sorted) {
    final end = row.end ?? row.start;
    final claimed = row.start.add(
      Duration(
        minutes: (minimumDays * 24 * 60).round(),
      ),
    );
    final occupiesUntil = end.isAfter(claimed) ? end : claimed;

    var lane = laneEnds.length;
    for (var i = 0; i < laneEnds.length; i++) {
      if (!laneEnds[i].isAfter(row.start)) {
        lane = i;
        break;
      }
    }
    if (lane == laneEnds.length) {
      laneEnds.add(occupiesUntil);
    } else {
      laneEnds[lane] = occupiesUntil;
    }

    events.add(
      TimelineEvent(
        rowId: row.rowId,
        start: row.start,
        end: end,
        lane: lane,
        isMilestone: row.end == null || !row.end!.isAfter(row.start),
      ),
    );
  }
  return events;
}

/// The dates the ruler should be marked at.
List<DateTime> timelineTicks(TimelineWindow window, TimelineScale scale) {
  final ticks = <DateTime>[];
  var at = _tickStart(window.first, scale);
  // A window can be years wide; a cap keeps a runaway table from drawing a
  // million marks.
  while (!at.isAfter(window.last) && ticks.length < 600) {
    ticks.add(at);
    at = _nextTick(at, scale);
  }
  return ticks;
}

DateTime _tickStart(DateTime from, TimelineScale scale) => switch (scale) {
      TimelineScale.day => DateTime(from.year, from.month, from.day),
      TimelineScale.week =>
        DateTime(from.year, from.month, from.day - (from.weekday - 1)),
      TimelineScale.month => DateTime(from.year, from.month),
      TimelineScale.quarter =>
        DateTime(from.year, ((from.month - 1) ~/ 3) * 3 + 1),
      TimelineScale.year => DateTime(from.year),
    };

DateTime _nextTick(DateTime at, TimelineScale scale) => switch (scale) {
      TimelineScale.day => DateTime(at.year, at.month, at.day + 1),
      TimelineScale.week => DateTime(at.year, at.month, at.day + 7),
      TimelineScale.month => DateTime(at.year, at.month + 1),
      TimelineScale.quarter => DateTime(at.year, at.month + 3),
      TimelineScale.year => DateTime(at.year + 1),
    };

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// What a mark on the ruler says.
String timelineTickLabel(DateTime at, TimelineScale scale) => switch (scale) {
      TimelineScale.day => '${at.day} ${_monthNames[at.month - 1]}',
      TimelineScale.week => '${at.day} ${_monthNames[at.month - 1]}',
      TimelineScale.month => '${_monthNames[at.month - 1]} ${at.year}',
      TimelineScale.quarter => 'Q${(at.month - 1) ~/ 3 + 1} ${at.year}',
      TimelineScale.year => '${at.year}',
    };

/// How wide a day is drawn at each scale.
double timelineDayWidth(TimelineScale scale) => switch (scale) {
      TimelineScale.day => 56,
      TimelineScale.week => 16,
      TimelineScale.month => 5.2,
      TimelineScale.quarter => 1.9,
      TimelineScale.year => 0.62,
    };
