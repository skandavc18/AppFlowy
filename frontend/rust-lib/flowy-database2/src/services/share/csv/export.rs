use collab_database::database::Database;
use collab_database::fields::Field;
use collab_database::rows::Cell;
use collab_database::template::timestamp_parse::TimestampCellData;
use futures::StreamExt;
use indexmap::IndexMap;
use std::collections::HashMap;

use flowy_error::{FlowyError, FlowyResult};

use crate::entities::FieldType;
use crate::services::cell::stringify_cell;

/// What each linked row is called, keyed by the id a relation cell stores.
///
/// A relation cell holds ids, which say nothing to a reader; the names have to
/// be fetched from the database being pointed at, so they are gathered once
/// and handed to the export.
pub type RelationNames = HashMap<String, String>;

#[derive(Debug, Clone, Copy)]
pub enum CSVFormat {
  /// The export data will be pure data, without any meta data.
  /// Will lost the field type information.
  Original,
  /// The export data contains meta data, such as field type.
  /// It can be used to fully restore the database.
  META,
}

pub struct CSVExport;
impl CSVExport {
  pub async fn export_database(
    &self,
    database: &Database,
    style: CSVFormat,
    relation_names: &RelationNames,
  ) -> FlowyResult<String> {
    let mut wtr = csv::Writer::from_writer(vec![]);
    let view_id = database
      .get_first_database_view_id()
      .ok_or_else(|| FlowyError::internal().with_context("failed to get first database view"))?;
    let fields = database.get_fields_in_view(&view_id, None);

    // Write fields
    let field_records = fields
      .iter()
      .map(|field| match &style {
        CSVFormat::Original => field.name.clone(),
        CSVFormat::META => serde_json::to_string(&field).unwrap(),
      })
      .collect::<Vec<String>>();
    wtr
      .write_record(&field_records)
      .map_err(|e| FlowyError::internal().with_context(e))?;

    // Write rows
    let mut field_by_field_id = IndexMap::new();
    fields.into_iter().for_each(|field| {
      field_by_field_id.insert(field.id.clone(), field);
    });
    let rows = database
      .get_rows_for_view(&view_id, 20, None)
      .await
      .filter_map(|result| async { result.ok() })
      .collect::<Vec<_>>()
      .await;

    let stringify = |cell: &Cell, field: &Field, style: CSVFormat| match style {
      CSVFormat::Original => {
        let value = stringify_cell(cell, field);
        if FieldType::from(field.field_type) == FieldType::Relation {
          resolve_relation(&value, relation_names)
        } else {
          value
        }
      },
      // The meta format is used to restore a database, so it keeps the ids.
      CSVFormat::META => serde_json::to_string(cell).unwrap_or_else(|_| "".to_string()),
    };

    for row in rows {
      let cells = field_by_field_id
        .iter()
        .map(|(field_id, field)| {
          let field_type = FieldType::from(field.field_type);
          match field_type {
            FieldType::LastEditedTime | FieldType::CreatedTime => {
              let cell_data = if field_type.is_created_time() {
                TimestampCellData::new(row.created_at)
              } else {
                TimestampCellData::new(row.modified_at)
              };
              let cell = cell_data.to_cell(field.field_type);
              stringify(&cell, field, style)
            },
            _ => match row.cells.get(field_id) {
              None => "".to_string(),
              Some(cell) => stringify(cell, field, style),
            },
          }
        })
        .collect::<Vec<_>>();

      if let Err(e) = wtr.write_record(&cells) {
        tracing::warn!("CSV failed to write record: {}", e);
      }
    }

    let data = wtr
      .into_inner()
      .map_err(|e| FlowyError::internal().with_context(e))?;
    let csv = String::from_utf8(data).map_err(|e| FlowyError::internal().with_context(e))?;
    Ok(csv)
  }
}

/// Turns the ids a relation cell holds into the names those rows go by.
///
/// An id with no name behind it is left as it is rather than dropped, so a
/// link to a row that has since gone is still visible.
pub fn resolve_relation(value: &str, names: &RelationNames) -> String {
  if value.is_empty() {
    return String::new();
  }
  value
    .split(',')
    .map(|id| id.trim())
    .filter(|id| !id.is_empty())
    .map(|id| names.get(id).cloned().unwrap_or_else(|| id.to_string()))
    .collect::<Vec<_>>()
    .join(", ")
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn resolves_every_linked_row() {
    let mut names = RelationNames::new();
    names.insert("r1".to_string(), "Ada".to_string());
    names.insert("r2".to_string(), "Grace".to_string());

    assert_eq!(resolve_relation("r1, r2", &names), "Ada, Grace");
    assert_eq!(resolve_relation("r2", &names), "Grace");
  }

  #[test]
  fn keeps_an_id_whose_row_has_gone() {
    let names = RelationNames::new();
    assert_eq!(resolve_relation("r1", &names), "r1");
  }

  #[test]
  fn leaves_an_unlinked_cell_empty() {
    let names = RelationNames::new();
    assert_eq!(resolve_relation("", &names), "");
    assert_eq!(resolve_relation(" , ", &names), "");
  }
}
