use collab_database::fields::relation_type_option::RelationTypeOption;
use collab_database::template::relation_parse::RelationCellData;
use flowy_derive::ProtoBuf;
use std::str::FromStr;

use crate::entities::CellIdPB;
use crate::services::field::{
  LocationFormat, LocationTypeOption, RollupAggregation, RollupTypeOption,
};

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RelationCellDataPB {
  #[pb(index = 1)]
  pub row_ids: Vec<String>,
}

impl From<RelationCellData> for RelationCellDataPB {
  fn from(data: RelationCellData) -> Self {
    Self {
      row_ids: data.row_ids.into_iter().map(Into::into).collect(),
    }
  }
}

impl From<RelationCellDataPB> for RelationCellData {
  fn from(data: RelationCellDataPB) -> Self {
    Self {
      row_ids: data.row_ids.into_iter().map(Into::into).collect(),
    }
  }
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RelationCellChangesetPB {
  #[pb(index = 1)]
  pub view_id: String,

  #[pb(index = 2)]
  pub cell_id: CellIdPB,

  #[pb(index = 3)]
  pub inserted_row_ids: Vec<String>,

  #[pb(index = 4)]
  pub removed_row_ids: Vec<String>,
}

#[derive(Clone, Debug, Default, ProtoBuf)]
pub struct RelationTypeOptionPB {
  #[pb(index = 1)]
  pub database_id: String,
}

impl From<RelationTypeOption> for RelationTypeOptionPB {
  fn from(value: RelationTypeOption) -> Self {
    RelationTypeOptionPB {
      database_id: value.database_id,
    }
  }
}

impl From<RelationTypeOptionPB> for RelationTypeOption {
  fn from(value: RelationTypeOptionPB) -> Self {
    RelationTypeOption {
      database_id: value.database_id,
    }
  }
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RelatedRowDataPB {
  #[pb(index = 1)]
  pub row_id: String,

  #[pb(index = 2)]
  pub name: String,
}

#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RepeatedRelatedRowDataPB {
  #[pb(index = 1)]
  pub rows: Vec<RelatedRowDataPB>,
}

#[derive(Debug, Default, Clone, ProtoBuf)]
pub struct GetRelatedRowDataPB {
  #[pb(index = 1)]
  pub database_id: String,

  #[pb(index = 2)]
  pub row_ids: Vec<String>,
}
/// How many rollup cells the last pass filled in.
#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RollupResultPB {
  #[pb(index = 1)]
  pub updated_cells: i64,
}

/// Points at one column of one view, to read its rollup settings or to ask
/// what a relation on it can reach.
#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RollupFieldPB {
  #[pb(index = 1)]
  pub view_id: String,

  #[pb(index = 2)]
  pub field_id: String,
}

/// Which relation a rollup follows, which column it reads on the far side,
/// and what it does with the values. An empty relation means the column is
/// not a rollup.
#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct RollupSettingsPB {
  #[pb(index = 1)]
  pub view_id: String,

  #[pb(index = 2)]
  pub field_id: String,

  #[pb(index = 3)]
  pub relation_field_id: String,

  #[pb(index = 4)]
  pub target_field_id: String,

  #[pb(index = 5)]
  pub aggregation: String,
}

impl From<RollupTypeOption> for RollupSettingsPB {
  fn from(option: RollupTypeOption) -> Self {
    Self {
      view_id: String::new(),
      field_id: String::new(),
      relation_field_id: option.relation_field_id,
      target_field_id: option.target_field_id,
      aggregation: option.aggregation.as_str().to_string(),
    }
  }
}

impl From<RollupSettingsPB> for RollupTypeOption {
  fn from(settings: RollupSettingsPB) -> Self {
    Self {
      relation_field_id: settings.relation_field_id,
      target_field_id: settings.target_field_id,
      aggregation: RollupAggregation::from_str(&settings.aggregation).unwrap_or_default(),
    }
  }
}

/// Turns a text column into one that holds a place, or back again.
#[derive(Debug, Clone, Default, ProtoBuf)]
pub struct LocationFieldPB {
  #[pb(index = 1)]
  pub view_id: String,

  #[pb(index = 2)]
  pub field_id: String,

  #[pb(index = 3)]
  pub enabled: bool,

  #[pb(index = 4)]
  pub format: String,
}

impl From<LocationFieldPB> for LocationTypeOption {
  fn from(settings: LocationFieldPB) -> Self {
    Self {
      enabled: settings.enabled,
      format: LocationFormat::from_str(&settings.format),
    }
  }
}