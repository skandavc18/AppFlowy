import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_edit_pipeline.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_edit_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_viewport.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const List<double> _identity = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

Future<ui.Image> _solidImage(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 120;
    pixels[i + 1] = 140;
    pixels[i + 2] = 160;
    pixels[i + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('colour matrix', () {
    test('is the identity when nothing is adjusted', () {
      final matrix = buildColorMatrix(
        ImageAdjustments.none,
        ImageFilterPreset.none,
      );
      for (var i = 0; i < matrix.length; i++) {
        expect(matrix[i], closeTo(_identity[i], 1e-9));
      }
    });

    test('brightness only shifts the offset column', () {
      final matrix = buildColorMatrix(
        const ImageAdjustments(brightness: 0.5),
        ImageFilterPreset.none,
      );
      expect(matrix[0], closeTo(1, 1e-9));
      expect(matrix[4], greaterThan(0));
      expect(matrix[9], closeTo(matrix[4], 1e-9));
      expect(matrix[14], closeTo(matrix[4], 1e-9));
    });

    test('monochrome collapses the channels onto luminance', () {
      final matrix = buildColorMatrix(
        ImageAdjustments.none,
        ImageFilterPreset.monochrome,
      );
      // Every output row reads the same weights when saturation is removed.
      expect(matrix[0], closeTo(matrix[5], 1e-6));
      expect(matrix[1], closeTo(matrix[6], 1e-6));
      expect(matrix[2], closeTo(matrix[7], 1e-6));
    });
  });

  group('geometry', () {
    test('a quarter turn swaps the oriented size', () {
      final geometry = ImageEditGeometry(
        imageSize: const Size(400, 200),
        transform: const ImageTransform(quarterTurns: 1),
      );
      expect(geometry.orientedSize, const Size(200, 400));
      expect(geometry.outputSize, const Size(200, 400));
    });

    test('cropping shrinks the output', () {
      final geometry = ImageEditGeometry(
        imageSize: const Size(400, 200),
        transform: const ImageTransform(
          crop: Rect.fromLTRB(0.25, 0, 0.75, 0.5),
        ),
      );
      expect(geometry.outputSize, const Size(200, 100));
    });

    test('output coordinates map back onto the source for every rotation', () {
      const imageSize = Size(400, 200);
      for (final turns in [0, 1, 2, 3]) {
        final geometry = ImageEditGeometry(
          imageSize: imageSize,
          transform: ImageTransform(quarterTurns: turns),
        );
        final topLeft = geometry.outputToImage(Offset.zero);
        final bottomRight = geometry.outputToImage(const Offset(1, 1));
        // The two opposite corners of the frame must still be opposite corners
        // of the source, whatever the rotation is.
        final mapped = Rect.fromPoints(topLeft, bottomRight);
        expect(mapped.width, closeTo(imageSize.width, 1e-6));
        expect(mapped.height, closeTo(imageSize.height, 1e-6));
      }
    });

    test('flipping mirrors the mapped point', () {
      const imageSize = Size(400, 200);
      final geometry = ImageEditGeometry(
        imageSize: imageSize,
        transform: const ImageTransform(flipHorizontal: true),
      );
      expect(geometry.outputToImage(Offset.zero).dx, closeTo(400, 1e-6));
      expect(geometry.outputToImage(const Offset(1, 0)).dx, closeTo(0, 1e-6));
    });
  });

  group('crop presets', () {
    test('a square crop is centred inside a landscape frame', () {
      final crop = ImageEditorViewportState.centeredCropForRatio(
        const Size(400, 200),
        1,
      );
      expect(crop.width, closeTo(0.5, 1e-6));
      expect(crop.height, closeTo(1, 1e-6));
      expect(crop.left, closeTo(0.25, 1e-6));
    });

    test('a free crop covers the whole frame', () {
      expect(
        ImageEditorViewportState.centeredCropForRatio(
          const Size(400, 200),
          null,
        ),
        const Rect.fromLTRB(0, 0, 1, 1),
      );
    });
  });

  group('settings', () {
    test('a fresh edit is pristine', () {
      expect(ImageEditSettings.pristine.isPristine, isTrue);
    });

    test('any change makes it dirty', () {
      expect(
        ImageEditSettings.pristine
            .copyWith(
              adjustments: const ImageAdjustments(contrast: 0.2),
            )
            .isPristine,
        isFalse,
      );
      expect(
        ImageEditSettings.pristine
            .copyWith(filter: ImageFilterPreset.warm)
            .isPristine,
        isFalse,
      );
    });

    test('unipolar adjustments cannot go negative', () {
      final adjustments =
          ImageAdjustments.none.withValue(ImageAdjustment.blur, -1);
      expect(adjustments.blur, 0);
    });

    test('rotating resets the crop window', () {
      const transform = ImageTransform(crop: Rect.fromLTRB(0.2, 0.2, 0.8, 0.8));
      expect(transform.rotated(1).crop, const Rect.fromLTRB(0, 0, 1, 1));
      expect(transform.rotated(1).quarterTurns, 1);
      expect(transform.rotated(-1).quarterTurns, 3);
    });
  });

  test('rendering honours the crop', () async {
    final source = await _solidImage(200, 100);
    final bytes = await encodeEditedImage(
      source,
      const ImageEditSettings(
        transform: ImageTransform(crop: Rect.fromLTRB(0, 0, 0.5, 1)),
      ),
    );
    expect(bytes, isNotEmpty);

    final decoded = await ui.instantiateImageCodec(bytes);
    final frame = await decoded.getNextFrame();
    expect(frame.image.width, 100);
    expect(frame.image.height, 100);
    frame.image.dispose();
    decoded.dispose();
    source.dispose();
  });

  group('clipboard payloads', () {
    test('reads the format from the magic number', () {
      expect(
        sniffImageFormat(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0])),
        'png',
      );
      expect(
        sniffImageFormat(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
        'jpeg',
      );
      expect(
        sniffImageFormat(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])),
        'gif',
      );
      expect(sniffImageFormat(Uint8List.fromList([1, 2, 3, 4])), isNull);
      expect(sniffImageFormat(Uint8List(0)), isNull);
    });

    test('maps a format onto a file extension', () {
      expect(imageExtensionFor('png'), 'png');
      expect(imageExtensionFor('jpeg'), 'jpg');
      expect(imageExtensionFor('gif'), 'gif');
      expect(imageExtensionFor(null), 'png');
    });

    test('hands an already supported payload over untouched', () async {
      final source = await _solidImage(24, 24);
      final bytes = await encodeEditedImage(
        source,
        ImageEditSettings.pristine,
      );
      final clipboard = await encodeForClipboard(bytes);

      expect(clipboard.$1, 'png');
      expect(identical(clipboard.$2, bytes), isTrue);
      source.dispose();
    });
  });
}
