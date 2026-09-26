import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Runs once per active workspace, independent of latest-view notifications.
/// Its lifetime guard also covers account changes while Home is being read.
class StartupHome extends StatefulWidget {
  const StartupHome({
    super.key,
    required this.workspaceId,
    required this.child,
  });

  final String workspaceId;
  final Widget child;

  @override
  State<StartupHome> createState() => _StartupHomeState();
}

class _StartupHomeState extends State<StartupHome> {
  TabsBloc? _tabs;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabs = context.read<TabsBloc>();
    if (identical(tabs, _tabs)) return;
    _tabs = tabs;
    _open();
  }

  @override
  void didUpdateWidget(covariant StartupHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) _open();
  }

  void _open() {
    final generation = ++_generation;
    final workspace = context.read<UserWorkspaceBloc?>();
    final workspaceId = widget.workspaceId;
    final userId = workspace?.state.userProfile.id;
    final initializing = workspace?.state.currentWorkspace == null;
    unawaited(
      _tabs!.openHome(
        workspaceId: workspaceId,
        startup: true,
        // The bloc can change identity before the selector's next frame.
        isCurrent: () =>
            mounted &&
            generation == _generation &&
            (workspace == null ||
                (!workspace.isClosed &&
                    workspace.state.userProfile.id == userId &&
                    (workspace.state.currentWorkspace?.workspaceId ==
                            workspaceId ||
                        (initializing &&
                            workspace.state.currentWorkspace == null)))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
