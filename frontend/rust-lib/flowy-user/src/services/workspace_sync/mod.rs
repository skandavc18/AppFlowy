//! Keeping a local workspace the same on several computers, through nothing
//! more than a shared folder.
//!
//! The pieces, in the order they are used:
//! - [bundle]: the file format a workspace's collabs travel in;
//! - [store]: reading collabs straight from the collab database;
//! - [state]: what this computer has already shared;
//! - [exchange]: exporting what changed and merging what arrived;
//! - [restore]: replacing a whole workspace with a snapshot at the next start.

mod bundle;
mod exchange;
mod restore;
mod state;
mod store;

pub use bundle::{
  BundleEntry, BundleError, BundleHeader, BundleKind, BundleReader, BundleWriter, BUNDLE_FORMAT,
  BUNDLE_MAGIC,
};
pub use exchange::{export_changes, export_snapshot, import_bundle, ExportSummary, ImportSummary};
pub use restore::{
  apply_pending_restore, has_pending_restore, schedule_restore, take_restore_outcome,
  RestoreOutcome,
};
pub use state::{covers, pending_state_path, SyncState};
pub use store::{object_ids, WorkspaceStore};

use std::sync::Mutex;

/// Exports, imports and restores take turns: each reads and rewrites the same
/// sync state, and two of them interleaving would lose one's bookkeeping.
pub(crate) static WORKSPACE_SYNC_LOCK: Mutex<()> = Mutex::new(());
