import 'dart:math' as math;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_page_turn.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rect = Rect.fromLTWH(120, 40, 600, 800);

  PageCurlSurface surfaceAt(
    double progress, {
    bool pivotOnLeft = true,
    bool leadFromBottom = true,
  }) =>
      buildPageCurlSurface(
        rect: rect,
        progress: progress,
        pivotOnLeft: pivotOnLeft,
        leadFromBottom: leadFromBottom,
      );

  Offset vertexAt(PageCurlSurface surface, int index) => Offset(
        surface.positions[index * 2],
        surface.positions[index * 2 + 1],
      );

  group('page curl geometry', () {
    test('a page at rest is undeformed and shows only its front', () {
      final surface = surfaceAt(0);

      expect(surface.lift, closeTo(0, 0.0001));
      expect(surface.backIndices, isEmpty);
      expect(surface.frontIndices, isNotEmpty);
      for (var i = 0; i < surface.positions.length; i += 2) {
        expect(surface.positions[i], greaterThanOrEqualTo(rect.left - 0.01));
        expect(surface.positions[i], lessThanOrEqualTo(rect.right + 0.01));
        expect(surface.positions[i + 1], greaterThanOrEqualTo(rect.top - 0.01));
        expect(
          surface.positions[i + 1],
          lessThanOrEqualTo(rect.bottom + 0.01),
        );
      }
    });

    test('a finished turn lands mirrored on the facing page', () {
      final surface = surfaceAt(1);

      // Every point of the outer edge ends a full page width past the pivot,
      // which is exactly where the facing page sits.
      for (final point in surface.leadingEdge) {
        expect(point.dx, closeTo(rect.left - rect.width, 2));
      }
      expect(surface.lift, closeTo(0, 0.0001));
    });

    test('the leading corner moves before the trailing one', () {
      final surface = surfaceAt(0.45);
      final edge = surface.leadingEdge;

      expect(edge.length, greaterThan(2));
      // The bottom corner leads, so it has travelled further towards the pivot.
      expect(edge.last.dx, lessThan(edge.first.dx));
    });

    test('the top corner leads when the drag starts there', () {
      final surface = surfaceAt(0.45, leadFromBottom: false);
      final edge = surface.leadingEdge;

      expect(edge.first.dx, lessThan(edge.last.dx));
    });

    test('the sheet rolls rather than rotating flat', () {
      final surface = surfaceAt(0.5);

      // A rigid rotation keeps every point on one line; a roll bends the sheet
      // back on itself, so part of it shows its reverse.
      expect(surface.backIndices, isNotEmpty);
      expect(surface.lift, greaterThan(0.9));

      // Along the leading row the x positions must turn around at the roll.
      var advanced = false;
      var returned = false;
      var previous = vertexAt(surface, 0).dx;
      for (var i = 1; i <= 34; i++) {
        final x = vertexAt(surface, i).dx;
        if (x > previous) advanced = true;
        if (advanced && x < previous) returned = true;
        previous = x;
      }
      expect(returned, isTrue);
    });

    test('a backward turn mirrors the geometry around the other edge', () {
      final forward = surfaceAt(0.4);
      final backward = surfaceAt(0.4, pivotOnLeft: false);

      for (var i = 0; i < forward.positions.length; i += 2) {
        final mirrored = rect.left + rect.right - forward.positions[i];
        expect(backward.positions[i], closeTo(mirrored, 0.001));
        expect(
          backward.positions[i + 1],
          closeTo(forward.positions[i + 1], 0.001),
        );
      }
    });

    test('paper darkens as it turns away from the light', () {
      final surface = surfaceAt(0.5);
      var brightest = 0;
      var darkest = 255;
      for (final color in surface.colors) {
        final level = color & 0xFF;
        brightest = math.max(brightest, level);
        darkest = math.min(darkest, level);
      }

      expect(darkest, lessThan(brightest));
      expect(darkest, greaterThan(120));
    });

    test('opacity reaches the mesh so a lone leaf can dissolve', () {
      final surface = buildPageCurlSurface(
        rect: rect,
        progress: 0.5,
        pivotOnLeft: true,
        leadFromBottom: true,
        opacity: 0.4,
      );

      for (final color in surface.colors) {
        expect((color >> 24) & 0xFF, closeTo(102, 1));
      }
    });

    test('texture coordinates stay normalised across the sheet', () {
      final surface = surfaceAt(0.7);

      for (var i = 0; i < surface.textureCoordinates.length; i++) {
        expect(surface.textureCoordinates[i], inInclusiveRange(0, 1));
      }
    });
  });
}
