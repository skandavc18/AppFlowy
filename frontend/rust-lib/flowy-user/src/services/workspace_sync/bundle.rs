//! The file a workspace travels in between computers.
//!
//! A bundle carries the full state of some or all of a workspace's collabs,
//! together with who the workspace belongs to. A snapshot bundle carries every
//! object and is what a restore, or a computer joining a sync folder, starts
//! from; a changes bundle carries only the objects that changed since the last
//! one.
//!
//! Layout, every length little-endian:
//!
//! ```text
//! magic "AFWSYNC1"
//! u32 header length, header JSON
//! entries: u8 1, then object id, state vector and doc state, each u32-length prefixed
//! end:     u8 0, u32 number of entries
//! ```
//!
//! The end marker is what tells a complete bundle from one whose download was
//! cut short: a reader refuses a bundle that stops before it.

use std::fmt;
use std::fs::File;
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::path::Path;

use serde::{Deserialize, Serialize};

pub const BUNDLE_MAGIC: &[u8; 8] = b"AFWSYNC1";
pub const BUNDLE_FORMAT: u32 = 1;

const ENTRY_TAG: u8 = 1;
const END_TAG: u8 = 0;
const MAX_HEADER_BYTES: u32 = 1 << 20;
const MAX_OBJECT_ID_BYTES: u32 = 1 << 10;
const MAX_STATE_BYTES: u32 = 1 << 30;

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BundleKind {
  Snapshot,
  Changes,
}

/// Whose workspace a bundle belongs to, and enough about it to recreate it on
/// a computer that has never seen it.
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct BundleHeader {
  pub format: u32,
  pub kind: BundleKind,
  pub uid: i64,
  pub user_uuid: String,
  pub workspace_id: String,
  #[serde(default)]
  pub workspace_name: String,
  #[serde(default)]
  pub workspace_icon: String,
  /// Seconds since the epoch.
  #[serde(default)]
  pub workspace_created_at: i64,
  #[serde(default)]
  pub database_storage_id: String,
  #[serde(default)]
  pub user_name: String,
  #[serde(default)]
  pub user_email: String,
  #[serde(default)]
  pub user_icon_url: String,
  #[serde(default)]
  pub device_id: String,
  /// Milliseconds since the epoch.
  pub created_at: i64,
  /// The data migrations already applied to this workspace, so a computer that
  /// adopts it does not run them a second time.
  #[serde(default)]
  pub migrations: Vec<String>,
}

/// The full state of one collab.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BundleEntry {
  pub object_id: String,
  /// Yrs state vector, v1 encoded.
  pub state_vector: Vec<u8>,
  /// Yrs update holding everything in the collab, v1 encoded.
  pub doc_state: Vec<u8>,
}

#[derive(Debug)]
pub enum BundleError {
  Io(io::Error),
  NotABundle,
  UnsupportedFormat,
  Truncated,
  Damaged(String),
}

impl fmt::Display for BundleError {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      BundleError::Io(err) => write!(f, "{}", err),
      BundleError::NotABundle => write!(f, "not a workspace bundle"),
      BundleError::UnsupportedFormat => write!(
        f,
        "the workspace bundle was written by a newer version of AppFlowy"
      ),
      BundleError::Truncated => write!(f, "the workspace bundle is incomplete"),
      BundleError::Damaged(detail) => write!(f, "the workspace bundle is damaged: {}", detail),
    }
  }
}

impl std::error::Error for BundleError {}

impl From<io::Error> for BundleError {
  fn from(err: io::Error) -> Self {
    BundleError::Io(err)
  }
}

pub struct BundleWriter {
  out: BufWriter<File>,
  count: u32,
}

impl BundleWriter {
  pub fn create(path: &Path, header: &BundleHeader) -> Result<Self, BundleError> {
    if let Some(parent) = path.parent() {
      std::fs::create_dir_all(parent)?;
    }
    let mut out = BufWriter::new(File::create(path)?);
    let header = serde_json::to_vec(header).map_err(|err| BundleError::Damaged(err.to_string()))?;
    out.write_all(BUNDLE_MAGIC)?;
    out.write_all(&(header.len() as u32).to_le_bytes())?;
    out.write_all(&header)?;
    Ok(Self { out, count: 0 })
  }

  pub fn write_entry(&mut self, entry: &BundleEntry) -> Result<(), BundleError> {
    self.out.write_all(&[ENTRY_TAG])?;
    write_block(&mut self.out, entry.object_id.as_bytes())?;
    write_block(&mut self.out, &entry.state_vector)?;
    write_block(&mut self.out, &entry.doc_state)?;
    self.count += 1;
    Ok(())
  }

  pub fn count(&self) -> u32 {
    self.count
  }

  /// Seals the bundle and makes sure it reached the disk.
  pub fn finish(mut self) -> Result<u32, BundleError> {
    self.out.write_all(&[END_TAG])?;
    self.out.write_all(&self.count.to_le_bytes())?;
    self.out.flush()?;
    self.out.get_ref().sync_all()?;
    Ok(self.count)
  }
}

fn write_block(out: &mut impl Write, bytes: &[u8]) -> io::Result<()> {
  out.write_all(&(bytes.len() as u32).to_le_bytes())?;
  out.write_all(bytes)
}

pub struct BundleReader {
  input: BufReader<File>,
  header: BundleHeader,
  read: u32,
  finished: bool,
}

impl BundleReader {
  pub fn open(path: &Path) -> Result<Self, BundleError> {
    let mut input = BufReader::new(File::open(path)?);
    let mut magic = [0u8; 8];
    read_exact(&mut input, &mut magic)?;
    if &magic != BUNDLE_MAGIC {
      return Err(BundleError::NotABundle);
    }
    let length = read_u32(&mut input)?;
    if length > MAX_HEADER_BYTES {
      return Err(BundleError::Damaged("header too large".to_string()));
    }
    let mut header = vec![0u8; length as usize];
    read_exact(&mut input, &mut header)?;
    let header: BundleHeader =
      serde_json::from_slice(&header).map_err(|err| BundleError::Damaged(err.to_string()))?;
    if header.format > BUNDLE_FORMAT {
      return Err(BundleError::UnsupportedFormat);
    }
    Ok(Self {
      input,
      header,
      read: 0,
      finished: false,
    })
  }

  pub fn header(&self) -> &BundleHeader {
    &self.header
  }

  /// The next entry, or None once the end marker has been read.
  pub fn next_entry(&mut self) -> Result<Option<BundleEntry>, BundleError> {
    if self.finished {
      return Ok(None);
    }
    let mut tag = [0u8; 1];
    read_exact(&mut self.input, &mut tag)?;
    match tag[0] {
      ENTRY_TAG => {
        let object_id = read_block(&mut self.input, MAX_OBJECT_ID_BYTES)?;
        let object_id = String::from_utf8(object_id)
          .map_err(|_| BundleError::Damaged("object id is not text".to_string()))?;
        let state_vector = read_block(&mut self.input, MAX_STATE_BYTES)?;
        let doc_state = read_block(&mut self.input, MAX_STATE_BYTES)?;
        self.read += 1;
        Ok(Some(BundleEntry {
          object_id,
          state_vector,
          doc_state,
        }))
      },
      END_TAG => {
        let count = read_u32(&mut self.input)?;
        if count != self.read {
          return Err(BundleError::Damaged(format!(
            "expected {} entries, found {}",
            count, self.read
          )));
        }
        self.finished = true;
        Ok(None)
      },
      other => Err(BundleError::Damaged(format!("unknown entry tag {}", other))),
    }
  }

  /// Reads every entry, proving the bundle is whole without keeping it in
  /// memory. Returns the header and how many entries it holds.
  pub fn verify(path: &Path) -> Result<(BundleHeader, u32), BundleError> {
    let mut reader = Self::open(path)?;
    while reader.next_entry()?.is_some() {}
    Ok((reader.header.clone(), reader.read))
  }
}

fn read_exact(input: &mut impl Read, buffer: &mut [u8]) -> Result<(), BundleError> {
  input.read_exact(buffer).map_err(|err| match err.kind() {
    io::ErrorKind::UnexpectedEof => BundleError::Truncated,
    _ => BundleError::Io(err),
  })
}

fn read_u32(input: &mut impl Read) -> Result<u32, BundleError> {
  let mut bytes = [0u8; 4];
  read_exact(input, &mut bytes)?;
  Ok(u32::from_le_bytes(bytes))
}

fn read_block(input: &mut impl Read, limit: u32) -> Result<Vec<u8>, BundleError> {
  let length = read_u32(input)?;
  if length > limit {
    return Err(BundleError::Damaged("entry too large".to_string()));
  }
  let mut bytes = vec![0u8; length as usize];
  read_exact(input, &mut bytes)?;
  Ok(bytes)
}

#[cfg(test)]
pub(crate) mod tests {
  use super::*;

  pub(crate) fn header(kind: BundleKind) -> BundleHeader {
    BundleHeader {
      format: BUNDLE_FORMAT,
      kind,
      uid: 7,
      user_uuid: "8f8a5bb0-6b2b-4f53-9b55-6d0c2d0e3f11".to_string(),
      workspace_id: "w".to_string(),
      workspace_name: "Notes".to_string(),
      workspace_icon: String::new(),
      workspace_created_at: 1,
      database_storage_id: "d".to_string(),
      user_name: "Me".to_string(),
      user_email: String::new(),
      user_icon_url: String::new(),
      device_id: "device".to_string(),
      created_at: 2,
      migrations: vec!["m1".to_string()],
    }
  }

  fn entry(id: &str) -> BundleEntry {
    BundleEntry {
      object_id: id.to_string(),
      state_vector: vec![1, 2, 3],
      doc_state: vec![4; 300],
    }
  }

  #[test]
  fn round_trips() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("a.bundle");
    let mut writer = BundleWriter::create(&path, &header(BundleKind::Snapshot)).unwrap();
    writer.write_entry(&entry("one")).unwrap();
    writer.write_entry(&entry("two")).unwrap();
    assert_eq!(writer.finish().unwrap(), 2);

    let mut reader = BundleReader::open(&path).unwrap();
    assert_eq!(reader.header().kind, BundleKind::Snapshot);
    assert_eq!(reader.header().migrations, vec!["m1".to_string()]);
    assert_eq!(reader.next_entry().unwrap(), Some(entry("one")));
    assert_eq!(reader.next_entry().unwrap(), Some(entry("two")));
    assert_eq!(reader.next_entry().unwrap(), None);
    assert_eq!(BundleReader::verify(&path).unwrap().1, 2);
  }

  #[test]
  fn refuses_a_cut_short_bundle() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("a.bundle");
    let mut writer = BundleWriter::create(&path, &header(BundleKind::Changes)).unwrap();
    writer.write_entry(&entry("one")).unwrap();
    writer.finish().unwrap();

    let bytes = std::fs::read(&path).unwrap();
    std::fs::write(&path, &bytes[..bytes.len() - 7]).unwrap();
    assert!(matches!(
      BundleReader::verify(&path),
      Err(BundleError::Truncated)
    ));
  }

  #[test]
  fn refuses_something_else() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("a.bundle");
    std::fs::write(&path, b"PK\x03\x04 not a bundle").unwrap();
    assert!(matches!(
      BundleReader::open(&path),
      Err(BundleError::NotABundle)
    ));
  }
}
