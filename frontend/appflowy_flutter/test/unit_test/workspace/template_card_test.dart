import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/templates/presentation/template_card.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceTemplate _template() => WorkspaceTemplate(
      id: 'a_template',
      category: TemplateCategory.work,
      label: () => 'A template',
      description: () => 'Short',
      icon: Icons.dashboard_rounded,
      build: () => [
        TemplatePart(
          key: 'board',
          name: () => 'A board',
          blueprint: TemplateDashboard((_) => DashboardDocument.blank()),
        ),
      ],
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required VoidCallback onChosen,
  bool compact = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 136,
            child: Builder(
              builder: (context) => TemplateCard(
                template: _template(),
                palette: DashboardPalette.of(context),
                compact: compact,
                onChosen: onChosen,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('pressing a template card', () {
    // A card is mostly empty space. `GestureDetector` defers to its child by
    // default, so without an opaque hit test the Spacer swallows the press and
    // the card reads as a dead button.
    testWidgets('a press on the empty middle still chooses it', (tester) async {
      var chosen = 0;
      await _pumpCard(tester, onChosen: () => chosen++);

      // The middle of a card is a gap: below the name and above the footer,
      // with nothing drawn in it. Nothing there answers a press on its own.
      final middle = tester.getCenter(find.byType(TemplateCard));
      expect(
        tester.widget<Column>(find.byType(Column).first).children,
        contains(isA<Spacer>()),
        reason: 'the test is meaningless unless the card really has a gap',
      );

      await tester.tapAt(middle);
      await tester.pump();
      expect(chosen, 1);
    });

    testWidgets('a press on the name chooses it', (tester) async {
      var chosen = 0;
      await _pumpCard(tester, onChosen: () => chosen++);

      await tester.tap(find.text('A template'));
      await tester.pump();
      expect(chosen, 1);
    });

    testWidgets('a press on the padding at the very edge chooses it',
        (tester) async {
      var chosen = 0;
      await _pumpCard(tester, onChosen: () => chosen++);

      final card = tester.getRect(find.byType(TemplateCard));
      await tester.tapAt(card.bottomLeft + const Offset(4, -4));
      await tester.pump();
      expect(chosen, 1);
    });

    testWidgets('a compact card answers a press too', (tester) async {
      var chosen = 0;
      await _pumpCard(tester, onChosen: () => chosen++, compact: true);

      await tester.tapAt(tester.getCenter(find.byType(TemplateCard)));
      await tester.pump();
      expect(chosen, 1);
    });
  });
}
