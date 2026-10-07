import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum _Handle { start, end }

/// Waveform overview with two draggable handles marking the part to keep.
/// Drag a handle, or tap anywhere to move the closest handle there.
class WaveformSelector extends StatefulWidget {
  const WaveformSelector({
    super.key,
    required this.levels,
    required this.durationMs,
    required this.startMs,
    required this.endMs,
    required this.playheadMs,
    required this.onStartChanged,
    required this.onEndChanged,
    this.height = 168,
  });

  final Float64List? levels;
  final int durationMs;
  final int startMs;
  final int endMs;
  final int? playheadMs;
  final ValueChanged<int> onStartChanged;
  final ValueChanged<int> onEndChanged;
  final double height;

  /// Horizontal padding so the handles stay fully visible at both ends.
  static const inset = 14.0;

  @override
  State<WaveformSelector> createState() => _WaveformSelectorState();
}

class _WaveformSelectorState extends State<WaveformSelector> {
  _Handle? _dragging;

  double _xFor(int ms, double width) =>
      WaveformSelector.inset + (width - 2 * WaveformSelector.inset) * (ms / widget.durationMs);

  int _msFor(double x, double width) {
    final usable = width - 2 * WaveformSelector.inset;
    final fraction = ((x - WaveformSelector.inset) / usable).clamp(0.0, 1.0);
    return (fraction * widget.durationMs).round();
  }

  _Handle _closest(double x, double width) {
    final toStart = (x - _xFor(widget.startMs, width)).abs();
    final toEnd = (x - _xFor(widget.endMs, width)).abs();
    if (toStart != toEnd) return toStart < toEnd ? _Handle.start : _Handle.end;
    // Handles on top of each other: pick based on which side the finger is.
    return x > _xFor(widget.endMs, width) ? _Handle.end : _Handle.start;
  }

  void _move(_Handle handle, double x, double width) {
    final ms = _msFor(x, width);
    handle == _Handle.start ? widget.onStartChanged(ms) : widget.onEndChanged(ms);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _dragging = _closest(d.localPosition.dx, width),
          onHorizontalDragUpdate: (d) {
            final handle = _dragging;
            if (handle != null) _move(handle, d.localPosition.dx, width);
          },
          onHorizontalDragEnd: (_) => _dragging = null,
          onTapUp: (d) => _move(_closest(d.localPosition.dx, width), d.localPosition.dx, width),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CustomPaint(
              size: Size(width, widget.height),
              painter: _WaveformPainter(
                levels: widget.levels,
                durationMs: widget.durationMs,
                startMs: widget.startMs,
                endMs: widget.endMs,
                playheadMs: widget.playheadMs,
                background: colors.surfaceContainerHighest,
                selection: colors.primary.withValues(alpha: 0.12),
                barInside: colors.primary,
                barOutside: colors.onSurfaceVariant.withValues(alpha: 0.35),
                handle: colors.primary,
                handleKnob: colors.onPrimary,
                playhead: colors.tertiary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.levels,
    required this.durationMs,
    required this.startMs,
    required this.endMs,
    required this.playheadMs,
    required this.background,
    required this.selection,
    required this.barInside,
    required this.barOutside,
    required this.handle,
    required this.handleKnob,
    required this.playhead,
  });

  final Float64List? levels;
  final int durationMs;
  final int startMs;
  final int endMs;
  final int? playheadMs;
  final Color background;
  final Color selection;
  final Color barInside;
  final Color barOutside;
  final Color handle;
  final Color handleKnob;
  final Color playhead;

  static const _barWidth = 3.0;
  static const _barGap = 2.0;
  static const _verticalPadding = 22.0;
  static const _knobRadius = 8.0;
  static const _serif = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = WaveformSelector.inset;
    final usable = size.width - 2 * inset;
    double xFor(int ms) => inset + usable * (ms / durationMs);
    final startX = xFor(startMs);
    final endX = xFor(endMs);
    final centerY = size.height / 2;

    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    canvas.drawRect(Rect.fromLTRB(startX, 0, endX, size.height), Paint()..color = selection);

    // Bars: each one shows the loudest slice it covers, scaled to the loudest slice overall.
    final data = levels;
    var maxLevel = 0.0;
    if (data != null) {
      for (final v in data) {
        if (v > maxLevel) maxLevel = v;
      }
    }
    final barCount = math.max(1, ((usable + _barGap) / (_barWidth + _barGap)).floor());
    final step = usable / barCount;
    final maxBarHeight = size.height - 2 * _verticalPadding;
    final barPaint = Paint()
      ..strokeWidth = _barWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < barCount; i++) {
      var level = 0.0;
      if (data != null && data.isNotEmpty && maxLevel > 0) {
        final from = (i * data.length / barCount).floor();
        final to = math.max(from + 1, ((i + 1) * data.length / barCount).floor());
        for (var j = from; j < to && j < data.length; j++) {
          if (data[j] > level) level = data[j];
        }
        level /= maxLevel;
      }
      final x = inset + (i + 0.5) * step;
      final half = math.max(0.0, level * maxBarHeight - _barWidth) / 2;
      barPaint.color = x >= startX && x <= endX ? barInside : barOutside;
      canvas.drawLine(Offset(x, centerY - half), Offset(x, centerY + half), barPaint);
    }

    // Handles: brackets around the kept part, like the launcher icon, with a grip in the middle.
    final bracket = Paint()
      ..color = handle
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const top = 6.0;
    final bottom = size.height - 6;
    for (final (x, inward) in [(startX, _serif), (endX, -_serif)]) {
      canvas.drawPath(
        Path()
          ..moveTo(x + inward, top)
          ..lineTo(x, top)
          ..lineTo(x, bottom)
          ..lineTo(x + inward, bottom),
        bracket,
      );
      final grip = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, centerY), width: _knobRadius * 1.6, height: _knobRadius * 4.4),
        const Radius.circular(_knobRadius),
      );
      canvas.drawRRect(grip, Paint()..color = handle);
      canvas.drawLine(
        Offset(x, centerY - _knobRadius),
        Offset(x, centerY + _knobRadius),
        Paint()
          ..color = handleKnob
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    final position = playheadMs;
    if (position != null) {
      final x = xFor(position.clamp(0, durationMs));
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = playhead
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.levels != levels ||
      old.durationMs != durationMs ||
      old.startMs != startMs ||
      old.endMs != endMs ||
      old.playheadMs != playheadMs ||
      old.background != background ||
      old.barInside != barInside;
}
