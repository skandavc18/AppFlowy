//! The collabs that are open in memory right now.
//!
//! An update that arrives from another computer has to reach the copy the
//! editor is showing, not only the one on disk: a document that is open keeps
//! its own state in memory, so an update written only to disk would stay
//! invisible until the document was closed and opened again. Every collab built
//! by [crate::collab_builder::AppFlowyCollabBuilder] is therefore registered
//! here, and an incoming update is applied to the live copy whenever there is
//! one.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, Weak};

use collab::core::collab_plugin::CollabPluginType;
use collab::core::origin::CollabOrigin;
use collab::preclude::{Collab, CollabPlugin, Doc, ReadTxn, Snapshot, Transact, Update};

/// One open collab.
pub struct LiveDoc {
  object_id: String,
  workspace_id: String,
  doc: Doc,
  /// Whether the collab has been initialised, which is the moment its disk
  /// plugin starts persisting the updates applied to it.
  initialized: AtomicBool,
}

impl LiveDoc {
  pub fn object_id(&self) -> &str {
    &self.object_id
  }

  pub fn workspace_id(&self) -> &str {
    &self.workspace_id
  }

  /// Whether an update applied to this collab is persisted by its own disk
  /// plugin. A collab that was loaded but never initialised is a read-only
  /// copy: whatever is applied to it has to be written to disk separately.
  pub fn persists_updates(&self) -> bool {
    self.initialized.load(Ordering::Acquire)
  }

  /// Applies [update] as a change that came from somewhere else.
  ///
  /// The origin is deliberately not the local client's: observers use it to
  /// tell a remote change from a local one, so the editor redraws it and the
  /// undo manager does not offer to undo somebody else's typing.
  ///
  /// [inspect] runs inside the same exclusive transaction, once before and once
  /// after the update is applied, so nothing typed locally can slip in between
  /// the two snapshots it is shown.
  pub fn apply_remote_update(
    &self,
    update: Update,
    mut inspect: impl FnMut(SnapshotMoment, &Snapshot),
  ) -> Result<(), anyhow::Error> {
    let mut txn = self.doc.transact_mut_with(CollabOrigin::Server);
    inspect(SnapshotMoment::Before, &txn.snapshot());
    txn.apply_update(update)?;
    inspect(SnapshotMoment::After, &txn.snapshot());
    txn.commit();
    Ok(())
  }
}

/// When [LiveDoc::apply_remote_update] shows a snapshot.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SnapshotMoment {
  Before,
  After,
}

/// Every open collab, by object id.
///
/// ⚠️ Owned by one collab builder rather than shared by the process: tests run
/// several AppFlowy cores side by side, and two of them syncing the same
/// workspace hold collabs with the same object ids.
#[derive(Default)]
pub struct LiveCollabRegistry {
  docs: Mutex<HashMap<String, Vec<Weak<LiveDoc>>>>,
}

impl LiveCollabRegistry {
  pub fn new() -> Self {
    Self::default()
  }

  /// Starts tracking [collab], returning the plugin that keeps the entry alive
  /// for exactly as long as the collab itself.
  pub fn track(&self, workspace_id: &str, collab: &Collab) -> LiveCollabPlugin {
    let live = Arc::new(LiveDoc {
      object_id: collab.object_id().to_string(),
      workspace_id: workspace_id.to_string(),
      doc: collab.doc().clone(),
      initialized: AtomicBool::new(false),
    });
    let mut docs = self.docs.lock().unwrap_or_else(|err| err.into_inner());
    let entry = docs.entry(live.object_id.clone()).or_default();
    entry.retain(|weak| weak.strong_count() > 0);
    entry.push(Arc::downgrade(&live));
    LiveCollabPlugin { live }
  }

  /// The open copies of one object in one workspace.
  pub fn live_docs(&self, workspace_id: &str, object_id: &str) -> Vec<Arc<LiveDoc>> {
    let mut docs = self.docs.lock().unwrap_or_else(|err| err.into_inner());
    let Some(entry) = docs.get_mut(object_id) else {
      return vec![];
    };
    entry.retain(|weak| weak.strong_count() > 0);
    let live = entry
      .iter()
      .filter_map(Weak::upgrade)
      .filter(|doc| doc.workspace_id == workspace_id)
      .collect::<Vec<_>>();
    if entry.is_empty() {
      docs.remove(object_id);
    }
    live
  }

  /// How many objects have at least one open copy.
  pub fn len(&self) -> usize {
    let mut docs = self.docs.lock().unwrap_or_else(|err| err.into_inner());
    docs.retain(|_, entry| {
      entry.retain(|weak| weak.strong_count() > 0);
      !entry.is_empty()
    });
    docs.len()
  }

  pub fn is_empty(&self) -> bool {
    self.len() == 0
  }
}

/// Keeps a [LiveDoc] registered while its collab is alive, and notes the
/// moment the collab is initialised.
pub struct LiveCollabPlugin {
  live: Arc<LiveDoc>,
}

impl CollabPlugin for LiveCollabPlugin {
  fn did_init(&self, _collab: &Collab, _object_id: &str) {
    self.live.initialized.store(true, Ordering::Release);
  }

  fn plugin_type(&self) -> CollabPluginType {
    CollabPluginType::Other("LiveCollabPlugin".to_string())
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use collab::preclude::updates::decoder::Decode;
  use collab::preclude::{Map, MapExt};

  fn new_collab(object_id: &str) -> Collab {
    Collab::new(1, object_id, "device", vec![], true)
  }

  #[test]
  fn a_dropped_collab_is_forgotten() {
    let registry = LiveCollabRegistry::new();
    let collab = new_collab("a");
    let plugin = registry.track("w", &collab);
    assert_eq!(registry.live_docs("w", "a").len(), 1);
    assert!(registry.live_docs("other", "a").is_empty());
    drop(plugin);
    assert!(registry.live_docs("w", "a").is_empty());
    assert!(registry.is_empty());
  }

  #[test]
  fn a_remote_update_reaches_the_open_copy() {
    let registry = LiveCollabRegistry::new();
    let open = new_collab("doc");
    let _plugin = registry.track("w", &open);

    let mut elsewhere = new_collab("doc");
    let data = elsewhere.data.clone();
    {
      let mut txn = elsewhere.transact_mut();
      data.insert(&mut txn, "title", "from elsewhere");
    }
    let update = elsewhere
      .transact()
      .encode_state_as_update_v1(&Default::default());

    let mut moments = vec![];
    for live in registry.live_docs("w", "doc") {
      live
        .apply_remote_update(Update::decode_v1(&update).unwrap(), |moment, _| {
          moments.push(moment)
        })
        .unwrap();
    }
    assert_eq!(moments, vec![SnapshotMoment::Before, SnapshotMoment::After]);

    let txn = open.transact();
    let title: String = open.data.get_with_txn(&txn, "title").unwrap();
    assert_eq!(title, "from elsewhere");
  }
}
