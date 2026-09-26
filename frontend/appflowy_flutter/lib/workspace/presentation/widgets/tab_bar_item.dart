import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/presentation/widgets/workspace_breadcrumb_children.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class ViewTabBarItem extends StatefulWidget {
  const ViewTabBarItem({
    super.key,
    required this.view,
    this.shortForm = false,
  });

  final ViewPB view;
  final bool shortForm;

  @override
  State<ViewTabBarItem> createState() => _ViewTabBarItemState();
}

class _ViewTabBarItemState extends State<ViewTabBarItem> {
  late final ViewListener _viewListener;
  late ViewPB view;

  @override
  void initState() {
    super.initState();
    view = widget.view;
    _viewListener = ViewListener(viewId: widget.view.id);
    _viewListener.start(
      onViewUpdated: (updatedView) {
        if (mounted) {
          setState(() => view = updatedView);
        }
      },
    );
  }

  @override
  void dispose() {
    _viewListener.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          widget.shortForm ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        WorkspaceBreadcrumbIcon(view: view, size: 16),
        if (!widget.shortForm) ...[
          const HSpace(8),
          Flexible(
            child: Text(
              view.nameOrDefault,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DefaultTextStyle.of(context).style.copyWith(
                    fontSize: 13,
                    height: 1.2,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
