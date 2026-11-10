//! Two computers keeping one local workspace in sync through bundle files, the
//! way a shared folder carries them: one starts it, the other joins from its
//! snapshot, and from then on their edits are exchanged and merged.

use std::path::{Path, PathBuf};

use event_integration_test::event_builder::EventBuilder;
use event_integration_test::EventIntegrationTest;
use flowy_user::entities::{
  ExportWorkspaceChangesPB, ExportWorkspaceSnapshotPB, ImportWorkspaceChangesPB,
  ScheduleWorkspaceRestorePB, ScheduledWorkspaceRestorePB, WorkspaceBundlePB, WorkspaceImportPB,
  WorkspaceRestoreOutcomePB,
};
use flowy_user::event_map::UserEvent;
use nanoid::nanoid;

const NAME: &str = "appflowy";

struct Computer {
  test: EventIntegrationTest,
  root: PathBuf,
  state: PathBuf,
}

impl Computer {
  async fn start(root: PathBuf) -> Self {
    let mut test = EventIntegrationTest::new_with_user_data_path(root.clone(), NAME.to_string()).await;
    // The folder outlives each instance: restarting in place is the point.
    test.skip_auto_remove_temp_dir();
    let state = root.join("sync_state.json");
    Self { test, root, state }
  }

  /// Closes this instance and opens a new one on the same folder, which is
  /// what AppFlowy does when it restarts in place.
  async fn restart(self) -> Self {
    self.test.appflowy_core.close_db();
    let root = self.root.clone();
    drop(self);
    Self::start(root).await
  }

  async fn export_snapshot(&self, path: &Path) -> WorkspaceBundlePB {
    EventBuilder::new(self.test.clone())
      .event(UserEvent::ExportWorkspaceSnapshot)
      .payload(ExportWorkspaceSnapshotPB {
        path: path.to_string_lossy().to_string(),
        sync_state_path: self.state.to_string_lossy().to_string(),
      })
      .async_send()
      .await
      .parse_or_panic::<WorkspaceBundlePB>()
  }

  /// Exports what changed and, as the sync engine does once the bundle has
  /// been uploaded, commits the state that reflects it.
  async fn export_changes(&self, path: &Path) -> WorkspaceBundlePB {
    let bundle = EventBuilder::new(self.test.clone())
      .event(UserEvent::ExportWorkspaceChanges)
      .payload(ExportWorkspaceChangesPB {
        path: path.to_string_lossy().to_string(),
        sync_state_path: self.state.to_string_lossy().to_string(),
      })
      .async_send()
      .await
      .parse_or_panic::<WorkspaceBundlePB>();
    if bundle.wrote {
      let next = self.root.join("sync_state.json.next");
      std::fs::rename(next, &self.state).unwrap();
    }
    bundle
  }

  async fn import(&self, path: &Path) -> WorkspaceImportPB {
    EventBuilder::new(self.test.clone())
      .event(UserEvent::ImportWorkspaceChanges)
      .payload(ImportWorkspaceChangesPB {
        path: path.to_string_lossy().to_string(),
        sync_state_path: self.state.to_string_lossy().to_string(),
      })
      .async_send()
      .await
      .parse_or_panic::<WorkspaceImportPB>()
  }

  async fn schedule_restore(&self, snapshot: &Path) -> ScheduledWorkspaceRestorePB {
    EventBuilder::new(self.test.clone())
      .event(UserEvent::ScheduleWorkspaceRestore)
      .payload(ScheduleWorkspaceRestorePB {
        snapshot_path: snapshot.to_string_lossy().to_string(),
        sync_state_path: self.state.to_string_lossy().to_string(),
      })
      .async_send()
      .await
      .parse_or_panic::<ScheduledWorkspaceRestorePB>()
  }

  async fn restore_outcome(&self) -> WorkspaceRestoreOutcomePB {
    EventBuilder::new(self.test.clone())
      .event(UserEvent::TakeWorkspaceRestoreOutcome)
      .async_send()
      .await
      .parse_or_panic::<WorkspaceRestoreOutcomePB>()
  }

  /// Every line of text on the page, sorted, so two computers can be compared
  /// regardless of the order concurrent lines were merged in.
  async fn page_text(&self, view_id: &str) -> Vec<String> {
    let data = self.test.get_document_data(view_id).await;
    let mut lines = data
      .meta
      .text_map
      .unwrap_or_default()
      .into_values()
      .filter_map(|delta| {
        let ops: Vec<serde_json::Value> = serde_json::from_str(&delta).ok()?;
        let line = ops
          .iter()
          .filter_map(|op| op.get("insert").and_then(|text| text.as_str()))
          .collect::<String>();
        (!line.is_empty()).then_some(line)
      })
      .collect::<Vec<_>>();
    lines.sort();
    lines
  }
}

fn temp_root(label: &str) -> PathBuf {
  let root = std::env::temp_dir().join(format!("workspace_sync_{}_{}", label, nanoid!(6)));
  std::fs::create_dir_all(&root).unwrap();
  root
}

#[tokio::test]
async fn two_computers_join_merge_and_restore() {
  let folder = temp_root("folder");

  // The first computer starts the sync folder from its workspace.
  let a = Computer::start(temp_root("a")).await;
  let a_profile = a.test.init_anon_user().await;
  let page = a.test.create_document("Shared page").await;
  a.test.insert_document_text(&page.id, "Hello from A", 0).await;
  let base = folder.join("base.snapshot");
  let exported = a.export_snapshot(&base).await;
  assert!(exported.wrote);
  assert!(exported.is_local_workspace);
  assert!(exported.object_count > 1);
  assert_eq!(exported.uid, a_profile.id);

  // The second computer has a workspace of its own, which it replaces by
  // joining. Its own stays where it was.
  let b = Computer::start(temp_root("b")).await;
  let b_profile = b.test.init_anon_user().await;
  assert_ne!(a_profile.id, b_profile.id);
  let scheduled = b.schedule_restore(&base).await;
  assert_eq!(scheduled.uid, a_profile.id);
  assert_eq!(scheduled.object_count, exported.object_count);

  let b = b.restart().await;
  let outcome = b.restore_outcome().await;
  assert!(outcome.happened && outcome.succeeded, "{}", outcome.detail);
  assert!(!b.restore_outcome().await.happened);
  assert_eq!(b.test.get_user_profile().await.unwrap().id, a_profile.id);
  assert_eq!(
    b.test.get_current_workspace().await.id,
    a.test.get_current_workspace().await.id
  );
  assert!(b.root.join(b_profile.id.to_string()).exists());
  assert_eq!(b.page_text(&page.id).await, vec!["Hello from A"]);

  // Joining leaves nothing to send back: the snapshot is already shared.
  assert!(!b.export_changes(&folder.join("b-0.changes")).await.wrote);

  // B has the page open when A's edit arrives, so it lands in the open copy.
  b.test.open_document(page.id.clone()).await;
  a.test
    .insert_document_text(&page.id, "Second line from A", 1)
    .await;
  let a1 = folder.join("a-1.changes");
  let sent = a.export_changes(&a1).await;
  assert!(sent.wrote);
  assert_eq!(sent.object_count, 1);
  let received = b.import(&a1).await;
  assert_eq!(received.objects, 1);
  assert_eq!(received.live, 1);
  assert_eq!(
    b.page_text(&page.id).await,
    vec!["Hello from A", "Second line from A"]
  );

  // An update that only came from elsewhere is not sent back again.
  assert!(!b.export_changes(&folder.join("b-1.changes")).await.wrote);
  // Importing the same bundle twice changes nothing.
  b.import(&a1).await;
  assert_eq!(
    b.page_text(&page.id).await,
    vec!["Hello from A", "Second line from A"]
  );
  assert!(!b.export_changes(&folder.join("b-1b.changes")).await.wrote);

  // Both computers edit the same page before hearing from each other.
  a.test.insert_document_text(&page.id, "A offline", 2).await;
  b.test.insert_document_text(&page.id, "B offline", 2).await;
  let a2 = folder.join("a-2.changes");
  let b2 = folder.join("b-2.changes");
  assert!(a.export_changes(&a2).await.wrote);
  assert!(b.export_changes(&b2).await.wrote);
  b.import(&a2).await;
  a.import(&b2).await;

  let expected = vec![
    "A offline",
    "B offline",
    "Hello from A",
    "Second line from A",
  ];
  assert_eq!(a.page_text(&page.id).await, expected);
  assert_eq!(b.page_text(&page.id).await, expected);
  // Merged, and nothing either side still owes the other.
  assert!(!a.export_changes(&folder.join("a-3.changes")).await.wrote);
  assert!(!b.export_changes(&folder.join("b-3.changes")).await.wrote);

  // A page created on one computer arrives on the other.
  let second = a.test.create_document("Made on A").await;
  a.test.insert_document_text(&second.id, "New page", 0).await;
  let a4 = folder.join("a-4.changes");
  assert!(a.export_changes(&a4).await.wrote);
  let received = b.import(&a4).await;
  assert!(received.created >= 1, "{:?}", received);
  assert_eq!(b.page_text(&second.id).await, vec!["New page"]);
  assert!(b
    .test
    .get_all_workspace_views()
    .await
    .iter()
    .any(|view| view.id == second.id));

  // Restoring puts the workspace back exactly as the snapshot had it.
  a.schedule_restore(&base).await;
  let a = a.restart().await;
  let outcome = a.restore_outcome().await;
  assert!(outcome.succeeded, "{}", outcome.detail);
  assert_eq!(a.test.get_user_profile().await.unwrap().id, a_profile.id);
  assert_eq!(a.page_text(&page.id).await, vec!["Hello from A"]);
  assert!(!a
    .test
    .get_all_workspace_views()
    .await
    .iter()
    .any(|view| view.id == second.id));

  // A bundle for another workspace is refused rather than merged.
  let stranger = Computer::start(temp_root("c")).await;
  stranger.test.init_anon_user().await;
  let foreign = folder.join("c.snapshot");
  stranger.export_snapshot(&foreign).await;
  let refused = EventBuilder::new(a.test.clone())
    .event(UserEvent::ImportWorkspaceChanges)
    .payload(ImportWorkspaceChangesPB {
      path: foreign.to_string_lossy().to_string(),
      sync_state_path: a.state.to_string_lossy().to_string(),
    })
    .async_send()
    .await
    .error();
  assert!(refused.is_some());

  for root in [&folder, &a.root, &b.root, &stranger.root] {
    let _ = std::fs::remove_dir_all(root);
  }
}
