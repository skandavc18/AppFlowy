import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/object_type_typography.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('code blocks use polished 550 text and warm surfaces',
      (tester) async {
    final appearanceCubit = DocumentAppearanceCubit();
    addTearDown(appearanceCubit.close);
    late CodeBlockStyle codeBlockStyle;
    final theme = DesktopAppearance()
        .getThemeData(
          AppTheme.fallback,
          Brightness.light,
          defaultFontFamily,
          builtInCodeFontFamily,
        )
        .copyWith(platform: TargetPlatform.windows);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: BlocProvider.value(
          value: appearanceCubit,
          child: Builder(
            builder: (context) {
              codeBlockStyle = EditorStyleCustomizer(
                context: context,
                padding: EdgeInsets.zero,
              ).codeBlockStyleBuilder();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final textStyle = codeBlockStyle.textStyle!;
    expect(textStyle.fontFamily, builtInCodeFontFamily);
    expect(textStyle.fontWeight, FontWeight.w500);
    expect(textStyle.fontVariations, flowyRegularFontVariations);
    expect(textStyle.fontFeatures, isNotEmpty);
    expect(textStyle.color, ObjectTypeTypography.lightEditorTextColor);
    expect(textStyle.shadows, isNotEmpty);
    expect(
      codeBlockStyle.backgroundColor,
      EditorSurfaceStyle.lightCodeBlockBackground,
    );
    expect(
      theme.extension<AFThemeExtension>()?.calloutBGColor,
      EditorSurfaceStyle.lightCalloutBackground,
    );
  });
}
