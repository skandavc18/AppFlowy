import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/startup/startup.dart';

/// Begin each application session with only top-level sidebar items visible.
///
/// Reset the tree's UI preference before any ViewBloc is created, not whenever
/// a sidebar widget rebuilds. Explicit expansion still persists within the
/// session (including when a parent is collapsed and its children remounted).
/// Section/space headers keep their existing expanded defaults.
class SidebarExpansionTask extends LaunchTask {
  const SidebarExpansionTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    await context.getIt<KeyValueStorage>().remove(KVKeys.expandedViews);
  }
}
