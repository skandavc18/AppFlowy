//! Reading a workspace's collabs straight from the collab database.

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use collab::core::collab::make_yrs_doc;
use collab::preclude::Doc;
use collab_integrate::live_collab::LiveCollabRegistry;
use collab_integrate::{CollabKVAction, CollabKVDB, PersistenceError};
use collab_plugins::local_storage::kv::keys::{
  make_doc_id_key_v1, make_doc_update_key, make_doc_update_key_prefix, make_state_vector_key,
  Clock, DOC_SPACE, DOC_SPACE_OBJECT, TERMINATOR,
};
use collab_plugins::local_storage::kv::{get_id_for_key, KVEntry, KVStore};
use tracing::warn;

/// One workspace's collabs, and the copies of them that are open right now.
pub struct WorkspaceStore {
  pub uid: i64,
  pub workspace_id: String,
  pub db: Arc<CollabKVDB>,
  pub live: Option<Arc<LiveCollabRegistry>>,
}

/// The ids of every collab stored for [workspace_id].
///
/// ⚠️ Not `CollabKVAction::get_all_object_ids`: that walks from this
/// workspace's first key to the end of the whole key space and slices every
/// key it meets, so it also returns objects of the workspaces stored after this
/// one. Here every key is checked to really start with this workspace's prefix.
pub fn object_ids<'a, S>(
  store: &S,
  uid: i64,
  workspace_id: &str,
) -> Result<Vec<String>, PersistenceError>
where
  S: KVStore<'a>,
  PersistenceError: From<<S as KVStore<'a>>::Error>,
{
  let mut prefix: Vec<u8> = vec![DOC_SPACE, DOC_SPACE_OBJECT];
  prefix.extend_from_slice(&uid.to_be_bytes());
  prefix.extend_from_slice(workspace_id.as_bytes());
  let mut end = prefix.clone();
  end.push(u8::MAX);

  let mut ids = vec![];
  for entry in store.range(prefix.as_slice()..end.as_slice())? {
    let key = entry.key();
    if key.len() <= prefix.len() + 1
      || !key.starts_with(&prefix)
      || key[key.len() - 1] != TERMINATOR
    {
      continue;
    }
    if let Ok(object_id) = std::str::from_utf8(&key[prefix.len()..key.len() - 1]) {
      ids.push(object_id.to_string());
    }
  }
  Ok(ids)
}

/// A cheap summary of how one collab is stored, or None when it is not.
///
/// Every change to a collab either appends an update or rewrites its state
/// vector, so hashing the last update's key with the stored state vector moves
/// whenever the collab does — without reading, let alone decoding, the
/// document itself.
pub fn fingerprint<'a, S>(store: &S, uid: i64, workspace_id: &str, object_id: &str) -> Option<u64>
where
  S: KVStore<'a>,
{
  let key = make_doc_id_key_v1(
    &uid.to_be_bytes(),
    workspace_id.as_bytes(),
    object_id.as_bytes(),
  );
  let doc_id = get_id_for_key(store, key)?;

  let mut hasher = DefaultHasher::new();
  doc_id.hash(&mut hasher);
  if let Ok(Some(state_vector)) = store.get(make_state_vector_key(doc_id).as_ref()) {
    state_vector.as_ref().hash(&mut hasher);
  }
  // The seek lands on the entry just before the highest possible update key,
  // which is only this collab's last update when it has any at all.
  let prefix = make_doc_update_key_prefix(doc_id);
  let highest = make_doc_update_key(doc_id, Clock::MAX);
  if let Ok(Some(entry)) = store.next_back_entry(highest.as_ref()) {
    if entry.key().starts_with(prefix.as_ref()) {
      entry.key().hash(&mut hasher);
    }
  }
  Some(hasher.finish())
}

/// Loads one collab from disk into a document of its own.
pub fn load_doc<'a, S>(
  store: &S,
  uid: i64,
  workspace_id: &str,
  object_id: &str,
) -> Result<Doc, PersistenceError>
where
  S: CollabKVAction<'a>,
  PersistenceError: From<<S as KVStore<'a>>::Error>,
{
  let doc = make_yrs_doc(true);
  store.load_doc(uid, workspace_id, object_id, &doc)?;
  Ok(doc)
}

/// Opens the collab database at [path], waiting a little for a previous
/// instance in this process to let go of it.
///
/// AppFlowy reopens its database when it restarts in place, and the instance
/// being replaced may still be finishing a write when the new one starts.
pub fn open_collab_db(path: &Path) -> Result<CollabKVDB, PersistenceError> {
  let mut attempt = 0;
  loop {
    match CollabKVDB::open(path) {
      Ok(db) => return Ok(db),
      Err(err) if attempt < 20 && is_lock_error(&err) => {
        attempt += 1;
        warn!(
          "[Workspace sync] the collab database is still held, retrying: {}",
          err
        );
        std::thread::sleep(Duration::from_millis(250));
      },
      Err(err) => return Err(err),
    }
  }
}

fn is_lock_error(err: &PersistenceError) -> bool {
  let text = err.to_string().to_lowercase();
  text.contains("lock") || text.contains("temporarily unavailable") || text.contains("busy")
}

#[cfg(test)]
mod tests {
  use super::*;
  use collab::preclude::{GetString, Text, Transact};
  use collab_plugins::local_storage::kv::KVTransactionDB;

  fn write_doc(db: &CollabKVDB, uid: i64, workspace_id: &str, object_id: &str, text: &str) {
    let doc = make_yrs_doc(true);
    doc
      .get_or_insert_text("t")
      .insert(&mut doc.transact_mut(), 0, text);
    let txn = doc.transact();
    db.with_write_txn(|w| w.create_new_doc(uid, workspace_id, object_id, &txn))
      .unwrap();
  }

  #[test]
  fn lists_only_this_workspace() {
    let dir = tempfile::tempdir().unwrap();
    let db = CollabKVDB::open(dir.path()).unwrap();
    let a = "00000000-0000-0000-0000-00000000000a";
    let b = "00000000-0000-0000-0000-00000000000b";
    write_doc(&db, 1, a, "one", "x");
    write_doc(&db, 1, a, "two", "x");
    write_doc(&db, 1, b, "three", "x");
    write_doc(&db, 2, a, "four", "x");

    let txn = db.read_txn();
    let mut ids = object_ids(&txn, 1, a).unwrap();
    ids.sort();
    assert_eq!(ids, vec!["one".to_string(), "two".to_string()]);
    assert_eq!(object_ids(&txn, 1, b).unwrap(), vec!["three".to_string()]);
    assert_eq!(object_ids(&txn, 2, a).unwrap(), vec!["four".to_string()]);
  }

  #[test]
  fn fingerprint_moves_with_an_update_and_only_then() {
    let dir = tempfile::tempdir().unwrap();
    let db = CollabKVDB::open(dir.path()).unwrap();
    let w = "00000000-0000-0000-0000-00000000000a";
    write_doc(&db, 1, w, "one", "x");
    write_doc(&db, 1, w, "two", "x");

    let first = fingerprint(&db.read_txn(), 1, w, "one").unwrap();
    let other = fingerprint(&db.read_txn(), 1, w, "two").unwrap();
    assert_eq!(first, fingerprint(&db.read_txn(), 1, w, "one").unwrap());

    db.with_write_txn(|txn| txn.push_update(1, w, "two", &[0, 0]).map(|_| ()))
      .unwrap();
    assert_eq!(first, fingerprint(&db.read_txn(), 1, w, "one").unwrap());
    assert_ne!(other, fingerprint(&db.read_txn(), 1, w, "two").unwrap());
    assert!(fingerprint(&db.read_txn(), 1, w, "missing").is_none());

    let doc = load_doc(&db.read_txn(), 1, w, "one").unwrap();
    let text = doc.get_or_insert_text("t");
    assert_eq!(text.get_string(&doc.transact()), "x");
  }
}
