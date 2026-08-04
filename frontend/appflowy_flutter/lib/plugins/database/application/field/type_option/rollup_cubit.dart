import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/rollup_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';

import 'rollup_entities.dart';

/// Everything the rollup editor needs to show: which relations this database
/// has, what the chosen one can reach, and what is currently set.
class RollupState {
  const RollupState({
    required this.isLoading,
    required this.relations,
    required this.targets,
    required this.relationFieldId,
    required this.targetFieldId,
    required this.aggregation,
  });

  const RollupState.initial()
      : isLoading = true,
        relations = const [],
        targets = const [],
        relationFieldId = '',
        targetFieldId = '',
        aggregation = RollupAggregation.showOriginal;

  final bool isLoading;
  final List<FieldPB> relations;
  final List<FieldPB> targets;
  final String relationFieldId;
  final String targetFieldId;
  final RollupAggregation aggregation;

  bool get isConfigured =>
      relationFieldId.isNotEmpty && targetFieldId.isNotEmpty;

  FieldPB? get relation => _find(relations, relationFieldId);

  FieldPB? get target => _find(targets, targetFieldId);

  RollupState copyWith({
    bool? isLoading,
    List<FieldPB>? relations,
    List<FieldPB>? targets,
    String? relationFieldId,
    String? targetFieldId,
    RollupAggregation? aggregation,
  }) {
    return RollupState(
      isLoading: isLoading ?? this.isLoading,
      relations: relations ?? this.relations,
      targets: targets ?? this.targets,
      relationFieldId: relationFieldId ?? this.relationFieldId,
      targetFieldId: targetFieldId ?? this.targetFieldId,
      aggregation: aggregation ?? this.aggregation,
    );
  }

  static FieldPB? _find(List<FieldPB> fields, String id) {
    for (final field in fields) {
      if (field.id == id) {
        return field;
      }
    }
    return null;
  }
}

class RollupCubit extends Cubit<RollupState> {
  RollupCubit({required this.viewId, required this.fieldId})
      : super(const RollupState.initial()) {
    _load();
  }

  final String viewId;
  final String fieldId;

  Future<void> _load() async {
    final fields = await FieldBackendService.getFields(viewId: viewId)
        .fold<List<FieldPB>>((fields) => fields, (_) => []);
    final relations =
        fields.where((field) => field.fieldType == FieldType.Relation).toList();

    final settings = await RollupBackendService.getSettings(
      viewId: viewId,
      fieldId: fieldId,
    ).fold<RollupSettingsPB?>((settings) => settings, (_) => null);

    final relationFieldId = settings?.relationFieldId ?? '';
    final targets = relationFieldId.isEmpty
        ? <FieldPB>[]
        : await _loadTargets(relationFieldId);

    if (isClosed) {
      return;
    }
    emit(
      RollupState(
        isLoading: false,
        relations: relations,
        targets: targets,
        relationFieldId: relationFieldId,
        targetFieldId: settings?.targetFieldId ?? '',
        aggregation: RollupAggregation.fromValue(
          settings?.aggregation ?? 'show_original',
        ),
      ),
    );
  }

  Future<List<FieldPB>> _loadTargets(String relationFieldId) {
    return RollupBackendService.getTargets(
      viewId: viewId,
      relationFieldId: relationFieldId,
    ).fold<List<FieldPB>>((fields) => fields, (_) => []);
  }

  /// Follows a different relation. The property has to be picked again, since
  /// the other database has its own columns.
  Future<void> selectRelation(String relationFieldId) async {
    if (relationFieldId == state.relationFieldId) {
      return;
    }
    emit(
      state.copyWith(
        relationFieldId: relationFieldId,
        targetFieldId: '',
        targets: const [],
      ),
    );
    final targets = await _loadTargets(relationFieldId);
    if (isClosed) {
      return;
    }
    emit(state.copyWith(targets: targets));
  }

  Future<void> selectTarget(String targetFieldId) async {
    emit(state.copyWith(targetFieldId: targetFieldId));
    await _save();
  }

  Future<void> selectAggregation(RollupAggregation aggregation) async {
    emit(state.copyWith(aggregation: aggregation));
    await _save();
  }

  /// Stops rolling up. The values already written stay put, as plain text.
  Future<void> clear() async {
    emit(
      state.copyWith(
        relationFieldId: '',
        targetFieldId: '',
        targets: const [],
        aggregation: RollupAggregation.showOriginal,
      ),
    );
    await RollupBackendService.updateSettings(
      viewId: viewId,
      fieldId: fieldId,
      relationFieldId: '',
      targetFieldId: '',
      aggregation: RollupAggregation.showOriginal.value,
    );
  }

  Future<void> recalculate() =>
      RollupBackendService.recalculate(viewId: viewId);

  Future<void> _save() async {
    if (!state.isConfigured) {
      return;
    }
    await RollupBackendService.updateSettings(
      viewId: viewId,
      fieldId: fieldId,
      relationFieldId: state.relationFieldId,
      targetFieldId: state.targetFieldId,
      aggregation: state.aggregation.value,
    );
  }
}
