import 'package:appflowy/shared/cover_image_decode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decode follows actual constraints and DPR, not requested infinity', () {
    final target = CoverImageDecodeSize.fromConstraints(
      const BoxConstraints.tightFor(width: 720, height: 200),
      2,
      width: double.infinity,
      height: double.infinity,
    )!;
    expect(target.width, 1536);
    expect(target.height, 512);
  });

  test('hero and tiny thumbnail use independent physical pixel buckets', () {
    final hero = CoverImageDecodeSize.fromConstraints(
      const BoxConstraints.tightFor(width: 720, height: 200),
      2,
    )!;
    final thumbnail = CoverImageDecodeSize.fromConstraints(
      const BoxConstraints.tightFor(width: 44, height: 32),
      2,
    )!;
    expect(thumbnail.width, 96);
    expect(thumbnail.height, 64);
    expect(thumbnail, isNot(hero));
    final decoded = thumbnail.target(6000, 4000, BoxFit.cover);
    expect((decoded.width, decoded.height), (96, 64));
  });

  test('one pixel resize within a bucket keeps equal decode/cache keys', () {
    CoverImageDecodeSize size(double width) =>
        CoverImageDecodeSize.fromConstraints(
          BoxConstraints.tightFor(width: width, height: 200),
          2,
        )!;
    expect(size(701), size(702));
    const source = AssetImage('cover.png');
    expect(CoverImageProvider(source, size(701), BoxFit.cover),
        CoverImageProvider(source, size(702), BoxFit.cover));
    expect(size(768), isNot(size(769)));
    expect(CoverImageKey('source', size(701), BoxFit.cover),
        isNot(CoverImageKey('source', size(701), BoxFit.contain)));
  });

  test('contain and crop use the encoded aspect, stretch remains a paint fit',
      () {
    const target = CoverImageDecodeSize(1024, 256);
    final contain = target.target(6000, 4000, BoxFit.contain);
    final crop = target.target(6000, 4000, BoxFit.cover);
    final stretch = target.target(6000, 4000, BoxFit.fill);
    expect((contain.width, contain.height), (384, 256));
    expect((crop.width, crop.height), (1024, 683));
    expect((stretch.width, stretch.height), (crop.width, crop.height));
    expect(crop.width! / crop.height!, closeTo(1.5, .003));
  });

  test('portrait crop preserves sufficient pixels on both visible axes', () {
    const target = CoverImageDecodeSize(768, 256);
    final result = target.target(2000, 4000, BoxFit.cover);
    expect((result.width, result.height), (768, 1536));
  });

  test('exact rational targets do not gain pixels from floating point ceil',
      () {
    const size = CoverImageDecodeSize(640, 224);
    for (final fit in [BoxFit.contain, BoxFit.scaleDown, BoxFit.fitHeight]) {
      final result = size.target(1200, 800, fit);
      expect((result.width, result.height), (336, 224));
    }
    final crop = size.target(1200, 800, BoxFit.cover);
    expect((crop.width, crop.height), (640, 427));
    final portrait =
        const CoverImageDecodeSize(224, 640).target(800, 1200, BoxFit.contain);
    expect((portrait.width, portrait.height), (224, 336));
  });

  test('decode never enlarges a tiny encoded image', () {
    for (final fit in [BoxFit.contain, BoxFit.cover, BoxFit.fill]) {
      final result = const CoverImageDecodeSize(2048, 640).target(2, 1, fit);
      expect((result.width, result.height), (2, 1));
    }
  });

  test('all fits cap each decoded dimension at 4096, including panoramas', () {
    for (final source in [(50000, 500), (500, 50000), (9000, 9000)]) {
      for (final fit in BoxFit.values) {
        final result = const CoverImageDecodeSize(4096, 4096)
            .target(source.$1, source.$2, fit);
        expect(result.width, inInclusiveRange(1, 4096));
        expect(result.height, inInclusiveRange(1, 4096));
        expect(result.width! / result.height!,
            closeTo(source.$1 / source.$2, 2.5));
      }
    }
  });

  test('invalid or unbounded layouts do not invent a screen-sized target', () {
    for (final constraints in [
      const BoxConstraints(),
      const BoxConstraints.tightFor(width: 0, height: 200)
    ]) {
      expect(CoverImageDecodeSize.fromConstraints(constraints, 2), isNull);
    }
    for (final dpr in [0.0, double.nan, double.infinity]) {
      expect(
          CoverImageDecodeSize.fromConstraints(
            const BoxConstraints.tightFor(width: 100, height: 100),
            dpr,
          ),
          isNull);
    }
    final huge = CoverImageDecodeSize.fromConstraints(
      const BoxConstraints.tightFor(width: 1e20, height: 1e20),
      100,
    )!;
    expect((huge.width, huge.height), (4096, 4096));
  });
}
