import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A cover that opens like a real book.
///
/// The leaf is not faded and it is not slid: it is rotated about the spine in
/// perspective, gathers a shadow as it lifts and lets the page beneath show
/// through — the same physical reading a PDF page turn gives, reduced to the
/// one hinge a cover actually has.
///
/// Left-hinged by default (a western book opens on its right edge); pass
/// [hinge] to open the other way.
class CoverFlip extends StatelessWidget {
  const CoverFlip({
    super.key,
    required this.progress,
    required this.cover,
    required this.contents,
    this.hinge = CoverFlipHinge.left,
    this.spineColor,
  });

  /// 0 = closed (cover facing the reader), 1 = fully open.
  final double progress;
  final Widget cover;
  final Widget contents;
  final CoverFlipHinge hinge;
  final Color? spineColor;

  /// How far past flat the leaf swings. A cover that stops at exactly 90°
  /// disappears edge on; carrying it a little past hides the seam.
  static const double _sweep = math.pi * 0.995;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    final angle = _sweep * Curves.easeInOutCubic.transform(t);
    final leftHinged = hinge == CoverFlipHinge.left;
    // Past a quarter turn the leaf is edge on and the contents are what the
    // reader is looking at, so the cover stops taking the pointer.
    final coverFacing = angle < math.pi / 2;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The contents are always mounted, so opening never costs a rebuild
        // of the index and the reader can start reading before the leaf lands.
        Opacity(opacity: t < 0.5 ? 0 : 1, child: contents),
        // A page edge peeking out from under the cover: it is what makes a
        // closed cover read as a book rather than as a picture.
        if (t < 0.98)
          Positioned(
            top: 6,
            bottom: 6,
            left: leftHinged ? null : 0,
            right: leftHinged ? 0 : null,
            width: 5 + 3 * t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF2EDE3),
                borderRadius: BorderRadius.horizontal(
                  left: leftHinged ? Radius.zero : const Radius.circular(2),
                  right: leftHinged ? const Radius.circular(2) : Radius.zero,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
          ),
        IgnorePointer(
          ignoring: !coverFacing,
          child: Transform(
            alignment:
                leftHinged ? Alignment.centerLeft : Alignment.centerRight,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(leftHinged ? -angle : angle),
            child: Opacity(
              // The last sliver of the swing dissolves so the leaf never
              // parks as a hairline over the first page.
              opacity: t > 0.94 ? (1 - (t - 0.94) / 0.06).clamp(0.0, 1.0) : 1,
              child: _CoverLeaf(
                facing: coverFacing,
                lift: math.sin(angle).abs(),
                leftHinged: leftHinged,
                spineColor: spineColor,
                child: cover,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum CoverFlipHinge { left, right }

class _CoverLeaf extends StatelessWidget {
  const _CoverLeaf({
    required this.child,
    required this.facing,
    required this.lift,
    required this.leftHinged,
    required this.spineColor,
  });

  final Widget child;
  final bool facing;
  final double lift;
  final bool leftHinged;
  final Color? spineColor;

  @override
  Widget build(BuildContext context) {
    final spine = spineColor ?? const Color(0xFF2B2118);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10 + 0.26 * lift),
            blurRadius: 8 + 26 * lift,
            offset: Offset(leftHinged ? 8 * lift : -8 * lift, 4 + 8 * lift),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Only the front of the leaf carries artwork. Its back is the
            // inside of the cover — board, not a mirrored picture.
            if (facing)
              child
            else
              ColoredBox(color: Color.lerp(spine, Colors.white, 0.12)!),
            // The board darkens towards the spine, which is where the light
            // never reaches on a real book.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: leftHinged
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    end: leftHinged
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    colors: [
                      Colors.black.withValues(alpha: 0.24),
                      Colors.black.withValues(alpha: 0.04),
                      Colors.black.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.10, 0.34],
                  ),
                ),
              ),
            ),
            // Lifting the leaf brings the room's light across it.
            IgnorePointer(
              child: Opacity(
                opacity: lift * 0.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.black.withValues(alpha: 0.16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The generated cover a book gets when it has no artwork of its own.
///
/// A tinted board with the title set on it reads as a book; a grey rectangle
/// with a folder glyph does not.
class GeneratedBookCover extends StatelessWidget {
  const GeneratedBookCover({
    super.key,
    required this.title,
    required this.hue,
    this.author,
    this.dark = false,
  });

  final String title;
  final String? author;
  final Color hue;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final board = Color.lerp(hue, dark ? Colors.black : Colors.white, 0.14)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = (width / 168).clamp(0.5, 1.6);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(board, Colors.white, 0.10)!,
                Color.lerp(board, Colors.black, 0.16)!,
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16 * scale,
              18 * scale,
              14 * scale,
              14 * scale,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22 * scale,
                  height: 2,
                  color: Colors.white.withValues(alpha: 0.62),
                ),
                SizedBox(height: 12 * scale),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.96),
                      fontSize: 15 * scale,
                      height: 1.22,
                      letterSpacing: -0.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (author != null && author!.isNotEmpty)
                  Text(
                    author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 10 * scale,
                      letterSpacing: 0.4,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
