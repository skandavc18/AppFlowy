use event_integration_test::EventIntegrationTest;

#[tokio::test]
async fn workspace_cover_persists_and_clears_locally() {
  let test = EventIntegrationTest::new().await;
  let _profile = test.init_anon_user().await;

  let workspace_id = test.get_all_workspaces().await.items[0]
    .workspace_id
    .clone();
  let cover = r##"{"type":"color","value":"#f4d35e"}"##;

  test
    .change_workspace_cover(&workspace_id, cover)
    .await
    .expect("failed to change workspace cover");

  let workspaces = test.get_all_workspaces().await;
  assert_eq!(workspaces.items[0].cover, cover);

  let current_workspace = test.folder_read_current_workspace().await;
  assert_eq!(current_workspace.cover, cover);

  test
    .change_workspace_cover(&workspace_id, "")
    .await
    .expect("failed to clear workspace cover");

  let workspaces = test.get_all_workspaces().await;
  assert!(workspaces.items[0].cover.is_empty());

  let current_workspace = test.folder_read_current_workspace().await;
  assert!(current_workspace.cover.is_empty());
}
