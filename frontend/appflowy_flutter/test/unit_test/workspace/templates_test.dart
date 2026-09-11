import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/built_in_templates.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/field_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB _view({String extra = '', ViewLayoutPB? layout}) => ViewPB()
  ..id = 'view'
  ..name = 'A page'
  ..layout = layout ?? ViewLayoutPB.Document
  ..extra = extra;

/// Every widget a template's dashboards ask for, at every depth.
Iterable<DashboardWidgetSpec> _widgetsOf(DashboardDocument document) sync* {
  for (final section in document.sections) {
    yield* section.widgets;
  }
}

Iterable<DashboardWidgetSpec> _everyWidgetIn(WorkspaceTemplate template) sync* {
  for (final part in template.parts) {
    final blueprint = part.blueprint;
    if (blueprint is TemplateDashboard) {
      yield* _widgetsOf(blueprint.build(const {}));
    }
  }
}

Iterable<TemplateTable> _everyTableIn(WorkspaceTemplate template) sync* {
  for (final part in template.parts) {
    final blueprint = part.blueprint;
    if (blueprint is TemplateDatabase) {
      yield blueprint.build(const {});
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the registry', () {
    tearDown(TemplateRegistry.reset);

    test('ships templates on every shelf', () {
      expect(TemplateRegistry.all(), isNotEmpty);
      for (final category in TemplateCategory.values) {
        expect(
          TemplateRegistry.inCategory(category),
          isNotEmpty,
          reason: 'no template on the $category shelf',
        );
      }
    });

    test('gives every template an id of its own', () {
      final ids = TemplateRegistry.all().map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('finds a template by id, and nothing by a made-up one', () {
      expect(TemplateRegistry.forId('stocks'), isNotNull);
      expect(TemplateRegistry.forId('nothing_like_this'), isNull);
    });

    test('every featured template really exists', () {
      for (final id in featuredTemplateIds) {
        expect(
          TemplateRegistry.forId(id),
          isNotNull,
          reason: '"$id" is featured but is not registered',
        );
      }
    });

    test('folds in the dashboards and canvases that already existed', () {
      expect(TemplateRegistry.forId('board_personal'), isNotNull);
      expect(TemplateRegistry.forId('canvas_mind_map'), isNotNull);
    });

    test('ranks an exact name above a keyword', () {
      final results = TemplateRegistry.search('stocks');
      expect(results, isNotEmpty);
      expect(results.first.id, 'stocks');
    });

    test('an extension taking its templates away leaves the rest', () {
      final before = TemplateRegistry.all().length;
      TemplateRegistry.register(
        WorkspaceTemplate(
          id: 'from_an_extension',
          category: TemplateCategory.work,
          extensionId: 'somebody',
          label: () => 'From an extension',
          description: () => '',
          icon: Icons.abc,
          build: () => [
            TemplatePart(
              key: 'board',
              name: () => 'x',
              blueprint: TemplateDashboard((_) => DashboardDocument.blank()),
            ),
          ],
        ),
      );
      expect(TemplateRegistry.all().length, before + 1);

      TemplateRegistry.unregisterAll('somebody');
      expect(TemplateRegistry.all().length, before);
      expect(TemplateRegistry.forId('from_an_extension'), isNull);
    });

    test('unregistering nothing in particular removes nothing', () {
      final before = TemplateRegistry.all().length;
      TemplateRegistry.unregisterAll('');
      expect(TemplateRegistry.all().length, before);
    });
  });

  group('what every template makes', () {
    tearDown(TemplateRegistry.reset);

    test('builds without throwing, and names itself', () {
      for (final template in TemplateRegistry.all()) {
        expect(template.parts, isNotEmpty, reason: template.id);
        expect(template.label(), isNotEmpty, reason: template.id);
        expect(template.description(), isNotEmpty, reason: template.id);
        for (final part in template.parts) {
          expect(part.key, isNotEmpty, reason: template.id);
          expect(part.name(), isNotEmpty, reason: '${template.id}/${part.key}');
        }
      }
    });

    test('gives every part of one template a key of its own', () {
      for (final template in TemplateRegistry.all()) {
        final keys = template.parts.map((part) => part.key).toList();
        expect(keys.toSet().length, keys.length, reason: template.id);
      }
    });

    test('reports the right kind', () {
      expect(TemplateRegistry.forId('stocks')?.kind, TemplateKind.dashboard);
      expect(TemplateRegistry.forId('landing')?.kind, TemplateKind.page);
      expect(
        TemplateRegistry.forId('subscriptions')?.kind,
        TemplateKind.database,
      );
      expect(TemplateRegistry.forId('assets')?.kind, TemplateKind.bundle);
      expect(
        TemplateRegistry.forId('canvas_mind_map')?.kind,
        TemplateKind.canvas,
      );
    });

    test('writes something into every page it makes', () {
      for (final template in TemplateRegistry.all()) {
        for (final part in template.parts) {
          final blueprint = part.blueprint;
          if (blueprint is TemplatePage) {
            expect(
              blueprint.markdown(const {}).trim(),
              isNotEmpty,
              reason: '${template.id}/${part.key}',
            );
          }
        }
      }
    });

    // The one mistake that only shows up as a page of "unknown widget"
    // placards: a widget type nobody registers.
    test('only asks for widgets that exist', () {
      for (final template in TemplateRegistry.all()) {
        for (final spec in _everyWidgetIn(template)) {
          if (spec.type.startsWith('ext.')) {
            continue;
          }
          expect(
            DashboardWidgetRegistry.definitionFor(spec.type),
            isNotNull,
            reason: '${template.id} asks for the unknown widget "${spec.type}"',
          );
        }
      }
    });

    test('declares the extension behind every extension widget it uses', () {
      for (final template in TemplateRegistry.all()) {
        for (final spec in _everyWidgetIn(template)) {
          if (!spec.type.startsWith('ext.')) {
            continue;
          }
          final owner = spec.type.split('.')[1];
          expect(
            template.requires,
            contains(owner),
            reason: '${template.id} uses ${spec.type} without asking for it',
          );
        }
      }
    });

    test('a template that needs nothing declares nothing', () {
      expect(TemplateRegistry.forId('assets')?.requires, isEmpty);
      expect(TemplateRegistry.forId('stocks')?.requires, contains('stock'));
      expect(TemplateRegistry.forId('news_weather')?.requires, contains('news'));
    });
  });

  group('the tables a template asks for', () {
    tearDown(TemplateRegistry.reset);

    test('lead with a text column, because the primary cannot be retyped', () {
      for (final template in TemplateRegistry.all()) {
        for (final table in _everyTableIn(template)) {
          expect(table.columns, isNotEmpty, reason: template.id);
          expect(
            table.columns.first.type,
            FieldType.RichText,
            reason: '${template.id} leads with a column that cannot be primary',
          );
        }
      }
    });

    test('name every column, and name each one once', () {
      for (final template in TemplateRegistry.all()) {
        for (final table in _everyTableIn(template)) {
          final names = [for (final column in table.columns) column.name];
          expect(
            names.any((name) => name.isEmpty),
            isFalse,
            reason: template.id,
          );
          expect(names.toSet().length, names.length, reason: template.id);
        }
      }
    });

    test('give a select column something to select', () {
      for (final template in TemplateRegistry.all()) {
        for (final table in _everyTableIn(template)) {
          for (final column in table.columns) {
            final selects = column.type == FieldType.SingleSelect ||
                column.type == FieldType.MultiSelect;
            expect(
              selects,
              column.options.isNotEmpty,
              reason: '${template.id}: "${column.name}" has the wrong options',
            );
          }
        }
      }
    });

    test('write no more cells than there are columns', () {
      for (final template in TemplateRegistry.all()) {
        for (final table in _everyTableIn(template)) {
          for (final row in table.rows) {
            expect(
              row.length,
              lessThanOrEqualTo(table.columns.length),
              reason: '${template.id} seeds a row wider than its table',
            );
          }
        }
      }
    });

    // A value that names no option would silently leave the cell empty.
    test('only choose options the column actually offers', () {
      for (final template in TemplateRegistry.all()) {
        for (final table in _everyTableIn(template)) {
          for (final row in table.rows) {
            for (var i = 0; i < row.length; i++) {
              final column = table.columns[i];
              if (column.options.isEmpty || row[i].isEmpty) {
                continue;
              }
              for (final chosen in row[i].split(',')) {
                expect(
                  column.options,
                  contains(chosen.trim()),
                  reason: '${template.id}: "${chosen.trim()}" is not an option '
                      'of "${column.name}"',
                );
              }
            }
          }
        }
      }
    });

    test('seed a date only in a form a date column can read', () {
      for (final template in TemplateRegistry.all()) {
        for (final table in _everyTableIn(template)) {
          for (final row in table.rows) {
            for (var i = 0; i < row.length; i++) {
              if (table.columns[i].type != FieldType.DateTime ||
                  row[i].isEmpty) {
                continue;
              }
              expect(
                DateTime.tryParse(row[i]),
                isNotNull,
                reason: '${template.id}: "${row[i]}" is not a date',
              );
            }
          }
        }
      }
    });
  });

  group('laying a template over something that already exists', () {
    tearDown(TemplateRegistry.reset);

    test('a dashboard template fits a dashboard and nothing else', () {
      final template = TemplateRegistry.forId('stocks')!;
      expect(
        template.appliesTo(_view(extra: DashboardMetadata.newExtra())),
        isTrue,
      );
      expect(template.appliesTo(_view()), isFalse);
      expect(
        template.appliesTo(_view(extra: CanvasMetadata.newExtra())),
        isFalse,
      );
    });

    test('a page template fits a plain page, not a dashboard', () {
      final template = TemplateRegistry.forId('landing')!;
      expect(template.appliesTo(_view()), isTrue);
      expect(
        template.appliesTo(_view(extra: DashboardMetadata.newExtra())),
        isFalse,
      );
    });

    test('a canvas template fits a canvas', () {
      final template = TemplateRegistry.forId('canvas_swot')!;
      expect(template.appliesTo(_view(extra: CanvasMetadata.newExtra())), isTrue);
      expect(template.appliesTo(_view()), isFalse);
    });

    test('a template of several parts fits nothing that already exists', () {
      final template = TemplateRegistry.forId('assets')!;
      expect(template.appliesTo(_view()), isFalse);
      expect(
        template.appliesTo(_view(extra: DashboardMetadata.newExtra())),
        isFalse,
      );
    });

    test('a table template is never laid over a page', () {
      final template = TemplateRegistry.forId('subscriptions')!;
      expect(template.appliesTo(_view()), isFalse);
      expect(
        template.appliesTo(_view(layout: ViewLayoutPB.Grid)),
        isFalse,
      );
    });

    test('a plain page is offered something, a grid is offered nothing', () {
      expect(TemplateRegistry.applicableTo(_view()), isNotEmpty);
      expect(
        TemplateRegistry.applicableTo(_view(layout: ViewLayoutPB.Grid)),
        isEmpty,
      );
    });
  });

  group('a dashboard bound to a table the template just made', () {
    tearDown(TemplateRegistry.reset);

    test('points its widgets at the table', () {
      final template = TemplateRegistry.forId('assets')!;
      final board = template.parts.last.blueprint as TemplateDashboard;
      final bound = board.build(const {'holdings': 'the-table-id'});
      final sources = [
        for (final spec in _widgetsOf(bound))
          if (spec.source.viewId.isNotEmpty) spec.source.viewId,
      ];
      expect(sources, isNotEmpty);
      expect(sources.every((id) => id == 'the-table-id'), isTrue);
    });

    // A part that could not be made must leave a widget asking to be pointed
    // at something, never a widget bound to an empty id.
    test('leaves a widget unbound when the table was not made', () {
      final template = TemplateRegistry.forId('assets')!;
      final board = template.parts.last.blueprint as TemplateDashboard;
      final unbound = board.build(const {});
      for (final spec in _widgetsOf(unbound)) {
        expect(spec.source.isBound, isFalse);
      }
    });
  });
}
