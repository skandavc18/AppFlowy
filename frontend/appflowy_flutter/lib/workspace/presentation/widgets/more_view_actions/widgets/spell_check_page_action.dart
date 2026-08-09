import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_page_settings.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The page's own answer to whether its writing is checked.
///
/// It sits with the rest of the page options because that is where somebody
/// looks when one page should be left alone — a page of names, a page of
/// commands — without turning the feature off everywhere.
class SpellCheckPageAction extends StatefulWidget {
  const SpellCheckPageAction({super.key, required this.view});

  final ViewPB view;

  @override
  State<SpellCheckPageAction> createState() => _SpellCheckPageActionState();
}

class _SpellCheckPageActionState extends State<SpellCheckPageAction> {
  SpellCheckPageSettings get _settings => SpellCheckPageSettings.instance;

  @override
  void initState() {
    super.initState();
    _settings.adopt(widget.view);
    _settings.addListener(_onChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _settings.isEnabledFor(widget.view.id);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyIconTextButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: _toggle,
        leftIconBuilder: (_) => const Icon(Icons.spellcheck_rounded, size: 16),
        iconPadding: 10.0,
        textBuilder: (_) => FlowyText(
          LocaleKeys.document_spellCheck_pageOption.tr(),
          figmaLineHeight: 18.0,
        ),
        rightIconBuilder: (_) => Container(
          width: 30,
          height: 20,
          margin: const EdgeInsets.only(right: 6),
          child: FittedBox(
            fit: BoxFit.fill,
            child: CupertinoSwitch(
              value: enabled,
              activeTrackColor: Theme.of(context).colorScheme.primary,
              onChanged: (_) => _toggle(),
            ),
          ),
        ),
      ),
    );
  }

  void _toggle() => unawaited(
        _settings.setEnabled(
          widget.view.id,
          !_settings.isEnabledFor(widget.view.id),
          extra: widget.view.extra,
        ),
      );
}
