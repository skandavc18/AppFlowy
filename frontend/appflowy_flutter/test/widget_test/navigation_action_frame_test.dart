import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the tab request instead of building a plugin.
class _TabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TabsBloc() : super(TabsState(pageManagers: []));

  final opened = <String>[];

  @override
  void openPlugin(
    ViewPB view, {
    Map<String, dynamic> arguments = const {},
    bool setLatest = true,
  }) =>
      opened.add(view.id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'a page opened from an idle window does not wait for a stray repaint',
    (tester) async {
      getIt.pushNewScope();
      final tabs = _TabsBloc();
      getIt.registerSingleton<TabsBloc>(tabs);
      try {
        await tester.pumpWidget(const SizedBox());
        // Nothing on screen is animating: no frame is coming by itself.
        expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);

        final view = ViewPB(
          id: 'thumbnail-page',
          name: 'Thumbnail page',
          layout: ViewLayoutPB.Document,
        );
        scheduleNavigationAction(
          NavigationAction(
            objectId: view.id,
            arguments: {ActionArgumentKeys.view: view},
          ),
        );

        expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);
        expect(tabs.opened, isEmpty);
        await tester.pump();
        expect(tabs.opened, ['thumbnail-page']);
        expect(tester.takeException(), isNull);
      } finally {
        await tabs.close();
        await getIt.popScope();
      }
    },
  );
}
