use collab::util::AnyMapExt;
use collab_database::entity::FieldType;
use collab_database::fields::{Field, TypeOptionData, TypeOptionDataBuilder};
use collab_database::rows::Row;
use std::str::FromStr;

use crate::services::cell::stringify_cell;

/// The key a rollup's settings are stored under on a field.
///
/// A rollup is not a field type of its own: it is a text field the app keeps
/// filled in. Type options are an open map keyed by string, so the settings
/// ride along beside the text field's own without disturbing anything that
/// does not know to look for them — a build without rollups still reads the
/// column, it just stops recalculating it.
pub const ROLLUP_TYPE_OPTION_KEY: &str = "rollup";

/// What a rollup does with the values it gathers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RollupAggregation {
  #[default]
  ShowOriginal,
  Count,
  CountValues,
  CountUnique,
  CountEmpty,
  CountNotEmpty,
  PercentEmpty,
  PercentNotEmpty,
  Sum,
  Average,
  Median,
  Min,
  Max,
  Range,
  Earliest,
  Latest,
}

impl RollupAggregation {
  pub fn as_str(&self) -> &'static str {
    match self {
      RollupAggregation::ShowOriginal => "show_original",
      RollupAggregation::Count => "count",
      RollupAggregation::CountValues => "count_values",
      RollupAggregation::CountUnique => "count_unique",
      RollupAggregation::CountEmpty => "count_empty",
      RollupAggregation::CountNotEmpty => "count_not_empty",
      RollupAggregation::PercentEmpty => "percent_empty",
      RollupAggregation::PercentNotEmpty => "percent_not_empty",
      RollupAggregation::Sum => "sum",
      RollupAggregation::Average => "average",
      RollupAggregation::Median => "median",
      RollupAggregation::Min => "min",
      RollupAggregation::Max => "max",
      RollupAggregation::Range => "range",
      RollupAggregation::Earliest => "earliest",
      RollupAggregation::Latest => "latest",
    }
  }

  /// Whether the gathered values have to be numbers.
  pub fn needs_numbers(&self) -> bool {
    matches!(
      self,
      RollupAggregation::Sum
        | RollupAggregation::Average
        | RollupAggregation::Median
        | RollupAggregation::Min
        | RollupAggregation::Max
        | RollupAggregation::Range
    )
  }
}

impl FromStr for RollupAggregation {
  type Err = ();

  fn from_str(value: &str) -> Result<Self, Self::Err> {
    Ok(match value {
      "count" => RollupAggregation::Count,
      "count_values" => RollupAggregation::CountValues,
      "count_unique" => RollupAggregation::CountUnique,
      "count_empty" => RollupAggregation::CountEmpty,
      "count_not_empty" => RollupAggregation::CountNotEmpty,
      "percent_empty" => RollupAggregation::PercentEmpty,
      "percent_not_empty" => RollupAggregation::PercentNotEmpty,
      "sum" => RollupAggregation::Sum,
      "average" => RollupAggregation::Average,
      "median" => RollupAggregation::Median,
      "min" => RollupAggregation::Min,
      "max" => RollupAggregation::Max,
      "range" => RollupAggregation::Range,
      "earliest" => RollupAggregation::Earliest,
      "latest" => RollupAggregation::Latest,
      _ => RollupAggregation::ShowOriginal,
    })
  }
}

/// Which relation to follow, which column to read on the far side, and what to
/// do with what comes back.
#[derive(Debug, Clone, Default)]
pub struct RollupTypeOption {
  pub relation_field_id: String,
  pub target_field_id: String,
  pub aggregation: RollupAggregation,
}

impl RollupTypeOption {
  pub fn is_configured(&self) -> bool {
    !self.relation_field_id.is_empty() && !self.target_field_id.is_empty()
  }

  /// The rollup settings on a field, if it carries any.
  pub fn from_field(field: &Field) -> Option<Self> {
    let data = field.get_any_type_option(ROLLUP_TYPE_OPTION_KEY)?;
    let option = RollupTypeOption::from(data);
    option.is_configured().then_some(option)
  }
}

impl From<TypeOptionData> for RollupTypeOption {
  fn from(data: TypeOptionData) -> Self {
    let aggregation: String = data.get_as("aggregation").unwrap_or_default();
    Self {
      relation_field_id: data.get_as("relation_field_id").unwrap_or_default(),
      target_field_id: data.get_as("target_field_id").unwrap_or_default(),
      aggregation: RollupAggregation::from_str(&aggregation).unwrap_or_default(),
    }
  }
}

impl From<RollupTypeOption> for TypeOptionData {
  fn from(data: RollupTypeOption) -> Self {
    TypeOptionDataBuilder::from([
      ("relation_field_id".into(), data.relation_field_id.into()),
      ("target_field_id".into(), data.target_field_id.into()),
      (
        "aggregation".into(),
        data.aggregation.as_str().to_string().into(),
      ),
    ])
  }
}

/// Reduces the values gathered from the linked rows to the one string a
/// rollup cell shows.
pub fn apply_rollup(
  aggregation: RollupAggregation,
  values: &[String],
  linked_rows: usize,
) -> String {
  let filled: Vec<&String> = values.iter().filter(|v| !v.trim().is_empty()).collect();
  let empty = linked_rows.saturating_sub(filled.len());

  match aggregation {
    RollupAggregation::ShowOriginal => filled
      .iter()
      .map(|v| v.trim())
      .collect::<Vec<_>>()
      .join(", "),
    RollupAggregation::Count => linked_rows.to_string(),
    RollupAggregation::CountValues => filled.len().to_string(),
    RollupAggregation::CountUnique => {
      let mut seen: Vec<&str> = filled.iter().map(|v| v.trim()).collect();
      seen.sort_unstable();
      seen.dedup();
      seen.len().to_string()
    },
    RollupAggregation::CountEmpty => empty.to_string(),
    RollupAggregation::CountNotEmpty => filled.len().to_string(),
    RollupAggregation::PercentEmpty => percent(empty, linked_rows),
    RollupAggregation::PercentNotEmpty => percent(filled.len(), linked_rows),
    RollupAggregation::Earliest | RollupAggregation::Latest => {
      let mut sorted: Vec<&str> = filled.iter().map(|v| v.trim()).collect();
      sorted.sort_unstable();
      let picked = if aggregation == RollupAggregation::Earliest {
        sorted.first()
      } else {
        sorted.last()
      };
      picked.map(|v| v.to_string()).unwrap_or_default()
    },
    _ => numeric_rollup(aggregation, &filled),
  }
}

fn percent(part: usize, whole: usize) -> String {
  if whole == 0 {
    return "0%".to_string();
  }
  format!("{}%", (part as f64 / whole as f64 * 100.0).round() as i64)
}

fn numeric_rollup(aggregation: RollupAggregation, values: &[&String]) -> String {
  let mut numbers: Vec<f64> = values.iter().filter_map(|v| parse_number(v)).collect();
  if numbers.is_empty() {
    return String::new();
  }
  numbers.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

  let result = match aggregation {
    RollupAggregation::Sum => numbers.iter().sum::<f64>(),
    RollupAggregation::Average => numbers.iter().sum::<f64>() / numbers.len() as f64,
    RollupAggregation::Median => {
      let middle = numbers.len() / 2;
      if numbers.len() % 2 == 0 {
        (numbers[middle - 1] + numbers[middle]) / 2.0
      } else {
        numbers[middle]
      }
    },
    RollupAggregation::Min => numbers[0],
    RollupAggregation::Max => numbers[numbers.len() - 1],
    RollupAggregation::Range => numbers[numbers.len() - 1] - numbers[0],
    _ => return String::new(),
  };
  trim_number(result)
}

/// Reads a number out of what a cell shows, ignoring the punctuation a
/// currency or a percentage brings with it.
fn parse_number(value: &str) -> Option<f64> {
  let cleaned: String = value
    .chars()
    .filter(|c| c.is_ascii_digit() || *c == '.' || *c == '-')
    .collect();
  if cleaned.is_empty() {
    return None;
  }
  cleaned.parse::<f64>().ok()
}

fn trim_number(value: f64) -> String {
  if (value - value.round()).abs() < f64::EPSILON {
    format!("{}", value.round() as i64)
  } else {
    let text = format!("{:.4}", value);
    text.trim_end_matches('0').trim_end_matches('.').to_string()
  }
}

/// What one linked row contributes to a rollup.
pub fn cell_value(row: &Row, field: &Field) -> String {
  row
    .cells
    .get(&field.id)
    .map(|cell| stringify_cell(cell, field))
    .unwrap_or_default()
}

/// Whether a field is one a rollup can be pointed at.
pub fn is_rollup_target(field: &Field) -> bool {
  !matches!(FieldType::from(field.field_type), FieldType::Relation)
}

#[cfg(test)]
mod tests {
  use super::*;

  fn values(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| s.to_string()).collect()
  }

  #[test]
  fn shows_the_values_as_they_are() {
    let v = values(&["Ada", "Grace"]);
    assert_eq!(
      apply_rollup(RollupAggregation::ShowOriginal, &v, 2),
      "Ada, Grace"
    );
  }

  #[test]
  fn counts_linked_rows_and_the_values_on_them() {
    let v = values(&["3", "", "5"]);
    assert_eq!(apply_rollup(RollupAggregation::Count, &v, 3), "3");
    assert_eq!(apply_rollup(RollupAggregation::CountValues, &v, 3), "2");
    assert_eq!(apply_rollup(RollupAggregation::CountEmpty, &v, 3), "1");
  }

  #[test]
  fn counts_only_the_distinct_values() {
    let v = values(&["red", "blue", "red"]);
    assert_eq!(apply_rollup(RollupAggregation::CountUnique, &v, 3), "2");
  }

  #[test]
  fn reports_how_much_is_filled_in() {
    let v = values(&["3", "", "", ""]);
    assert_eq!(apply_rollup(RollupAggregation::PercentNotEmpty, &v, 4), "25%");
    assert_eq!(apply_rollup(RollupAggregation::PercentEmpty, &v, 4), "75%");
  }

  #[test]
  fn adds_up_numbers_however_they_are_written() {
    let v = values(&["$1200", "300", "1.5"]);
    assert_eq!(apply_rollup(RollupAggregation::Sum, &v, 3), "1501.5");
    assert_eq!(apply_rollup(RollupAggregation::Min, &v, 3), "1.5");
    assert_eq!(apply_rollup(RollupAggregation::Max, &v, 3), "1200");
  }

  #[test]
  fn finds_the_middle_and_the_spread() {
    let v = values(&["1", "2", "3", "4"]);
    assert_eq!(apply_rollup(RollupAggregation::Median, &v, 4), "2.5");
    assert_eq!(apply_rollup(RollupAggregation::Average, &v, 4), "2.5");
    assert_eq!(apply_rollup(RollupAggregation::Range, &v, 4), "3");
  }

  #[test]
  fn picks_the_first_and_last_date() {
    let v = values(&["2026-03-14", "2024-01-02", "2025-06-30"]);
    assert_eq!(
      apply_rollup(RollupAggregation::Earliest, &v, 3),
      "2024-01-02"
    );
    assert_eq!(apply_rollup(RollupAggregation::Latest, &v, 3), "2026-03-14");
  }

  #[test]
  fn says_nothing_when_there_is_nothing_to_say() {
    let v: Vec<String> = vec![];
    assert_eq!(apply_rollup(RollupAggregation::Sum, &v, 0), "");
    assert_eq!(apply_rollup(RollupAggregation::Count, &v, 0), "0");
    assert_eq!(apply_rollup(RollupAggregation::PercentEmpty, &v, 0), "0%");
  }

  #[test]
  fn settings_survive_being_stored_and_read_back() {
    let option = RollupTypeOption {
      relation_field_id: "f1".to_string(),
      target_field_id: "f2".to_string(),
      aggregation: RollupAggregation::Median,
    };
    let restored = RollupTypeOption::from(TypeOptionData::from(option.clone()));

    assert_eq!(restored.relation_field_id, option.relation_field_id);
    assert_eq!(restored.target_field_id, option.target_field_id);
    assert_eq!(restored.aggregation, RollupAggregation::Median);
    assert!(restored.is_configured());
  }

  #[test]
  fn an_unconfigured_rollup_is_not_taken_for_one() {
    let option = RollupTypeOption::default();
    assert!(!option.is_configured());
  }
}
