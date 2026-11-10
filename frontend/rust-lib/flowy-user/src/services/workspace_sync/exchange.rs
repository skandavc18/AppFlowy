//! Sending a workspace's changes, and taking in another computer's.
//!
//! Collabs are CRDTs, so taking in another computer's state is never a choice
//! between two versions: the update is merged, whatever the order things
//! arrive in and however often the same update arrives. What has to be decided
//! here is only where to apply it — to the copy that is open, so the editor
//! shows it at once, or to the copy on disk — and what this computer still owes
//! the others afterwards.

use std::collections::HashSet;
use std::path::Path;

use collab::core::collab::make_yrs_doc;
use collab::preclude::updates::decoder::Decode;
use collab::preclude::updates::encoder::Encode;
use collab::preclude::{ReadTxn, Snapshot, StateVector, Transact, Update};
use collab_integrate::live_collab::SnapshotMoment;
use collab_integrate::{CollabKVAction, PersistenceError};
use collab_plugins::local_storage::kv::KVTransactionDB;
use flowy_error::{FlowyError, FlowyResult};
use tracing::{info, warn};

use super::bundle::{BundleEntry, BundleError, BundleHeader, BundleKind, BundleReader, BundleWriter};
use super::state::{covers, pending_state_path, SyncState};
use super::store::{fingerprint, load_doc, object_ids, WorkspaceStore};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ExportSummary {
  pub objects: u32,
  /// Whether a bundle was written at all. A changes export that found nothing
  /// new writes none.
  pub wrote: bool,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ImportSummary {
  pub objects: u32,
  /// Applied to a copy that was open.
  pub live: u32,
  /// New to this computer.
  pub created: u32,
  /// Merged into the copy on disk.
  pub merged: u32,
  /// Already known here.
  pub unchanged: u32,
}

pub(crate) fn bundle_error(err: BundleError) -> FlowyError {
  match err {
    BundleError::Io(err) => FlowyError::internal().with_context(err.to_string()),
    other => FlowyError::invalid_data().with_context(other.to_string()),
  }
}

pub(crate) fn persistence_error(err: PersistenceError) -> FlowyError {
  FlowyError::internal().with_context(err.to_string())
}

/// The full state of one collab, as a bundle carries it.
fn entry_from_doc(object_id: &str, txn: &impl ReadTxn) -> BundleEntry {
  BundleEntry {
    object_id: object_id.to_string(),
    state_vector: txn.state_vector().encode_v1(),
    doc_state: txn.encode_state_as_update_v1(&StateVector::default()),
  }
}

/// Writes every collab of the workspace to [path].
///
/// With [state_path], the sync state is reset to say that all of it has been
/// shared — which is true of the snapshot a sync folder is started from.
pub fn export_snapshot(
  store: &WorkspaceStore,
  header: &BundleHeader,
  path: &Path,
  state_path: Option<&Path>,
) -> FlowyResult<ExportSummary> {
  let mut header = header.clone();
  header.kind = BundleKind::Snapshot;

  let txn = store.db.read_txn();
  let ids = object_ids(&txn, store.uid, &store.workspace_id).map_err(persistence_error)?;
  let mut writer = BundleWriter::create(path, &header).map_err(bundle_error)?;
  let mut state = SyncState::new(&store.workspace_id);

  for object_id in ids {
    let print = fingerprint(&txn, store.uid, &store.workspace_id, &object_id);
    let doc = match load_doc(&txn, store.uid, &store.workspace_id, &object_id) {
      Ok(doc) => doc,
      Err(err) => {
        warn!(
          "[Workspace sync] {} could not be read and is left out: {}",
          object_id, err
        );
        continue;
      },
    };
    let read = doc.transact();
    writer
      .write_entry(&entry_from_doc(&object_id, &read))
      .map_err(bundle_error)?;
    if state_path.is_some() {
      let object = state.objects.entry(object_id).or_default();
      object.fingerprint = print.unwrap_or_default();
      object.set_synced(&read.snapshot());
    }
  }
  drop(txn);

  let objects = writer.finish().map_err(bundle_error)?;
  if let Some(state_path) = state_path {
    state.save(state_path)?;
    let _ = std::fs::remove_file(pending_state_path(state_path));
  }
  info!(
    "[Workspace sync] exported a snapshot of {} objects",
    objects
  );
  Ok(ExportSummary {
    objects,
    wrote: true,
  })
}

/// Writes every collab with something the sync folder has not seen yet.
///
/// The state that reflects this export is left beside [state_path] with a
/// `.next` suffix, and only becomes the state once the caller moves it over —
/// which it does after the bundle has actually reached the sync folder. An
/// export whose bundle never arrived therefore changes nothing, and the same
/// objects are simply sent again next time.
pub fn export_changes(
  store: &WorkspaceStore,
  header: &BundleHeader,
  path: &Path,
  state_path: &Path,
) -> FlowyResult<ExportSummary> {
  let mut header = header.clone();
  header.kind = BundleKind::Changes;
  let pending = pending_state_path(state_path);
  let _ = std::fs::remove_file(&pending);

  let mut state = SyncState::load(state_path, &store.workspace_id);
  let txn = store.db.read_txn();
  let ids = object_ids(&txn, store.uid, &store.workspace_id).map_err(persistence_error)?;
  let mut present = HashSet::with_capacity(ids.len());
  let mut writer: Option<BundleWriter> = None;
  let mut touched = false;

  for object_id in ids {
    present.insert(object_id.clone());
    // The fingerprint is read before the document, never after: a change
    // landing in between is then sent now and noticed again later, rather than
    // recorded as sent without having been.
    let Some(print) = fingerprint(&txn, store.uid, &store.workspace_id, &object_id) else {
      continue;
    };
    let object = state.objects.entry(object_id.clone()).or_default();
    if object.fingerprint == print {
      continue;
    }
    touched = true;
    let doc = match load_doc(&txn, store.uid, &store.workspace_id, &object_id) {
      Ok(doc) => doc,
      Err(err) => {
        warn!(
          "[Workspace sync] {} could not be read and is not sent: {}",
          object_id, err
        );
        continue;
      },
    };
    let read = doc.transact();
    let local = read.snapshot();
    if !covers(&object.synced_snapshot(), &local) {
      if writer.is_none() {
        writer = Some(BundleWriter::create(path, &header).map_err(bundle_error)?);
      }
      writer
        .as_mut()
        .expect("created above")
        .write_entry(&entry_from_doc(&object_id, &read))
        .map_err(bundle_error)?;
      object.set_synced(&local);
    }
    object.fingerprint = print;
  }
  drop(txn);

  let before = state.objects.len();
  state.objects.retain(|object_id, _| present.contains(object_id));
  touched |= state.objects.len() != before;

  match writer {
    Some(writer) => {
      let objects = writer.finish().map_err(bundle_error)?;
      state.save(&pending)?;
      Ok(ExportSummary {
        objects,
        wrote: true,
      })
    },
    None => {
      if touched {
        state.save(state_path)?;
      }
      Ok(ExportSummary::default())
    },
  }
}

/// Merges every collab in the bundle at [path] into this workspace.
pub fn import_bundle(
  store: &WorkspaceStore,
  path: &Path,
  state_path: Option<&Path>,
) -> FlowyResult<ImportSummary> {
  let mut reader = BundleReader::open(path).map_err(bundle_error)?;
  if reader.header().workspace_id != store.workspace_id {
    return Err(FlowyError::invalid_data().with_context(format!(
      "the bundle belongs to workspace {}, not {}",
      reader.header().workspace_id,
      store.workspace_id
    )));
  }

  let mut state = state_path.map(|path| SyncState::load(path, &store.workspace_id));
  let mut summary = ImportSummary::default();
  while let Some(entry) = reader.next_entry().map_err(bundle_error)? {
    let synced = state
      .as_ref()
      .and_then(|state| state.objects.get(&entry.object_id))
      .map(|object| object.synced_snapshot())
      .unwrap_or_default();
    let merged = match merge_entry(store, &entry, &synced) {
      Ok(merged) => merged,
      Err(err) => {
        warn!(
          "[Workspace sync] {} could not be merged: {}",
          entry.object_id, err
        );
        continue;
      },
    };
    summary.objects += 1;
    match merged.how {
      Merged::Live => summary.live += 1,
      Merged::Created => summary.created += 1,
      Merged::OnDisk => summary.merged += 1,
      Merged::Unchanged => summary.unchanged += 1,
    }
    if let (Some(state), Some(after)) = (state.as_mut(), merged.shared) {
      state
        .objects
        .entry(entry.object_id.clone())
        .or_default()
        .set_synced(&after);
    }
  }

  if let (Some(state), Some(state_path)) = (state, state_path) {
    state.save(state_path)?;
  }
  Ok(summary)
}

enum Merged {
  Live,
  Created,
  OnDisk,
  Unchanged,
}

struct MergeResult {
  how: Merged,
  /// What the sync folder now holds of this object, when this computer had
  /// nothing of its own still waiting to be sent. None means there is, and the
  /// object will go out with the next export anyway.
  shared: Option<Snapshot>,
}

fn merge_entry(
  store: &WorkspaceStore,
  entry: &BundleEntry,
  synced: &Snapshot,
) -> FlowyResult<MergeResult> {
  let live_docs = store
    .live
    .as_ref()
    .map(|live| live.live_docs(&store.workspace_id, &entry.object_id))
    .unwrap_or_default();

  if live_docs.is_empty() {
    return merge_on_disk(store, entry, synced);
  }

  let mut clean: Option<bool> = None;
  let mut after: Option<Snapshot> = None;
  for live in &live_docs {
    let update = Update::decode_v1(&entry.doc_state)
      .map_err(|err| FlowyError::invalid_data().with_context(err.to_string()))?;
    live
      .apply_remote_update(update, |moment, snapshot| match moment {
        SnapshotMoment::Before => {
          if clean.is_none() {
            clean = Some(covers(synced, snapshot));
          }
        },
        SnapshotMoment::After => after = Some(snapshot.clone()),
      })
      .map_err(|err| FlowyError::internal().with_context(err.to_string()))?;
  }
  // A collab that was loaded but never initialised does not persist what is
  // applied to it, so the copy on disk has to be told as well.
  if !live_docs.iter().any(|live| live.persists_updates()) {
    merge_on_disk(store, entry, synced)?;
  }
  Ok(MergeResult {
    how: Merged::Live,
    shared: if clean == Some(true) { after } else { None },
  })
}

fn merge_on_disk(
  store: &WorkspaceStore,
  entry: &BundleEntry,
  synced: &Snapshot,
) -> FlowyResult<MergeResult> {
  let (uid, workspace_id, object_id) = (store.uid, &store.workspace_id, &entry.object_id);
  let update = || {
    Update::decode_v1(&entry.doc_state)
      .map_err(|err| FlowyError::invalid_data().with_context(err.to_string()))
  };

  let exists = store.db.read_txn().is_exist(uid, workspace_id, object_id);
  if !exists {
    let doc = make_yrs_doc(true);
    doc
      .transact_mut()
      .apply_update(update()?)
      .map_err(|err| FlowyError::invalid_data().with_context(err.to_string()))?;
    let read = doc.transact();
    let state_vector = read.state_vector().encode_v1();
    let doc_state = read.encode_state_as_update_v1(&StateVector::default());
    let created = store
      .db
      .with_write_txn(|txn| {
        // Something here may have created it a moment ago; then the update is
        // appended rather than written over it.
        if txn.is_exist(uid, workspace_id, object_id) {
          txn.push_update(uid, workspace_id, object_id, &doc_state)?;
          Ok(false)
        } else {
          txn.flush_doc(uid, workspace_id, object_id, state_vector, doc_state)?;
          Ok(true)
        }
      })
      .map_err(persistence_error)?;
    return Ok(MergeResult {
      how: if created {
        Merged::Created
      } else {
        Merged::OnDisk
      },
      shared: if created { Some(read.snapshot()) } else { None },
    });
  }

  let doc = load_doc(&store.db.read_txn(), uid, workspace_id, object_id)
    .map_err(persistence_error)?;
  let before = doc.transact().snapshot();
  doc
    .transact_mut()
    .apply_update(update()?)
    .map_err(|err| FlowyError::invalid_data().with_context(err.to_string()))?;
  let read = doc.transact();
  let after = read.snapshot();
  let clean = covers(synced, &before);

  if covers(&before, &after) {
    return Ok(MergeResult {
      how: Merged::Unchanged,
      shared: clean.then_some(after),
    });
  }

  // Only what this computer did not have is appended. Nothing is ever written
  // over: if the collab is being opened at this very moment, whatever it
  // records next lands beside this update rather than being lost under it.
  let missing = read.encode_state_as_update_v1(&before.state_map);
  store
    .db
    .with_write_txn(|txn| {
      txn.push_update(uid, workspace_id, object_id, &missing)?;
      Ok(())
    })
    .map_err(persistence_error)?;
  Ok(MergeResult {
    how: Merged::OnDisk,
    shared: clean.then_some(after),
  })
}
