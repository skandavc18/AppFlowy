import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';

/// What a rollup does with the values it gathers from the linked rows.
///
/// The stored value has to match the backend's spelling exactly, since it is
/// what gets written into the column's settings.
enum RollupAggregation {
  showOriginal('show_original'),
  count('count'),
  countValues('count_values'),
  countUnique('count_unique'),
  countEmpty('count_empty'),
  countNotEmpty('count_not_empty'),
  percentEmpty('percent_empty'),
  percentNotEmpty('percent_not_empty'),
  sum('sum'),
  average('average'),
  median('median'),
  min('min'),
  max('max'),
  range('range'),
  earliest('earliest'),
  latest('latest');

  const RollupAggregation(this.value);

  final String value;

  static RollupAggregation fromValue(String value) {
    return RollupAggregation.values.firstWhere(
      (aggregation) => aggregation.value == value,
      orElse: () => RollupAggregation.showOriginal,
    );
  }

  String get label => switch (this) {
        RollupAggregation.showOriginal =>
          LocaleKeys.grid_rollup_aggregation_showOriginal.tr(),
        RollupAggregation.count =>
          LocaleKeys.grid_rollup_aggregation_count.tr(),
        RollupAggregation.countValues =>
          LocaleKeys.grid_rollup_aggregation_countValues.tr(),
        RollupAggregation.countUnique =>
          LocaleKeys.grid_rollup_aggregation_countUnique.tr(),
        RollupAggregation.countEmpty =>
          LocaleKeys.grid_rollup_aggregation_countEmpty.tr(),
        RollupAggregation.countNotEmpty =>
          LocaleKeys.grid_rollup_aggregation_countNotEmpty.tr(),
        RollupAggregation.percentEmpty =>
          LocaleKeys.grid_rollup_aggregation_percentEmpty.tr(),
        RollupAggregation.percentNotEmpty =>
          LocaleKeys.grid_rollup_aggregation_percentNotEmpty.tr(),
        RollupAggregation.sum => LocaleKeys.grid_rollup_aggregation_sum.tr(),
        RollupAggregation.average =>
          LocaleKeys.grid_rollup_aggregation_average.tr(),
        RollupAggregation.median =>
          LocaleKeys.grid_rollup_aggregation_median.tr(),
        RollupAggregation.min => LocaleKeys.grid_rollup_aggregation_min.tr(),
        RollupAggregation.max => LocaleKeys.grid_rollup_aggregation_max.tr(),
        RollupAggregation.range =>
          LocaleKeys.grid_rollup_aggregation_range.tr(),
        RollupAggregation.earliest =>
          LocaleKeys.grid_rollup_aggregation_earliest.tr(),
        RollupAggregation.latest =>
          LocaleKeys.grid_rollup_aggregation_latest.tr(),
      };
}
