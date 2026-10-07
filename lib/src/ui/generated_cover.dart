import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The drawings a generated cover can have. [bars] is the default (the launcher icon's motif);
/// the others can be picked as a playlist's cover.
enum CoverStyle { bars, waves, rings, halftone, sunset, shapes }

/// A generated cover: a [style] and a [seed] that picks its colors and variations.
@immutable
class CoverDesign {
  const CoverDesign(this.style, this.seed);

  final CoverStyle style;
  final String seed;

  /// "waves:1234", as stored in playlists.json.
  String encode() => '${style.name}:$seed';

  static CoverDesign? decode(String? value) {
    if (value == null) return null;
    final split = value.indexOf(':');
    if (split < 0) return null;
    final style = CoverStyle.values.asNameMap()[value.substring(0, split)];
    return style == null ? null : CoverDesign(style, value.substring(split + 1));
  }

  @override
  bool operator ==(Object other) => other is CoverDesign && other.style == style && other.seed == seed;

  @override
  int get hashCode => Object.hash(style, seed);
}

/// Stands in for missing cover art: by default seven waveform bars shaped like the launcher
/// icon's, in one of the [CoverPalette] colors. The same [seed] always draws the same cover, so
/// a song keeps its look everywhere it appears.
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({super.key, required this.seed, this.style = CoverStyle.bars});

  GeneratedCover.design(CoverDesign design, {Key? key}) : this(key: key, seed: design.seed, style: design.style);

  final String seed;
  final CoverStyle style;

  @override
  Widget build(BuildContext context) {
    final hash = stableHash(seed);
    final palette = CoverPalette.of(context);
    final (background, foreground) = palette.pick(hash);
    // A second hue, half the color wheel away, for the two-color designs.
    final (other, _) = palette.pick(hash + palette.swatches.length ~/ 2);
    return CustomPaint(
      painter: _CoverPainter(style, hash, background, foreground, other),
      child: const SizedBox.expand(),
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.style, this.hash, this.background, this.foreground, this.other);

  final CoverStyle style;
  final int hash;
  final Color background;
  final Color foreground;
  final Color other;

  /// Tallest in the middle, like the icon. Each bar then gets a random share of its height.
  static const _envelope = [0.4, 0.62, 0.86, 1.0, 0.8, 0.6, 0.38];

  late int _state;

  /// xorshift32: a tiny deterministic generator. Returns 0..1.
  double _random() {
    _state ^= (_state << 13) & 0xffffffff;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0xffffffff;
    return (_state & 0xffff) / 0xffff;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _state = hash == 0 ? 0x9e3779b9 : hash;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (style) {
      case CoverStyle.bars:
        _bars(canvas, size);
      case CoverStyle.waves:
        _waves(canvas, size);
      case CoverStyle.rings:
        _rings(canvas, size);
      case CoverStyle.halftone:
        _halftone(canvas, size);
      case CoverStyle.sunset:
        _sunset(canvas, size);
      case CoverStyle.shapes:
        _shapes(canvas, size);
    }
    canvas.restore();
  }

  void _bars(Canvas canvas, Size size) {
    final width = size.width;
    final barWidth = width * 0.066;
    final gap = width * 0.048;
    final total = _envelope.length * barWidth + (_envelope.length - 1) * gap;
    final centerY = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;
    var x = (width - total) / 2 + barWidth / 2;
    for (var i = 0; i < _envelope.length; i++) {
      final height = size.height * 0.6 * _envelope[i] * (0.5 + 0.5 * _random());
      final half = math.max(0.0, height - barWidth) / 2;
      // The two outer bars on each side are fainter, as in the icon.
      paint.color = i < 2 || i > 4 ? foreground.withValues(alpha: 0.5) : foreground;
      canvas.drawLine(Offset(x, centerY - half), Offset(x, centerY + half), paint);
      x += barWidth + gap;
    }
  }

  /// Stacked sine bands, darkest at the bottom.
  void _waves(Canvas canvas, Size size) {
    const bands = 5;
    final frequency = 1 + _random() * 1.5;
    final phase = _random() * math.pi * 2;
    for (var b = 0; b < bands; b++) {
      final baseY = size.height * (0.3 + b * 0.16);
      final amplitude = size.height * (0.05 + 0.04 * _random());
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width; x += size.width / 48) {
        final t = x / size.width * math.pi * 2 * frequency + phase + b * 0.9;
        path.lineTo(x, baseY + math.sin(t) * amplitude);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      final color = b.isEven ? foreground : other;
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.35 + 0.65 * b / (bands - 1)));
    }
  }

  /// Ripples from a point off the center, like a dropped stone (or a record).
  void _rings(Canvas canvas, Size size) {
    final center = Offset(size.width * (0.25 + _random() * 0.5), size.height * (0.25 + _random() * 0.5));
    final step = size.shortestSide * (0.07 + _random() * 0.03);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = step * 0.42;
    final maxRadius = size.longestSide * 1.5;
    var i = 0;
    for (var r = step; r < maxRadius; r += step, i++) {
      paint.color = (i % 3 == 2 ? other : foreground).withValues(alpha: math.max(0.18, 1 - r / maxRadius * 1.4));
      canvas.drawCircle(center, r, paint);
    }
    canvas.drawCircle(center, step * 0.5, Paint()..color = foreground);
  }

  /// A grid of dots whose size follows a diagonal wave.
  void _halftone(Canvas canvas, Size size) {
    const count = 9;
    final cell = size.width / count;
    final angle = _random() * math.pi;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final frequency = 0.6 + _random() * 0.6;
    final paint = Paint();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        final center = Offset((col + 0.5) * cell, (row + 0.5) * cell * size.height / size.width);
        final along = (col * direction.dx + row * direction.dy) * frequency;
        final level = (math.sin(along) + 1) / 2;
        paint.color = level > 0.75 ? other : foreground;
        canvas.drawCircle(center, cell * (0.08 + 0.36 * level), paint);
      }
    }
  }

  /// A retro sun cut by horizontal stripes, over a horizon.
  void _sunset(Canvas canvas, Size size) {
    final radius = size.width * (0.3 + _random() * 0.08);
    final horizon = size.height * 0.72;
    final center = Offset(size.width / 2, horizon);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, horizon));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [foreground, other],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    // Stripes widen toward the horizon.
    var y = horizon - radius * 0.55;
    for (var gap = radius * 0.035; y < horizon; gap *= 1.45) {
      canvas.drawRect(Rect.fromLTRB(0, y, size.width, y + gap), Paint()..color = background);
      y += gap * 2.6;
    }
    canvas.restore();
    final ground = Paint()..color = foreground.withValues(alpha: 0.3);
    for (var i = 0; i < 4; i++) {
      final y = horizon + (size.height - horizon) * (i / 4) * (i / 4) + size.height * 0.02;
      canvas.drawRect(Rect.fromLTRB(0, y, size.width, y + size.height * 0.012 * (i + 1)), ground);
    }
  }

  /// Bold overlapping shapes: a circle, a half circle and a bar, placed by the seed.
  void _shapes(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawCircle(
      Offset(size.width * (0.3 + _random() * 0.4), size.height * (0.28 + _random() * 0.2)),
      s * (0.2 + _random() * 0.1),
      Paint()..color = other,
    );
    final arcCenter = Offset(size.width * (_random() < 0.5 ? 0.15 : 0.85), size.height * 0.92);
    canvas.drawCircle(arcCenter, s * 0.42, Paint()..color = foreground.withValues(alpha: 0.85));
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate((_random() - 0.5) * math.pi / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: s * 1.2, height: s * 0.11), Radius.circular(s)),
      Paint()..color = foreground,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverPainter old) =>
      old.style != style ||
      old.hash != hash ||
      old.background != background ||
      old.foreground != foreground ||
      old.other != other;
}
