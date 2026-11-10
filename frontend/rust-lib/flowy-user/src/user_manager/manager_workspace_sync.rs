use std::path::{Path, PathBuf};

use chrono::Utc;
use diesel::{QueryDsl, RunQueryDsl};
use flowy_error::{FlowyError, FlowyResult};
use flowy_sqlite::schema::user_data_migration_records;
use flowy_user_pub::entities::WorkspaceType;
use flowy_user_pub::sql::{select_user_profile, select_user_workspace};

use crate::services::workspace_sync::{
  export_changes, export_snapshot, import_bundle, schedule_restore, take_restore_outcome,
  BundleHeader, BundleKind, ExportSummary, ImportSummary, RestoreOutcome, WorkspaceStore,
  BUNDLE_FORMAT, WORKSPACE_SYNC_LOCK,
};
use crate::user_manager::UserManager;

/// Who the current workspace belongs to, as a bundle records it.
pub struct WorkspaceSyncSource {
  pub header: BundleHeader,
  pub store: WorkspaceStore,
  pub workspace_type: WorkspaceType,
}

impl UserManager {
  fn workspace_sync_source(&self) -> FlowyResult<WorkspaceSyncSource> {
    let session = self.authenticate_user.get_session()?;
    let uid = session.user_id;
    let mut conn = self.authenticate_user.get_sqlite_connection(uid)?;
    let profile = select_user_profile(uid, &session.workspace_id, &mut conn)?;
    let workspace = select_user_workspace(&session.workspace_id, &mut conn)?;
    let migrations: Vec<String> = user_data_migration_records::table
      .select(user_data_migration_records::migration_name)
      .load(&mut *conn)
      .unwrap_or_default();

    let db = self
      .authenticate_user
      .get_collab_db(uid)?
      .upgrade()
      .ok_or_else(|| FlowyError::internal().with_context("the collab database is closed"))?;
    let live = self
      .collab_builder
      .upgrade()
      .map(|builder| builder.live_collabs());

    Ok(WorkspaceSyncSource {
      header: BundleHeader {
        format: BUNDLE_FORMAT,
        kind: BundleKind::Changes,
        uid,
        user_uuid: session.user_uuid.to_string(),
        workspace_id: session.workspace_id.clone(),
        workspace_name: workspace.name,
        workspace_icon: workspace.icon,
        workspace_created_at: workspace.created_at,
        database_storage_id: workspace.database_storage_id,
        user_name: profile.name,
        user_email: profile.email,
        user_icon_url: profile.icon_url,
        device_id: self.authenticate_user.user_config.device_id.clone(),
        created_at: Utc::now().timestamp_millis(),
        migrations,
      },
      store: WorkspaceStore {
        uid,
        workspace_id: session.workspace_id.clone(),
        db,
        live,
      },
      workspace_type: WorkspaceType::from(workspace.workspace_type),
    })
  }

  fn storage_root(&self) -> PathBuf {
    PathBuf::from(&self.authenticate_user.user_config.storage_path)
  }

  /// Writes every collab of the current workspace to [path].
  pub async fn export_workspace_snapshot(
    &self,
    path: &str,
    sync_state_path: &str,
  ) -> FlowyResult<(ExportSummary, BundleHeader, WorkspaceType)> {
    let source = self.workspace_sync_source()?;
    let path = PathBuf::from(path);
    let state_path = optional_path(sync_state_path);
    let header = source.header.clone();
    let workspace_type = source.workspace_type.clone();
    let summary = run_blocking(move || {
      let _turn = WORKSPACE_SYNC_LOCK.lock().unwrap_or_else(|err| err.into_inner());
      export_snapshot(
        &source.store,
        &source.header,
        &path,
        state_path.as_deref(),
      )
    })
    .await?;
    Ok((summary, header, workspace_type))
  }

  /// Writes the collabs of the current workspace that changed since the last
  /// export to [path].
  pub async fn export_workspace_changes(
    &self,
    path: &str,
    sync_state_path: &str,
  ) -> FlowyResult<(ExportSummary, BundleHeader, WorkspaceType)> {
    let source = self.workspace_sync_source()?;
    let state_path = optional_path(sync_state_path)
      .ok_or_else(|| FlowyError::invalid_data().with_context("a sync state path is required"))?;
    let path = PathBuf::from(path);
    let header = source.header.clone();
    let workspace_type = source.workspace_type.clone();
    let summary = run_blocking(move || {
      let _turn = WORKSPACE_SYNC_LOCK.lock().unwrap_or_else(|err| err.into_inner());
      export_changes(&source.store, &source.header, &path, &state_path)
    })
    .await?;
    Ok((summary, header, workspace_type))
  }

  /// Merges the bundle at [path] into the current workspace.
  pub async fn import_workspace_changes(
    &self,
    path: &str,
    sync_state_path: &str,
  ) -> FlowyResult<ImportSummary> {
    let source = self.workspace_sync_source()?;
    let path = PathBuf::from(path);
    let state_path = optional_path(sync_state_path);
    run_blocking(move || {
      let _turn = WORKSPACE_SYNC_LOCK.lock().unwrap_or_else(|err| err.into_inner());
      import_bundle(&source.store, &path, state_path.as_deref())
    })
    .await
  }

  /// Sets the snapshot at [path] aside to replace its workspace when AppFlowy
  /// next starts.
  pub async fn schedule_workspace_restore(
    &self,
    path: &str,
    sync_state_path: &str,
  ) -> FlowyResult<(BundleHeader, u32)> {
    let root = self.storage_root();
    let path = PathBuf::from(path);
    let sync_state_path = sync_state_path.to_string();
    run_blocking(move || {
      let _turn = WORKSPACE_SYNC_LOCK.lock().unwrap_or_else(|err| err.into_inner());
      schedule_restore(&root, &path, &sync_state_path)
    })
    .await
  }

  /// How the last restore went, once.
  pub fn take_workspace_restore_outcome(&self) -> Option<RestoreOutcome> {
    take_restore_outcome(&self.storage_root())
  }
}

fn optional_path(path: &str) -> Option<PathBuf> {
  if path.trim().is_empty() {
    None
  } else {
    Some(Path::new(path).to_path_buf())
  }
}

async fn run_blocking<T, F>(work: F) -> FlowyResult<T>
where
  T: Send + 'static,
  F: FnOnce() -> FlowyResult<T> + Send + 'static,
{
  tokio::task::spawn_blocking(work)
    .await
    .map_err(|err| FlowyError::internal().with_context(err))?
}
