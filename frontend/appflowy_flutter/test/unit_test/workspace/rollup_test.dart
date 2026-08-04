import 'package:appflowy/plugins/database/application/field/type_option/rollup_cubit.dart';
import 'package:appflowy/plugins/database/application/field/type_option/rollup_entities.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

FieldPB _field(String id, String name, FieldType type) {
  return FieldPB()
    ..id = id
    ..name = name
    ..fieldType = type;
}

void main() {
  group('rollup aggregations', () {
    test('every aggregation has a name the backend agrees with', () {
      final names = RollupAggregation.values.map((a) => a.value).toList();

      expect(names, contains('show_original'));
      expect(names, contains('count_not_empty'));
      expect(names, contains('percent_not_empty'));
      expect(names, contains('earliest'));
      expect(names.toSet().length, RollupAggregation.values.length);
    });

    test('a stored name comes back as the same aggregation', () {
      for (final aggregation in RollupAggregation.values) {
        expect(
          RollupAggregation.fromValue(aggregation.value),
          aggregation,
        );
      }
    });

    test('a name nobody recognises falls back to showing the values', () {
      expect(
        RollupAggregation.fromValue('something_else'),
        RollupAggregation.showOriginal,
      );
    });
  });

  group('rollup settings', () {
    final relations = [_field('rel', 'Tasks', FieldType.Relation)];
    final targets = [_field('cost', 'Cost', FieldType.Number)];

    test('a rollup needs both a relation and a property', () {
      const nothing = RollupState.initial();
      expect(nothing.isConfigured, isFalse);

      final halfWay = nothing.copyWith(relationFieldId: 'rel');
      expect(halfWay.isConfigured, isFalse);

      final done = halfWay.copyWith(targetFieldId: 'cost');
      expect(done.isConfigured, isTrue);
    });

    test('it names the columns it is pointed at', () {
      final state = const RollupState.initial().copyWith(
        relations: relations,
        targets: targets,
        relationFieldId: 'rel',
        targetFieldId: 'cost',
      );

      expect(state.relation?.name, 'Tasks');
      expect(state.target?.name, 'Cost');
    });

    test('a column that has gone away is simply absent', () {
      final state = const RollupState.initial().copyWith(
        relations: relations,
        targets: targets,
        relationFieldId: 'rel',
        targetFieldId: 'deleted',
      );

      expect(state.relation?.name, 'Tasks');
      expect(state.target, isNull);
      expect(state.isConfigured, isTrue);
    });

    test('what is not changed is left alone', () {
      final state = const RollupState.initial().copyWith(
        isLoading: false,
        relations: relations,
        relationFieldId: 'rel',
        aggregation: RollupAggregation.sum,
      );

      final next = state.copyWith(targetFieldId: 'cost');

      expect(next.isLoading, isFalse);
      expect(next.relations, relations);
      expect(next.relationFieldId, 'rel');
      expect(next.aggregation, RollupAggregation.sum);
      expect(next.targetFieldId, 'cost');
    });
  });
}
