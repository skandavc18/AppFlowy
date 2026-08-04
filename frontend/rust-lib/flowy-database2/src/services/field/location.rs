use collab::util::AnyMapExt;
use collab_database::fields::{Field, TypeOptionData, TypeOptionDataBuilder};

/// The key that marks a column as holding a place.
///
/// Like a rollup, a location is not a field type of its own: it is a text
/// column wearing a note. Type options are an open map keyed by string, so the
/// note rides beside the text column's own and a build that knows nothing
/// about maps still reads the column as the words it contains.
pub const LOCATION_TYPE_OPTION_KEY: &str = "location";

/// How a place is written in the cell.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LocationFormat {
  /// Whatever was typed: an address, a town, a pasted link.
  #[default]
  Address,
  /// "51.50740, -0.12780".
  Coordinates,
}

impl LocationFormat {
  pub fn as_str(&self) -> &'static str {
    match self {
      LocationFormat::Address => "address",
      LocationFormat::Coordinates => "coordinates",
    }
  }

  pub fn from_str(value: &str) -> Self {
    match value {
      "coordinates" => LocationFormat::Coordinates,
      _ => LocationFormat::Address,
    }
  }
}

/// What a location column knows about itself.
#[derive(Debug, Clone, Default)]
pub struct LocationTypeOption {
  pub enabled: bool,
  pub format: LocationFormat,
}

impl LocationTypeOption {
  /// The location settings on a field, if it carries any.
  pub fn from_field(field: &Field) -> Option<Self> {
    let data = field.get_any_type_option(LOCATION_TYPE_OPTION_KEY)?;
    let option = LocationTypeOption::from(data);
    option.enabled.then_some(option)
  }
}

impl From<TypeOptionData> for LocationTypeOption {
  fn from(data: TypeOptionData) -> Self {
    let format: String = data.get_as("format").unwrap_or_default();
    Self {
      enabled: data.get_as::<String>("enabled").as_deref() == Some("true"),
      format: LocationFormat::from_str(&format),
    }
  }
}

impl From<LocationTypeOption> for TypeOptionData {
  fn from(data: LocationTypeOption) -> Self {
    TypeOptionDataBuilder::from([
      ("enabled".into(), data.enabled.to_string().into()),
      ("format".into(), data.format.as_str().to_string().into()),
    ])
  }
}

/// Whether this column has been told it holds a place.
pub fn is_location_field(field: &Field) -> bool {
  LocationTypeOption::from_field(field).is_some()
}

#[cfg(test)]
mod tests {
  use super::*;
  use collab_database::entity::FieldType;

  fn field_with(option: LocationTypeOption) -> Field {
    let mut field = Field::new(
      "f".to_string(),
      "Where".to_string(),
      FieldType::RichText as i64,
      false,
    );
    field
      .type_options
      .insert(LOCATION_TYPE_OPTION_KEY.to_string(), option.into());
    field
  }

  #[test]
  fn a_marked_column_holds_a_place() {
    let field = field_with(LocationTypeOption {
      enabled: true,
      format: LocationFormat::Coordinates,
    });
    let read = LocationTypeOption::from_field(&field).unwrap();
    assert!(read.enabled);
    assert_eq!(read.format, LocationFormat::Coordinates);
    assert!(is_location_field(&field));
  }

  #[test]
  fn a_column_that_was_turned_off_is_an_ordinary_one_again() {
    let field = field_with(LocationTypeOption {
      enabled: false,
      ..Default::default()
    });
    assert!(LocationTypeOption::from_field(&field).is_none());
    assert!(!is_location_field(&field));
  }

  #[test]
  fn a_plain_column_says_nothing_about_places() {
    let field = Field::new(
      "f".to_string(),
      "Notes".to_string(),
      FieldType::RichText as i64,
      false,
    );
    assert!(!is_location_field(&field));
  }

  #[test]
  fn a_format_nobody_recognises_falls_back_to_the_words_typed() {
    assert_eq!(LocationFormat::from_str("nonsense"), LocationFormat::Address);
  }
}
