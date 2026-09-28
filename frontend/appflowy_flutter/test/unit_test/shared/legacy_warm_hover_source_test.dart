import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// These guards inspect the real call sites without importing database/native
// viewer dependencies. They are NOT rendered row or database behavior tests;
// legacy_warm_hover_test.dart exercises their shared paint adapter separately.
const _cellEditors = 'lib/plugins/database/widgets/cell_editor';
const _notification =
    'lib/workspace/presentation/notifications/widgets/notification_item.dart';

void main() {
  test('media row adapts only its existing hover paint', () {
    final build = _build(
        _class('$_cellEditors/media_cell_editor.dart', '_RenderMediaState'));
    final hover = _hover(build, 'isHovering', 'greyHover');
    final style = _calls(_named(hover, 'style'), 'HoverStyle').single;
    expect(
        _named(style, 'borderRadius').toSource(), 'BorderRadius.circular(4)');
    final region = _calls(build, 'MouseRegion').single;
    expect(_named(region, 'onEnter').toSource(),
        '(_) => setState(() => isHovering = true)');
    expect(_named(region, 'onExit').toSource(),
        '(_) => setState(() => isHovering = false)');
    expect(
        _named(_calls(build, 'MediaActionReveal').single, 'visible').toSource(),
        'isHovering');
    expect(_calls(build, 'ReorderableDragStartListener'), hasLength(1));
    expect(
        _named(_calls(build, 'AppFlowyPopover').single, 'controller')
            .toSource(),
        'controller');
    _noDirectAliasFill(build);
  });

  test('relation option keeps focus ownership, linked-row actions and geometry',
      () {
    final build = _build(
        _class('$_cellEditors/relation_cell_editor.dart', '_RowListItem'));
    final hover = _hover(build, 'isHovered', 'lightGreyHover');
    final focused = _nodes<VariableDeclaration>(build)
        .singleWhere((node) => node.name.lexeme == 'isHovered');
    expect(focused.initializer!.toSource(),
        'context.watch<RelationRowSearchBloc>().state.focusedRowId == row.rowId');
    final container = _calls(build, 'Container').single;
    expect((_named(container, 'height') as IntegerLiteral).value, 28);
    expect(_named(container, 'margin').toSource(),
        'const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0)');
    expect(_calls(_named(hover, 'child'), 'GestureDetector'), hasLength(1));
    final region = _calls(build, 'MouseRegion').single;
    expect(_named(region, 'onHover').toSource(),
        '(_) => context.read<RelationRowSearchBloc>().add(RelationRowSearchEvent.updateFocusedOption(row.rowId))');
    expect(
        region.arguments
            .whereType<NamedExpression>()
            .any((arg) => arg.name.label.name == 'onExit'),
        isFalse);
    final tap = _named(_calls(build, 'GestureDetector').single, 'onTap');
    expect(_nodes<IfStatement>(tap).single.expression.toSource(), 'isSelected');
    expect(_calls(tap, 'showRelatedRowDetailPage'), hasLength(1));
    expect(_calls(tap, 'RelationCellEvent.selectRow'), hasLength(1));
    _noDirectAliasFill(build);
  });

  test(
      'notification hover keeps action gating, read opacity and non-layout stripe',
      () {
    final build = _build(_class(_notification, '_NotificationItemState'));
    final hover = _hover(
        build, '_isHovering && widget.onAction != null', 'lightGreyHover');
    final style = _calls(_named(hover, 'style'), 'HoverStyle').single;
    expect(_named(style, 'borderRadius').toSource(), 'BorderRadius.zero');
    expect(
        style.arguments
            .whereType<NamedExpression>()
            .any((arg) => arg.name.label.name == 'border'),
        isFalse);
    final decorated = _named(hover, 'child');
    final decoration = _calls(decorated, 'DecoratedBox').first;
    final box =
        _calls(_named(decoration, 'decoration'), 'BoxDecoration').single;
    final border = _named(box, 'border') as ConditionalExpression;
    expect(border.condition.toSource(), 'widget.isRead || widget.readOnly');
    expect(border.thenExpression, isA<NullLiteral>());
    final stripe = _calls(border.elseExpression, 'BorderSide').single;
    expect(_named(stripe, 'width').toSource(),
        'UniversalPlatform.isMobile ? 4 : 2');
    expect(_named(stripe, 'color').toSource(),
        'Theme.of(context).colorScheme.primary');
    expect(_named(_calls(build, 'Opacity').single, 'opacity').toSource(),
        'widget.isRead && !widget.readOnly ? 0.5 : 1');
    _noDirectAliasFill(build);

    // This same alias is still a border on the actions, not a hover fill.
    final actions = _build(_class(_notification, 'NotificationItemActions'));
    expect(_named(_calls(actions, 'Border.all').single, 'color').toSource(),
        'AFThemeExtension.of(context).lightGreyHover');
  });

  test('email rail forwards all-inbox identity to the existing central mapping',
      () {
    const path = 'lib/plugins/collection/views/email/email_toolbar.dart';
    final rail = _build(_class(path, 'EmailSenderRail'));
    expect(_named(_calls(rail, '_RailRow').first, 'icon').toSource(),
        'Icons.all_inbox_rounded');
    final build = _build(_class(
      path,
      '_RailRow',
    ));
    final glyph = _calls(build, 'WorkspaceGlyph').single;
    final icon = glyph.arguments.first as PostfixExpression;
    expect(icon.operand.toSource(), 'icon');
    expect(icon.operator.lexeme, '!');
    expect(WorkspaceGlyphs.nameForIcon(Icons.all_inbox_rounded), 'inboxes');
    expect(WorkspaceGlyphs.nameForIcon(Icons.inbox_rounded), isNot('inboxes'));
  });
}

ClassDeclaration _class(String path, String name) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason: 'Run from frontend/appflowy_flutter: $path');
  final parsed =
      parseString(content: file.readAsStringSync(), throwIfDiagnostics: false);
  expect(parsed.errors, isEmpty, reason: path);
  return parsed.unit.declarations
      .whereType<ClassDeclaration>()
      .singleWhere((node) => node.name.lexeme == name);
}

MethodDeclaration _build(ClassDeclaration declaration) => declaration.members
    .whereType<MethodDeclaration>()
    .singleWhere((node) => node.name.lexeme == 'build');

Iterable<T> _nodes<T extends AstNode>(AstNode root) sync* {
  if (root is T) yield root;
  for (final child in root.childEntities.whereType<AstNode>()) {
    yield* _nodes<T>(child);
  }
}

Iterable<ArgumentList> _calls(AstNode root, String name) sync* {
  for (final node in _nodes<AstNode>(root)) {
    if (node is MethodInvocation) {
      final target = node.target;
      final actual = target == null
          ? node.methodName.name
          : '${target.toSource()}.${node.methodName.name}';
      if (actual == name) yield node.argumentList;
    } else if (node is InstanceCreationExpression &&
        node.constructorName.toSource() == name) {
      yield node.argumentList;
    }
  }
}

Expression _named(ArgumentList arguments, String name) => arguments.arguments
    .whereType<NamedExpression>()
    .singleWhere((arg) => arg.name.label.name == name)
    .expression;

ArgumentList _hover(AstNode build, String condition, String alias) {
  final hover = _calls(build, 'FlowyHoverContainer').single;
  expect(_named(hover, 'applyStyle').toSource(), condition);
  final style = _calls(_named(hover, 'style'), 'HoverStyle').single;
  expect(_named(style, 'hoverColor').toSource(),
      'AFThemeExtension.of(context).$alias');
  expect(
      style.arguments
          .whereType<NamedExpression>()
          .any((arg) => arg.name.label.name == 'backgroundColor'),
      isFalse);
  expect(
      hover.arguments
          .whereType<NamedExpression>()
          .any((arg) => arg.name.label.name == 'isSelected'),
      isFalse);
  return hover;
}

void _noDirectAliasFill(AstNode build) {
  for (final decoration in _calls(build, 'BoxDecoration')) {
    for (final color in decoration.arguments
        .whereType<NamedExpression>()
        .where((arg) => arg.name.label.name == 'color')) {
      final source = color.expression.toSource();
      expect(source, isNot(contains('.greyHover')));
      expect(source, isNot(contains('.lightGreyHover')));
    }
  }
}
