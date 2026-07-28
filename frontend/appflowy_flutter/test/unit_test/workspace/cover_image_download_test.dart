import 'dart:typed_data';

import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/cover_image_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D]);
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

  group('DownloadableCoverImage.fromPageStyleCover', () {
    test('has nothing to save for absent, colour or gradient covers', () {
      expect(DownloadableCoverImage.fromPageStyleCover(null), isNull);
      expect(
        DownloadableCoverImage.fromPageStyleCover(const PageStyleCover.none()),
        isNull,
      );
      expect(
        DownloadableCoverImage.fromPageStyleCover(
          const PageStyleCover(
            type: PageStyleCoverImageType.pureColor,
            value: '0xffe8e0ff',
          ),
        ),
        isNull,
      );
      expect(
        DownloadableCoverImage.fromPageStyleCover(
          const PageStyleCover(
            type: PageStyleCoverImageType.gradientColor,
            value: '1',
          ),
        ),
        isNull,
      );
      expect(
        DownloadableCoverImage.fromPageStyleCover(
          const PageStyleCover(
            type: PageStyleCoverImageType.customImage,
            value: '',
          ),
        ),
        isNull,
      );
    });

    test('reads a built-in cover from the asset bundle', () {
      final cover = DownloadableCoverImage.fromPageStyleCover(
        const PageStyleCover(
          type: PageStyleCoverImageType.builtInImage,
          value: '3',
        ),
      );

      expect(cover?.storage, CoverImageStorage.asset);
      expect(cover?.value, PageStyleCoverImageType.builtInImagePath('3'));
    });

    test('keeps local covers on disk and hosted covers on the network', () {
      expect(
        DownloadableCoverImage.fromPageStyleCover(
          const PageStyleCover(
            type: PageStyleCoverImageType.localImage,
            value: r'C:\images\cover.png',
          ),
        )?.storage,
        CoverImageStorage.local,
      );
      expect(
        DownloadableCoverImage.fromPageStyleCover(
          const PageStyleCover(
            type: PageStyleCoverImageType.unsplashImage,
            value: 'https://images.unsplash.com/photo-1',
          ),
        )?.storage,
        CoverImageStorage.remote,
      );
    });

    test('a custom cover may be either a url or a stored file', () {
      expect(
        DownloadableCoverImage.fromPageStyleCover(
          const PageStyleCover(
            type: PageStyleCoverImageType.customImage,
            value: 'https://workspace.example/files/abc',
          ),
        )?.storage,
        CoverImageStorage.remote,
      );
      expect(
        DownloadableCoverImage.fromPageStyleCover(
          const PageStyleCover(
            type: PageStyleCoverImageType.customImage,
            value: '/home/me/.appflowy/images/abc.jpg',
          ),
        )?.storage,
        CoverImageStorage.local,
      );
    });
  });

  group('DownloadableCoverImage.fileNameFor', () {
    test('keeps the stored name when it already carries an extension', () {
      expect(
        const DownloadableCoverImage.remote(
          'https://workspace.example/files/sunset.jpeg?token=1',
        ).fileNameFor(png),
        'sunset.jpeg',
      );
    });

    test('names an extension-less source after the actual payload', () {
      expect(
        const DownloadableCoverImage.remote(
          'https://workspace.example/files/abc123',
        ).fileNameFor(png),
        'abc123.png',
      );
      expect(
        const DownloadableCoverImage.remote(
          'https://workspace.example/files/abc123',
        ).fileNameFor(jpeg),
        'abc123.jpg',
      );
    });

    test('falls back to a generic name when the source has no basename', () {
      expect(
        const DownloadableCoverImage.remote('https://workspace.example')
            .fileNameFor(png),
        'appflowy-cover.png',
      );
    });
  });
}
