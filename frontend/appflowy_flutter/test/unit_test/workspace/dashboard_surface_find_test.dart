import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _document = DashboardDocument(
  subtitle: 'needle subtitle',
  sections: [
    DashboardSection(
      id: 'section',
      title: 'needle section',
      widgets: [
        DashboardWidgetSpec(
          id: 'note',
          type: 'text',
          title: 'needle card',
          settings: {'text': 'needle needle', 'token': 'private_token'},
        ),
        DashboardWidgetSpec(
          id: 'button',
          type: 'button',
          settings: {'label': 'needle label', 'config': 'private_token'},
        ),
        DashboardWidgetSpec(
          id: 'extension',
          type: 'unknown_extension',
          settings: {'text': 'private_token'},
        ),
      ],
    ),
  ],
);

void main() {
  test('dashboard searches owned text and labels, never arbitrary configs', () {
    final dashboard = DashboardController(viewId: '', document: _document);
    final find =
        DashboardFindController(dashboard, title: () => 'needle title');
    addTearDown(dashboard.dispose);
    addTearDown(find.dispose);
    find.open();
    find.setQuery('needle');
    expect(find.matches, hasLength(7));
    expect(find.matches.first.id, dashboardFindTitle);
    expect(find.matches.first.entry.replaceable, isFalse);
    expect(find.matches.map((hit) => hit.id),
        contains(dashboardFindWidget('button', 'label')));
    find.setQuery('private_token');
    expect(find.matches, isEmpty);
    expect(dashboard.document, same(_document));
    expect(dashboard.canUndo, isFalse);
  });

  test('dashboard replace all is one native undo step and preserves config',
      () {
    final dashboard = DashboardController(viewId: '', document: _document);
    final find =
        DashboardFindController(dashboard, title: () => 'needle title');
    addTearDown(dashboard.dispose);
    addTearDown(find.dispose);
    find.open(replace: true);
    find.setQuery('needle');
    find.replacementController.text = 'thread';
    find.replaceAll();
    expect(dashboard.document.subtitle, 'thread subtitle');
    expect(dashboard.document.widgetById('note')!.setting('text'),
        'thread thread');
    expect(dashboard.document.widgetById('note')!.setting('token'),
        'private_token');
    expect(find.matches.single.id, dashboardFindTitle);
    dashboard.undo();
    expect(dashboard.document, _document);
    expect(dashboard.canUndo, isFalse);
    dashboard.redo();
    expect(dashboard.document.widgetById('note')!.setting('text'),
        'thread thread');
    dashboard.setReadOnly(true, notify: false);
    final before = dashboard.document;
    find.setQuery('thread');
    find.replaceAll();
    expect(dashboard.document, same(before));
    expect(find.supportsReplace, isFalse);
  });

  test('suspended dashboard drafts are searchable but not replaceable', () {
    final dashboard = DashboardController(viewId: '', document: _document);
    final find = DashboardFindController(dashboard, title: () => 'title');
    final draft = TextEditingController(text: 'uncommitted draftword');
    addTearDown(dashboard.dispose);
    addTearDown(draft.dispose);
    addTearDown(find.dispose);
    find.watchDraft(dashboardFindWidget('note', 'text'), draft);
    find.open();
    find.setQuery('draftword');
    expect(find.matches, hasLength(1));
    expect(find.current!.entry.replaceable, isFalse);
    find.replacementController.text = 'lost';
    find.replaceAll();
    expect(draft.text, 'uncommitted draftword');
    expect(dashboard.document, same(_document));
  });

  test('unregistering an enlarged field retains the original card draft', () {
    final dashboard = DashboardController(viewId: '', document: _document);
    final find = DashboardFindController(dashboard, title: () => 'title');
    final original = TextEditingController(text: 'original draftword');
    final enlarged = TextEditingController(text: 'needle needle');
    addTearDown(dashboard.dispose);
    addTearDown(original.dispose);
    addTearDown(enlarged.dispose);
    addTearDown(find.dispose);
    final id = dashboardFindWidget('note', 'text');
    find.watchDraft(id, original);
    find.watchDraft(id, enlarged);
    find.open();
    find.setQuery('needle');
    expect(
        find.matches
            .where((hit) => hit.id == id)
            .every((hit) => !hit.entry.replaceable),
        isTrue);
    find.close();
    find.unwatchDraft(id, enlarged);
    find.open();
    find.setQuery('draftword');
    expect(find.current!.entry.text, 'original draftword');
    expect(original.text, 'original draftword');
  });

  test('presentation can find collapsed text without changing the document',
      () {
    final document = _document.copyWith(sections: [
      _document.sections.single.copyWith(collapsed: true),
    ]);
    final dashboard = DashboardController(
      viewId: '',
      document: document,
      mode: DashboardMode.presentation,
    );
    final find = DashboardFindController(dashboard, title: () => 'title');
    addTearDown(dashboard.dispose);
    addTearDown(find.dispose);
    find.open();
    find.setQuery('needle');
    expect(find.matches, isNotEmpty);
    expect(find.matches.every((hit) => !hit.entry.replaceable), isTrue);
    expect(dashboard.document, same(document));
  });
}
