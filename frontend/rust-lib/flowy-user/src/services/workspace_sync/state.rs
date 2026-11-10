//! What this computer has already shared, object by object.
//!
//! For every collab the state records a cheap fingerprint of how it is stored,
//! and a Yrs snapshot of everything in it that is already in the sync folder.
//! An object whose fingerprint has not moved has not changed; one whose
//! snapshot is still covered by what was shared has nothing new to send, even
//! though it was touched — which is exactly the case for an object that was
//! only changed by an update that came from another computer.

use std::collections::HashMap;
use std::io;
use std::ops::Range;
use std::path::{Path, PathBuf};

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use collab::preclude::updates::decoder::Decode;
use collab::preclude::updates::encoder::Encode;
use collab::preclude::Snapshot;
use serde::{Deserialize, Serialize};
use tracing::warn;

pub const SYNC_STATE_VERSION: u32 = 1;

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct SyncState {
  #[serde(default)]
  pub version: u32,
  #[serde(default)]
  pub workspace_id: String,
  #[serde(default)]
  pub objects: HashMap<String, ObjectSyncState>,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct ObjectSyncState {
  #[serde(default)]
  pub fingerprint: u64,
  /// A Yrs snapshot — state vector and delete set — v1 encoded, in base64.
  #[serde(default)]
  pub synced: String,
}

impl ObjectSyncState {
  pub fn synced_snapshot(&self) -> Snapshot {
    if self.synced.is_empty() {
      return Snapshot::default();
    }
    STANDARD
      .decode(&self.synced)
      .ok()
      .and_then(|bytes| Snapshot::decode_v1(&bytes).ok())
      .unwrap_or_default()
  }

  pub fn set_synced(&mut self, snapshot: &Snapshot) {
    self.synced = STANDARD.encode(snapshot.encode_v1());
  }
}

impl SyncState {
  pub fn new(workspace_id: &str) -> Self {
    Self {
      version: SYNC_STATE_VERSION,
      workspace_id: workspace_id.to_string(),
      objects: HashMap::new(),
    }
  }

  /// The state kept at [path] for [workspace_id], or a fresh one when there is
  /// none, it cannot be read, or it belongs to another workspace.
  pub fn load(path: &Path, workspace_id: &str) -> Self {
    let Ok(bytes) = std::fs::read(path) else {
      return Self::new(workspace_id);
    };
    match serde_json::from_slice::<SyncState>(&bytes) {
      Ok(state) if state.workspace_id == workspace_id && state.version <= SYNC_STATE_VERSION => {
        state
      },
      Ok(_) => Self::new(workspace_id),
      Err(err) => {
        warn!("[Workspace sync] the sync state could not be read: {}", err);
        Self::new(workspace_id)
      },
    }
  }

  /// Written beside, then moved over, so an interrupted write never leaves a
  /// state that reads as "nothing has been shared".
  pub fn save(&self, path: &Path) -> io::Result<()> {
    if let Some(parent) = path.parent() {
      std::fs::create_dir_all(parent)?;
    }
    let bytes = serde_json::to_vec(self).map_err(io::Error::other)?;
    let staging = with_suffix(path, ".tmp");
    std::fs::write(&staging, bytes)?;
    std::fs::rename(&staging, path)
  }
}

/// [path] with [suffix] appended to its file name.
pub fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
  let mut name = path.file_name().unwrap_or_default().to_os_string();
  name.push(suffix);
  path.with_file_name(name)
}

/// Where an export leaves the state it will become once its bundle has
/// reached the sync folder.
pub fn pending_state_path(path: &Path) -> PathBuf {
  with_suffix(path, ".next")
}

/// Whether everything in [local] is already in [synced].
pub fn covers(synced: &Snapshot, local: &Snapshot) -> bool {
  for (client, clock) in local.state_map.iter() {
    if synced.state_map.get(client) < *clock {
      return false;
    }
  }
  for (client, deleted) in local.delete_set.iter() {
    let known = synced
      .delete_set
      .range(client)
      .map(|range| merged_ranges(range.iter().cloned().collect()))
      .unwrap_or_default();
    for range in deleted.iter() {
      if range.start < range.end && !is_within(&known, range) {
        return false;
      }
    }
  }
  true
}

fn merged_ranges(mut ranges: Vec<Range<u32>>) -> Vec<Range<u32>> {
  ranges.sort_by_key(|range| range.start);
  let mut merged: Vec<Range<u32>> = Vec::with_capacity(ranges.len());
  for range in ranges {
    if range.start >= range.end {
      continue;
    }
    match merged.last_mut() {
      Some(last) if range.start <= last.end => last.end = last.end.max(range.end),
      _ => merged.push(range),
    }
  }
  merged
}

fn is_within(merged: &[Range<u32>], range: &Range<u32>) -> bool {
  let index = merged.partition_point(|known| known.end < range.end);
  merged
    .get(index)
    .is_some_and(|known| known.start <= range.start && known.end >= range.end)
}

#[cfg(test)]
mod tests {
  use super::*;
  use collab::preclude::{Doc, GetString, ReadTxn, Text, Transact};

  fn text_doc(client: u64) -> Doc {
    Doc::with_client_id(client)
  }

  #[test]
  fn a_snapshot_covers_itself_and_its_past() {
    let doc = text_doc(1);
    let text = doc.get_or_insert_text("t");
    text.insert(&mut doc.transact_mut(), 0, "hello");
    let first = doc.transact().snapshot();
    text.insert(&mut doc.transact_mut(), 5, " world");
    let second = doc.transact().snapshot();

    assert!(covers(&second, &second));
    assert!(covers(&second, &first));
    assert!(!covers(&first, &second));
  }

  #[test]
  fn a_deletion_is_something_new() {
    let doc = text_doc(1);
    let text = doc.get_or_insert_text("t");
    text.insert(&mut doc.transact_mut(), 0, "hello world");
    let before = doc.transact().snapshot();
    text.remove_range(&mut doc.transact_mut(), 0, 6);
    let after = doc.transact().snapshot();

    assert_eq!(text.get_string(&doc.transact()), "world");
    assert!(!covers(&before, &after));
    assert!(covers(&after, &before));
  }

  #[test]
  fn merged_changes_from_elsewhere_are_covered_by_the_merge() {
    let here = text_doc(1);
    let elsewhere = text_doc(2);
    here
      .get_or_insert_text("t")
      .insert(&mut here.transact_mut(), 0, "a");
    elsewhere
      .get_or_insert_text("t")
      .insert(&mut elsewhere.transact_mut(), 0, "b");

    let update = elsewhere
      .transact()
      .encode_state_as_update_v1(&Default::default());
    let mut txn = here.transact_mut();
    txn
      .apply_update(collab::preclude::Update::decode_v1(&update).unwrap())
      .unwrap();
    drop(txn);

    let merged = here.transact().snapshot();
    let theirs = elsewhere.transact().snapshot();
    assert!(covers(&merged, &theirs));
    assert!(!covers(&theirs, &merged));
  }

  #[test]
  fn state_survives_a_round_trip_and_ignores_other_workspaces() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("state.json");
    let mut state = SyncState::new("w");
    let mut object = ObjectSyncState {
      fingerprint: u64::MAX,
      ..Default::default()
    };
    let doc = text_doc(3);
    doc
      .get_or_insert_text("t")
      .insert(&mut doc.transact_mut(), 0, "x");
    let snapshot = doc.transact().snapshot();
    object.set_synced(&snapshot);
    state.objects.insert("o".to_string(), object);
    state.save(&path).unwrap();

    let loaded = SyncState::load(&path, "w");
    assert_eq!(loaded.objects["o"].fingerprint, u64::MAX);
    assert!(covers(&loaded.objects["o"].synced_snapshot(), &snapshot));
    assert!(SyncState::load(&path, "other").objects.is_empty());
    assert_eq!(
      pending_state_path(&path).file_name().unwrap(),
      "state.json.next"
    );
  }
}
