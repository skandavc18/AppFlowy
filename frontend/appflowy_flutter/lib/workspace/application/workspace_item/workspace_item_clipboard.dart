import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

enum WorkspaceItemClipboardOperation {
  copy,
  cut;
}

@immutable
class WorkspaceItemClipboardData {
  const WorkspaceItemClipboardData({
    required this.operation,
    required this.views,
  });

  final WorkspaceItemClipboardOperation operation;
  final List<ViewPB> views;
}

class WorkspaceItemClipboard extends ChangeNotifier {
  WorkspaceItemClipboard._();

  static final instance = WorkspaceItemClipboard._();

  WorkspaceItemClipboardData? _data;

  WorkspaceItemClipboardData? get data => _data;
  bool get hasData => _data?.views.isNotEmpty ?? false;

  void copy(Iterable<ViewPB> views) {
    _set(WorkspaceItemClipboardOperation.copy, views);
  }

  void cut(Iterable<ViewPB> views) {
    _set(WorkspaceItemClipboardOperation.cut, views);
  }

  void clear() {
    if (_data == null) {
      return;
    }
    _data = null;
    notifyListeners();
  }

  void _set(
    WorkspaceItemClipboardOperation operation,
    Iterable<ViewPB> views,
  ) {
    _data = WorkspaceItemClipboardData(
      operation: operation,
      views: List.unmodifiable(
        views.map((view) => ViewPB.fromBuffer(view.writeToBuffer())),
      ),
    );
    notifyListeners();
  }
}
