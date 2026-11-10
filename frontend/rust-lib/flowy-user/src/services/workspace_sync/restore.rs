//! Putting a whole workspace back, from a snapshot bundle.
//!
//! A workspace cannot be replaced while it is open — its collabs live in
//! memory and in a database the application holds. So a restore is scheduled:
//! the snapshot is set aside in the storage folder with a note beside it, the
//! application restarts in place, and the note is acted on while the new
//! instance starts, after the old one has let go of the database and before the
//! new one has opened it.
//!
//! The same path serves a computer joining a sync folder. The snapshot names
//! the user and workspace it belongs to; when that is not who is signed in
//! here, the workspace is written for its own user and the session moves to
//! it, which leaves the workspace that was here untouched in its own folder.

use std::path::{Path, PathBuf};

use chrono::{TimeZone, Utc};
use collab::core::collab::make_yrs_doc;
use collab::preclude::updates::decoder::Decode;
use collab::preclude::{ReadTxn, Transact, Update};
use collab_integrate::{CollabKVAction, CollabKVDB};
use collab_plugins::local_storage::kv::KVTransactionDB;
use diesel::{insert_into, ExpressionMethods, QueryDsl, RunQueryDsl};
use flowy_error::{FlowyError, FlowyResult};
use flowy_sqlite::kv::KVStorePreferences;
use flowy_sqlite::schema::user_data_migration_records;
use flowy_sqlite::SqliteConnection;
use flowy_user_pub::entities::{AuthType, Role, UserProfile, UserWorkspace, WorkspaceType};
use flowy_user_pub::session::Session;
use flowy_user_pub::sql::{
  select_user_auth_type, upsert_user, upsert_user_workspace, upsert_workspace_member,
  WorkspaceMemberTable,
};
use serde::{Deserialize, Serialize};
use tracing::{error, info};
use uuid::Uuid;

use super::bundle::{BundleEntry, BundleHeader, BundleKind, BundleReader};
use super::exchange::{bundle_error, persistence_error};
use super::state::{with_suffix, SyncState};
use super::store::{fingerprint, object_ids, open_collab_db};
use crate::services::db::UserDBPath;
use crate::services::entities::{UserConfig, UserPaths};

pub const PENDING_RESTORE_FILE: &str = "pending_workspace_restore.json";
pub const PENDING_RESTORE_SNAPSHOT: &str = "pending_workspace_restore.snapshot";
pub const RESTORE_OUTCOME_FILE: &str = "last_workspace_restore.json";

/// Collabs are written in batches this large, so a big workspace does not sit
/// in one transaction.
const WRITE_BATCH: usize = 128;

#[derive(Serialize, Deserialize, Debug, Clone)]
struct PendingRestore {
  snapshot: String,
  #[serde(default)]
  sync_state_path: String,
  requested_at: i64,
}

/// How the last restore went, kept until the application asks.
#[derive(Serialize, Deserialize, Debug, Clone, Default)]
pub struct RestoreOutcome {
  pub succeeded: bool,
  pub uid: i64,
  pub workspace_id: String,
  pub workspace_name: String,
  pub objects: u32,
  pub detail: String,
  pub at: i64,
}

/// Sets [snapshot] aside to replace its workspace the next time AppFlowy
/// starts.
///
/// The whole bundle is read first: a snapshot that turns out to be damaged
/// must be refused now, while the workspace it would replace is still intact.
pub fn schedule_restore(
  storage_root: &Path,
  snapshot: &Path,
  sync_state_path: &str,
) -> FlowyResult<(BundleHeader, u32)> {
  let (header, objects) = BundleReader::verify(snapshot).map_err(bundle_error)?;
  if header.kind != BundleKind::Snapshot {
    return Err(
      FlowyError::invalid_data().with_context("only a snapshot can replace a workspace"),
    );
  }
  if header.workspace_id.is_empty() || header.database_storage_id.is_empty() {
    return Err(FlowyError::invalid_data().with_context("the snapshot does not name its workspace"));
  }

  std::fs::create_dir_all(storage_root)?;
  let kept = storage_root.join(PENDING_RESTORE_SNAPSHOT);
  let staging = with_suffix(&kept, ".tmp");
  std::fs::copy(snapshot, &staging)?;
  std::fs::rename(&staging, &kept)?;

  let pending = PendingRestore {
    snapshot: kept.to_string_lossy().to_string(),
    sync_state_path: sync_state_path.to_string(),
    requested_at: Utc::now().timestamp_millis(),
  };
  let marker = storage_root.join(PENDING_RESTORE_FILE);
  let staging = with_suffix(&marker, ".tmp");
  std::fs::write(
    &staging,
    serde_json::to_vec(&pending).map_err(|err| FlowyError::internal().with_context(err))?,
  )?;
  std::fs::rename(&staging, &marker)?;
  info!(
    "[Workspace sync] scheduled a restore of {} ({} objects)",
    header.workspace_id, objects
  );
  Ok((header, objects))
}

/// Whether a restore is waiting for the next start.
pub fn has_pending_restore(storage_root: &Path) -> bool {
  storage_root.join(PENDING_RESTORE_FILE).exists()
}

/// Acts on a scheduled restore, if there is one.
///
/// Called while AppFlowy starts, before anything has opened the user's
/// databases. Never fails the start: whatever happens is recorded for
/// [take_restore_outcome], and a restore that could not be applied leaves the
/// workspace it would have replaced as it was.
pub fn apply_pending_restore(
  storage_root: &Path,
  user_config: &UserConfig,
  store_preferences: &KVStorePreferences,
) {
  let marker = storage_root.join(PENDING_RESTORE_FILE);
  if !marker.exists() {
    return;
  }
  let outcome = match apply(storage_root, &marker, user_config, store_preferences) {
    Ok(outcome) => {
      let _ = std::fs::remove_file(&marker);
      let _ = std::fs::remove_file(storage_root.join(PENDING_RESTORE_SNAPSHOT));
      outcome
    },
    Err(err) => {
      error!("[Workspace sync] the restore could not be applied: {}", err);
      // Set aside rather than retried forever: a restore that fails the same
      // way at every start would keep the application from ever starting
      // cleanly. The snapshot stays where it was for another attempt.
      let _ = std::fs::rename(&marker, with_suffix(&marker, ".failed"));
      RestoreOutcome {
        succeeded: false,
        detail: err.msg.clone(),
        at: Utc::now().timestamp_millis(),
        ..Default::default()
      }
    },
  };
  if let Ok(bytes) = serde_json::to_vec(&outcome) {
    let _ = std::fs::write(storage_root.join(RESTORE_OUTCOME_FILE), bytes);
  }
}

/// The outcome of the last restore, once; None when nothing was restored since
/// the last time this was asked.
pub fn take_restore_outcome(storage_root: &Path) -> Option<RestoreOutcome> {
  let path = storage_root.join(RESTORE_OUTCOME_FILE);
  let bytes = std::fs::read(&path).ok()?;
  let _ = std::fs::remove_file(&path);
  serde_json::from_slice(&bytes).ok()
}

fn apply(
  storage_root: &Path,
  marker: &Path,
  user_config: &UserConfig,
  store_preferences: &KVStorePreferences,
) -> FlowyResult<RestoreOutcome> {
  let pending: PendingRestore = serde_json::from_slice(&std::fs::read(marker)?)
    .map_err(|err| FlowyError::invalid_data().with_context(err))?;
  let snapshot = PathBuf::from(&pending.snapshot);
  let mut reader = BundleReader::open(&snapshot).map_err(bundle_error)?;
  let header = reader.header().clone();
  let uid = header.uid;
  let workspace_id = header.workspace_id.clone();

  let paths = UserPaths::new(storage_root.to_string_lossy().to_string());
  let database = flowy_sqlite::init(paths.sqlite_db_path(uid))?;
  restore_records(&header, &database)?;

  let db = open_collab_db(&paths.collab_db_path(uid)).map_err(persistence_error)?;
  let existing = object_ids(&db.read_txn(), uid, &workspace_id).map_err(persistence_error)?;
  db.with_write_txn(|txn| {
    for object_id in &existing {
      txn.delete_doc(uid, &workspace_id, object_id)?;
    }
    Ok(())
  })
  .map_err(persistence_error)?;

  let mut state = SyncState::new(&workspace_id);
  let track = !pending.sync_state_path.is_empty();
  let mut batch = Vec::with_capacity(WRITE_BATCH);
  let mut objects = 0u32;
  while let Some(entry) = reader.next_entry().map_err(bundle_error)? {
    batch.push(entry);
    if batch.len() >= WRITE_BATCH {
      objects += write_batch(&db, uid, &workspace_id, &mut batch, track.then_some(&mut state))?;
    }
  }
  objects += write_batch(&db, uid, &workspace_id, &mut batch, track.then_some(&mut state))?;

  if track {
    let txn = db.read_txn();
    for (object_id, object) in state.objects.iter_mut() {
      object.fingerprint = fingerprint(&txn, uid, &workspace_id, object_id).unwrap_or_default();
    }
    drop(txn);
    state.save(Path::new(&pending.sync_state_path))?;
  }
  let _ = db.flush();
  drop(db);
  drop(database);

  let user_uuid = Uuid::parse_str(&header.user_uuid).unwrap_or_else(|_| {
    store_preferences
      .get_object::<Session>(&user_config.session_cache_key)
      .filter(|session| session.user_id == uid)
      .map(|session| session.user_uuid)
      .unwrap_or_else(Uuid::new_v4)
  });
  store_preferences
    .set_object(
      &user_config.session_cache_key,
      &Session {
        user_id: uid,
        user_uuid,
        workspace_id: workspace_id.clone(),
      },
    )
    .map_err(|err| FlowyError::internal().with_context(err))?;

  info!(
    "[Workspace sync] restored {} objects into workspace {}",
    objects, workspace_id
  );
  Ok(RestoreOutcome {
    succeeded: true,
    uid,
    workspace_id,
    workspace_name: header.workspace_name,
    objects,
    detail: String::new(),
    at: Utc::now().timestamp_millis(),
  })
}

fn write_batch(
  db: &CollabKVDB,
  uid: i64,
  workspace_id: &str,
  batch: &mut Vec<BundleEntry>,
  mut state: Option<&mut SyncState>,
) -> FlowyResult<u32> {
  if batch.is_empty() {
    return Ok(0);
  }
  db.with_write_txn(|txn| {
    for entry in batch.iter() {
      txn.flush_doc(
        uid,
        workspace_id,
        &entry.object_id,
        entry.state_vector.clone(),
        entry.doc_state.clone(),
      )?;
    }
    Ok(())
  })
  .map_err(persistence_error)?;

  if let Some(state) = state.as_mut() {
    for entry in batch.iter() {
      let doc = make_yrs_doc(true);
      if let Ok(update) = Update::decode_v1(&entry.doc_state) {
        if doc.transact_mut().apply_update(update).is_ok() {
          state
            .objects
            .entry(entry.object_id.clone())
            .or_default()
            .set_synced(&doc.transact().snapshot());
        }
      }
    }
  }
  let written = batch.len() as u32;
  batch.clear();
  Ok(written)
}

/// Makes sure the user, the workspace and its membership are on record, and
/// that the migrations the workspace has already been through are not run on
/// it again.
fn restore_records(header: &BundleHeader, database: &flowy_sqlite::Database) -> FlowyResult<()> {
  let uid = header.uid;
  let connect = || {
    database
      .get_connection()
      .map_err(|err| FlowyError::internal().with_context(format!("{:?}", err)))
  };
  let mut conn = connect()?;

  // A user already on record is kept as it is: it may carry a sign-in.
  if select_user_auth_type(uid, &mut conn).is_err() {
    let profile = UserProfile {
      uid,
      email: header.user_email.clone(),
      name: header.user_name.clone(),
      token: String::new(),
      icon_url: header.user_icon_url.clone(),
      auth_type: AuthType::Local,
      workspace_type: WorkspaceType::Local,
      updated_at: Utc::now().timestamp(),
    };
    upsert_user((profile, AuthType::Local).into(), connect()?)?;
  }

  let created_at = Utc
    .timestamp_opt(header.workspace_created_at, 0)
    .single()
    .unwrap_or_else(Utc::now);
  let workspace = UserWorkspace {
    id: header.workspace_id.clone(),
    name: header.workspace_name.clone(),
    created_at,
    workspace_database_id: header.database_storage_id.clone(),
    icon: header.workspace_icon.clone(),
    cover: String::new(),
    member_count: 1,
    role: Some(Role::Owner),
    workspace_type: WorkspaceType::Local,
  };
  upsert_user_workspace(uid, WorkspaceType::Local, workspace, &mut conn)?;
  upsert_workspace_member(
    &mut conn,
    WorkspaceMemberTable {
      email: header.user_email.clone(),
      role: Role::Owner as i32,
      name: header.user_name.clone(),
      avatar_url: Some(header.user_icon_url.clone()),
      uid,
      workspace_id: header.workspace_id.clone(),
      updated_at: Utc::now().naive_utc(),
      joined_at: None,
    },
  )?;

  record_migrations(&mut conn, &header.migrations)?;
  Ok(())
}

fn record_migrations(conn: &mut SqliteConnection, names: &[String]) -> FlowyResult<()> {
  let known: Vec<String> = user_data_migration_records::table
    .select(user_data_migration_records::migration_name)
    .load(conn)
    .unwrap_or_default();
  for name in names {
    if !known.contains(name) {
      insert_into(user_data_migration_records::table)
        .values(user_data_migration_records::migration_name.eq(name))
        .execute(conn)?;
    }
  }
  Ok(())
}
