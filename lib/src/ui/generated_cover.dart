import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Stands in for missing cover art: seven waveform bars shaped like the launcher icon's, in one
/// of the [CoverPalette] colors. The same [seed] always draws the same cover, so a song keeps
/// its look everywhere it appears.
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({super.key, required this.seed});

  final String seed;

  @override
  Widget build(BuildContext context) {
    final hash = stableHash(seed);
    final (background, bars) = CoverPalette.of(context).pick(hash);
    return CustomPaint(painter: _CoverPainter(hash, background, bars), child: const SizedBox.expand());
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.hash, this.background, this.bars);

  final int hash;
  final Color background;
  final Color bars;

  /// Tallest in the middle, like the icon. Each bar then gets a random share of its height.
  static const _envelope = [0.4, 0.62, 0.86, 1.0, 0.8, 0.6, 0.38];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final width = size.width;
    final barWidth = width * 0.066;
    final gap = width * 0.048;
    final total = _envelope.length * barWidth + (_envelope.length - 1) * gap;
    final centerY = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    var state = hash == 0 ? 0x9e3779b9 : hash;
    var x = (width - total) / 2 + barWidth / 2;
    for (var i = 0; i < _envelope.length; i++) {
      // xorshift32: a tiny deterministic generator.
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      final random = (state & 0xffff) / 0xffff;
      final height = size.height * 0.6 * _envelope[i] * (0.5 + 0.5 * random);
      final half = math.max(0.0, height - barWidth) / 2;
      // The two outer bars on each side are fainter, as in the icon.
      paint.color = i < 2 || i > 4 ? bars.withValues(alpha: 0.5) : bars;
      canvas.drawLine(Offset(x, centerY - half), Offset(x, centerY + half), paint);
      x += barWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.hash != hash || old.background != background || old.bars != bars;
}
