use flowy_derive::ProtoBuf;

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct ExportWorkspaceSnapshotPB {
  /// Where the snapshot bundle is written.
  #[pb(index = 1)]
  pub path: String,

  /// When set, the sync state kept here is reset to say the whole snapshot has
  /// been shared.
  #[pb(index = 2)]
  pub sync_state_path: String,
}

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct ExportWorkspaceChangesPB {
  /// Where the changes bundle is written, if there is anything to send.
  #[pb(index = 1)]
  pub path: String,

  /// The sync state the export compares against. The state reflecting this
  /// export is left beside it with a `.next` suffix, to be moved over once the
  /// bundle has reached the sync folder.
  #[pb(index = 2)]
  pub sync_state_path: String,
}

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct WorkspaceBundlePB {
  #[pb(index = 1)]
  pub object_count: i64,

  /// False when there was nothing to write.
  #[pb(index = 2)]
  pub wrote: bool,

  #[pb(index = 3)]
  pub uid: i64,

  #[pb(index = 4)]
  pub workspace_id: String,

  #[pb(index = 5)]
  pub workspace_name: String,

  #[pb(index = 6)]
  pub is_local_workspace: bool,

  #[pb(index = 7)]
  pub device_id: String,
}

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct ImportWorkspaceChangesPB {
  #[pb(index = 1)]
  pub path: String,

  #[pb(index = 2)]
  pub sync_state_path: String,
}

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct WorkspaceImportPB {
  #[pb(index = 1)]
  pub objects: i64,

  /// Applied to a page or table that was open.
  #[pb(index = 2)]
  pub live: i64,

  #[pb(index = 3)]
  pub created: i64,

  #[pb(index = 4)]
  pub merged: i64,

  #[pb(index = 5)]
  pub unchanged: i64,
}

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct ScheduleWorkspaceRestorePB {
  #[pb(index = 1)]
  pub snapshot_path: String,

  /// When set, the sync state is rewritten for the restored workspace, so the
  /// first export afterwards does not send everything again.
  #[pb(index = 2)]
  pub sync_state_path: String,
}

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct ScheduledWorkspaceRestorePB {
  #[pb(index = 1)]
  pub uid: i64,

  #[pb(index = 2)]
  pub workspace_id: String,

  #[pb(index = 3)]
  pub workspace_name: String,

  #[pb(index = 4)]
  pub object_count: i64,
}

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct WorkspaceRestoreOutcomePB {
  /// False when no restore has happened since the last time this was asked.
  #[pb(index = 1)]
  pub happened: bool,

  #[pb(index = 2)]
  pub succeeded: bool,

  #[pb(index = 3)]
  pub workspace_id: String,

  #[pb(index = 4)]
  pub workspace_name: String,

  #[pb(index = 5)]
  pub object_count: i64,

  #[pb(index = 6)]
  pub detail: String,
}

/// A value kept with the user's account on the server, by name.
#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct CloudUserKeyPB {
  #[pb(index = 1)]
  pub key: String,
}

#[derive(ProtoBuf, Default, Clone, Debug)]
pub struct CloudUserValuePB {
  #[pb(index = 1)]
  pub key: String,

  #[pb(index = 2)]
  pub value: String,

  /// Whether the server holds anything under the key.
  #[pb(index = 3)]
  pub found: bool,
}
