import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

/// The way into a page's previous states, from the page's own options.
///
/// It only opens the rail — the page itself owns the editor, and is the only
/// thing that can put a version back.
class PageVersionsAction extends StatelessWidget {
  const PageVersionsAction({
    super.key,
    required this.view,
    this.onOpened,
  });

  final ViewPB view;

  /// Lets the host close the menu the row was chosen from.
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyIconTextButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: () {
          PageVersionPanel.instance.open(view.id);
          onOpened?.call();
        },
        leftIconBuilder: (_) => const Icon(Icons.history_rounded, size: 16),
        iconPadding: 10.0,
        textBuilder: (_) => FlowyText(
          LocaleKeys.pageVersions_showVersions.tr(),
          figmaLineHeight: 18.0,
        ),
      ),
    );
  }
}
