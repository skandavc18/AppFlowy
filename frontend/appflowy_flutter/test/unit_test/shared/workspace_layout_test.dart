import 'dart:math' as math;

import 'package:appflowy/shared/workspace_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _widths = [320.0, 480.0, 800.0, 1280.0, 1920.0, 2560.0];

void main() {
  group('document reading geometry', () {
    for (final width in _widths) {
      for (final maximum in [480.0, 960.0, 1111.0, 1280.0, 1920.0]) {
        test('$width pane retains the $maximum preferred maximum', () {
          final geometry = WorkspaceDocumentGeometry.resolve(
            availableWidth: width,
            preferredMaxWidth: maximum,
            actionGutterWidth: 63,
          );
          expect(geometry.pageWidth, math.min(width, maximum));
          expect(geometry.contentLeft, geometry.contentRight);
          expect(geometry.editorPadding.left, greaterThanOrEqualTo(0));
          expect(
            geometry.editorPadding.left + 63,
            geometry.headerPadding.left,
          );
          expect(geometry.editorPadding.right, geometry.headerPadding.right);
          expect(geometry.contentWidth, greaterThan(0));
          expect(
            geometry.outerInset * 2 +
                geometry.contentLeft +
                geometry.contentWidth +
                geometry.contentRight,
            closeTo(width, 0.0001),
          );
          // Rendering at another size does not normalize a custom preference
          // to one of the preset values.
          final restored = WorkspaceDocumentGeometry.resolve(
            availableWidth: 2560,
            preferredMaxWidth: maximum,
            actionGutterWidth: 63,
          );
          expect(restored.pageWidth, maximum);
        });
      }
    }

    test('concrete full-width measurements use equal logical gutters', () {
      const insets = [64.0, 64.0, 80.0, 96.0, 96.0, 96.0];
      const measures = [192.0, 352.0, 640.0, 1088.0, 1728.0, 1728.0];
      for (var i = 0; i < _widths.length; i++) {
        final geometry = WorkspaceDocumentGeometry.resolve(
          availableWidth: _widths[i],
          preferredMaxWidth: 1920,
          actionGutterWidth: 63,
        );
        expect(geometry.contentLeft, insets[i]);
        expect(geometry.contentWidth, measures[i]);
      }
    });

    test('zero, tiny and non-finite constraints never produce negative insets',
        () {
      for (final width in [0.0, 1.0, 48.0, 63.0, 127.0, double.infinity]) {
        final geometry = WorkspaceDocumentGeometry.resolve(
          availableWidth: width,
          preferredMaxWidth: 1111,
          actionGutterWidth: 63,
        );
        for (final value in [
          geometry.pageWidth,
          geometry.outerInset,
          geometry.contentWidth,
          geometry.editorPadding.left,
          geometry.editorPadding.right,
        ]) {
          expect(value.isFinite, isTrue);
          expect(value, greaterThanOrEqualTo(0));
        }
        expect(
          geometry.headerPadding.horizontal,
          lessThanOrEqualTo(geometry.pageWidth),
        );
      }
    });

    test('invalid maximum falls back to the pane without changing settings',
        () {
      for (final maximum in [0.0, -1.0, double.nan, double.infinity]) {
        final geometry = WorkspaceDocumentGeometry.resolve(
          availableWidth: 480,
          preferredMaxWidth: maximum,
          actionGutterWidth: 63,
        );
        expect(geometry.pageWidth, 480);
        expect(geometry.contentWidth, 352);
      }
    });
  });

  group('shell allocation', () {
    for (final width in _widths) {
      for (final sidebar in [true, false]) {
        for (final panel in [true, false]) {
          test('$width sidebar=$sidebar panel=$panel stays inside its pane',
              () {
            final geometry = WorkspaceShellGeometry.resolve(
              availableWidth: width,
              preferredSidebarWidth: 10000,
              showSidebar: sidebar,
              showEditPanel: panel,
              preferredEditPanelWidth: 400,
            );
            expect(
              geometry.sidebarIsDrawer,
              width < WorkspaceLayout.sidebarBreakpoint,
            );
            expect(geometry.sidebarWidth, inInclusiveRange(0, width));
            expect(geometry.editPanelWidth, inInclusiveRange(0, width));
            expect(geometry.contentWidth, greaterThanOrEqualTo(320));
            expect(
              geometry.contentLeft +
                  geometry.contentWidth +
                  geometry.contentRight,
              width,
            );
            if (geometry.sidebarIsDrawer) {
              expect(geometry.contentLeft, 0);
              expect(geometry.contentRight, 0);
              expect(
                geometry.sidebarWidth,
                lessThanOrEqualTo(width - WorkspaceLayout.drawerEdge),
              );
            }
          });
        }
      }
    }

    test('a constrained sidebar recovers its preference when the pane grows',
        () {
      WorkspaceShellGeometry at(double width) => WorkspaceShellGeometry.resolve(
            availableWidth: width,
            preferredSidebarWidth: 460,
            showSidebar: true,
            showEditPanel: true,
            preferredEditPanelWidth: 400,
          );
      expect(at(1920).sidebarWidth, 460);
      expect(at(1024).sidebarWidth, 304);
      expect(at(320).sidebarWidth, 288);
      expect(at(1920).sidebarWidth, 460);
    });

    test('one breakpoint distinguishes drawer and docked geometry', () {
      expect(WorkspaceLayout.sidebarIsDrawer(1023.99), isTrue);
      expect(WorkspaceLayout.sidebarIsDrawer(1024), isFalse);
    });
  });

  group('header and constraint resolution', () {
    test('local constraints win over a larger screen fallback', () {
      expect(
        WorkspaceLayout.availableWidth(
          const BoxConstraints(maxWidth: 320),
          fallbackWidth: 2560,
        ),
        320,
      );
      expect(
        WorkspaceLayout.availableWidth(
          const BoxConstraints(minWidth: 480),
          fallbackWidth: 320,
        ),
        480,
      );
      expect(
        WorkspaceLayout.availableWidth(const BoxConstraints()),
        WorkspaceLayout.headerBreakpoint,
      );
    });

    for (final width in _widths) {
      for (final scale in [1.0, 2.0]) {
        test('$width header at $scale text scale allocates finite columns', () {
          final geometry = WorkspaceHeaderGeometry.resolve(
            availableWidth: width,
            textScale: scale,
          );
          expect(
            geometry.stacked,
            width < WorkspaceLayout.headerBreakpoint * scale,
          );
          for (final value in [geometry.identityWidth, geometry.actionsWidth]) {
            expect(value.isFinite, isTrue);
            expect(value, inInclusiveRange(0, width));
          }
          if (geometry.stacked) {
            expect(geometry.identityWidth, width);
            expect(geometry.actionsWidth, width);
          } else {
            expect(
              geometry.identityWidth +
                  WorkspaceHeaderGeometry.gap +
                  geometry.actionsWidth,
              closeTo(width, 0.0001),
            );
          }
        });
      }
    }
  });
}
