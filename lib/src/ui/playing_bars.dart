import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Three bouncing bars marking the song that's playing. They rest when it's paused.
class PlayingBars extends StatefulWidget {
  const PlayingBars({super.key, required this.playing, required this.color, this.size = 18});

  final bool playing;
  final Color color;
  final double size;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _BarsPainter(_controller.value, widget.playing, widget.color),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.t, this.playing, this.color);

  final double t;
  final bool playing;
  final Color color;

  // Whole numbers of cycles per loop, so the animation repeats without a jump.
  static const _speeds = [2, 3, 2];
  static const _phases = [0.0, 1.9, 3.7];
  static const _resting = [0.45, 0.85, 0.6];

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width * 0.22;
    final gap = (size.width - 3 * barWidth) / 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < 3; i++) {
      final level = playing ? 0.3 + 0.7 * (0.5 + 0.5 * math.sin(2 * math.pi * _speeds[i] * t + _phases[i])) : _resting[i];
      final height = size.height * level;
      final x = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - height, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.t != t || old.playing != playing || old.color != color;
}
