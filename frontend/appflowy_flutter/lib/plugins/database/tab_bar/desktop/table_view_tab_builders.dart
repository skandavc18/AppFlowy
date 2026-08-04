import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/table_view_host.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/table_views/feed_stage.dart';
import 'package:appflowy/shared/table_views/form_stage.dart';
import 'package:appflowy/shared/table_views/gallery_stage.dart';
import 'package:appflowy/shared/table_views/timeline_stage.dart';
import 'package:appflowy/workspace/application/table_views/feed_spec.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy/workspace/application/table_views/timeline_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

const EdgeInsets _stagePadding = EdgeInsets.fromLTRB(40, 4, 40, 20);
const EdgeInsets _innerPadding = EdgeInsets.fromLTRB(4, 8, 4, 6);

/// A tab that lays the database out in time.
class TimelineTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      TimelineTabPage(
        key: ValueKey(view.id),
        view: view,
        databaseController: controller,
      );

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      const SizedBox.shrink();

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) =>
      const SizedBox.shrink();
}

class TimelineTabPage extends StatefulWidget {
  const TimelineTabPage({
    super.key,
    required this.view,
    required this.databaseController,
  });

  final ViewPB view;
  final DatabaseController databaseController;

  @override
  State<TimelineTabPage> createState() => _TimelineTabPageState();
}

class _TimelineTabPageState extends State<TimelineTabPage>
    with TableViewHostPlumbing<TimelineTabPage> {
  final GlobalKey<TimelineStageState> _stage = GlobalKey<TimelineStageState>();

  late TimelineSpec _spec = TimelineSpec.fromJson(
    widget.view.tableViewMark(TableViewKind.timeline)?.settings ?? const {},
  );

  @override
  ViewPB get hostView => widget.view;

  @override
  DatabaseController get hostController => widget.databaseController;

  @override
  TableViewKind get hostKind => TableViewKind.timeline;

  @override
  void onRowsChanged() => _stage.currentState?.reload();

  @override
  void initState() {
    super.initState();
    startHosting();
  }

  @override
  void didUpdateWidget(TimelineTabPage old) {
    super.didUpdateWidget(old);
    if (old.view.extra != widget.view.extra) {
      _spec = TimelineSpec.fromJson(
        widget.view.tableViewMark(TableViewKind.timeline)?.settings ?? const {},
      );
    }
    onRowsChanged();
  }

  void _save(TimelineSpec spec) {
    setState(() => _spec = spec);
    saveHostSettings(spec.toJson());
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: _stagePadding,
        child: TimelineStage(
          key: _stage,
          viewId: widget.view.id,
          spec: _spec,
          title: widget.view.name,
          padding: _innerPadding,
          onSpecChanged: _save,
          onOpenRow: openRow,
          onAddRow: addRow,
          onReschedule: (rowId, start, end) => rescheduleRow(
            _spec.startColumn.isNotEmpty
                ? _spec.startColumn
                : _stage.currentState?.startFieldId ?? '',
            rowId,
            start,
            end,
          ),
        ),
      );
}

/// A tab that reads the database as a column of posts.
class FeedTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      FeedTabPage(
        key: ValueKey(view.id),
        view: view,
        databaseController: controller,
      );

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      const SizedBox.shrink();

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) =>
      const SizedBox.shrink();
}

class FeedTabPage extends StatefulWidget {
  const FeedTabPage({
    super.key,
    required this.view,
    required this.databaseController,
  });

  final ViewPB view;
  final DatabaseController databaseController;

  @override
  State<FeedTabPage> createState() => _FeedTabPageState();
}

class _FeedTabPageState extends State<FeedTabPage>
    with TableViewHostPlumbing<FeedTabPage> {
  final GlobalKey<FeedStageState> _stage = GlobalKey<FeedStageState>();

  late FeedSpec _spec = FeedSpec.fromJson(
    widget.view.tableViewMark(TableViewKind.feed)?.settings ?? const {},
  );

  @override
  ViewPB get hostView => widget.view;

  @override
  DatabaseController get hostController => widget.databaseController;

  @override
  TableViewKind get hostKind => TableViewKind.feed;

  @override
  void onRowsChanged() => _stage.currentState?.reload();

  @override
  void initState() {
    super.initState();
    startHosting();
  }

  @override
  void didUpdateWidget(FeedTabPage old) {
    super.didUpdateWidget(old);
    if (old.view.extra != widget.view.extra) {
      _spec = FeedSpec.fromJson(
        widget.view.tableViewMark(TableViewKind.feed)?.settings ?? const {},
      );
    }
    onRowsChanged();
  }

  void _save(FeedSpec spec) {
    setState(() => _spec = spec);
    saveHostSettings(spec.toJson());
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: _stagePadding,
        child: FeedStage(
          key: _stage,
          viewId: widget.view.id,
          spec: _spec,
          title: widget.view.name,
          padding: _innerPadding,
          onSpecChanged: _save,
          onOpenRow: openRow,
          onAddRow: addRow,
        ),
      );
}

/// A tab that hangs the database on a wall.
class GalleryTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      GalleryTabPage(
        key: ValueKey(view.id),
        view: view,
        databaseController: controller,
      );

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      const SizedBox.shrink();

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) =>
      const SizedBox.shrink();
}

class GalleryTabPage extends StatefulWidget {
  const GalleryTabPage({
    super.key,
    required this.view,
    required this.databaseController,
  });

  final ViewPB view;
  final DatabaseController databaseController;

  @override
  State<GalleryTabPage> createState() => _GalleryTabPageState();
}

class _GalleryTabPageState extends State<GalleryTabPage>
    with TableViewHostPlumbing<GalleryTabPage> {
  final GlobalKey<GalleryStageState> _stage = GlobalKey<GalleryStageState>();

  late GallerySpec _spec = GallerySpec.fromJson(
    widget.view.tableViewMark(TableViewKind.gallery)?.settings ?? const {},
  );

  @override
  ViewPB get hostView => widget.view;

  @override
  DatabaseController get hostController => widget.databaseController;

  @override
  TableViewKind get hostKind => TableViewKind.gallery;

  @override
  void onRowsChanged() => _stage.currentState?.reload();

  @override
  void initState() {
    super.initState();
    startHosting();
  }

  @override
  void didUpdateWidget(GalleryTabPage old) {
    super.didUpdateWidget(old);
    if (old.view.extra != widget.view.extra) {
      _spec = GallerySpec.fromJson(
        widget.view.tableViewMark(TableViewKind.gallery)?.settings ?? const {},
      );
    }
    onRowsChanged();
  }

  void _save(GallerySpec spec) {
    setState(() => _spec = spec);
    saveHostSettings(spec.toJson());
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: _stagePadding,
        child: GalleryStage(
          key: _stage,
          viewId: widget.view.id,
          spec: _spec,
          title: widget.view.name,
          padding: _innerPadding,
          onSpecChanged: _save,
          onOpenRow: openRow,
          onAddRow: addRow,
        ),
      );
}

/// A tab that offers the database as something to fill in.
class FormTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      FormTabPage(
        key: ValueKey(view.id),
        view: view,
        databaseController: controller,
      );

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      const SizedBox.shrink();

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) =>
      const SizedBox.shrink();
}

class FormTabPage extends StatefulWidget {
  const FormTabPage({
    super.key,
    required this.view,
    required this.databaseController,
  });

  final ViewPB view;
  final DatabaseController databaseController;

  @override
  State<FormTabPage> createState() => _FormTabPageState();
}

class _FormTabPageState extends State<FormTabPage>
    with TableViewHostPlumbing<FormTabPage> {
  final GlobalKey<FormStageState> _stage = GlobalKey<FormStageState>();

  late FormSpec _spec = FormSpec.fromJson(
    widget.view.tableViewMark(TableViewKind.form)?.settings ?? const {},
  );

  @override
  ViewPB get hostView => widget.view;

  @override
  DatabaseController get hostController => widget.databaseController;

  @override
  TableViewKind get hostKind => TableViewKind.form;

  @override
  void onRowsChanged() => _stage.currentState?.reload();

  @override
  void initState() {
    super.initState();
    startHosting();
  }

  @override
  void didUpdateWidget(FormTabPage old) {
    super.didUpdateWidget(old);
    if (old.view.extra != widget.view.extra) {
      _spec = FormSpec.fromJson(
        widget.view.tableViewMark(TableViewKind.form)?.settings ?? const {},
      );
    }
  }

  void _save(FormSpec spec) {
    setState(() => _spec = spec);
    saveHostSettings(spec.toJson());
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: _stagePadding,
        child: FormStage(
          key: _stage,
          viewId: widget.view.id,
          spec: _spec,
          title: widget.view.name,
          padding: _innerPadding,
          onSpecChanged: _save,
          onSubmit: addRowWithAnswers,
          onOpenRow: openRow,
        ),
      );
}
