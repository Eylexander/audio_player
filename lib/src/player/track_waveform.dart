import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../formatting.dart';
import '../native_bridge.dart';
import 'player_controller.dart';

/// Loudness overview of the playing track, drawn as the now-playing seek bar. It's decoded
/// natively in its own slot (the cutter's waveform is never interrupted) in the background as
/// soon as a track starts, so it's ready when the now-playing screen opens. The last few tracks
/// are kept.
class TrackWaveforms {
  TrackWaveforms._() {
    NativeBridge.events.listen(_onEvent);
    PlayerController.instance.addListener(_follow);
    _follow();
  }

  /// Starts following the player. Called once at startup.
  static void init() => instance;

  static final instance = TrackWaveforms._();

  static const _buckets = 240;
  static const _maxCached = 40;
  static int _lastToken = 0;

  final _cache = <String, Float64List>{};

  /// Levels of the track being shown. Null until the first decoded chunk arrives.
  final levels = ValueNotifier<Float64List?>(null);

  String? _uri;

  /// Negative, so it can never match one of the editor's tokens. 0 when nothing is decoding.
  int _token = 0;

  void _follow() {
    final s = PlayerController.instance.state;
    final uri = s.uri;
    final duration = s.durationMs ?? 0;
    if (uri != null && duration > 0) _show(uri, duration);
  }

  void _show(String uri, int durationMs) {
    if (uri == _uri) return;
    _uri = uri;
    final cached = _cache.remove(uri);
    if (cached != null) {
      _cache[uri] = cached;
      if (_token != 0) NativeBridge.cancelWaveform(slot: 'player').catchError((_) {});
      _token = 0;
      levels.value = cached;
      return;
    }
    levels.value = null;
    _token = --_lastToken;
    NativeBridge.startWaveform(uri, durationMs: durationMs, token: _token, buckets: _buckets, slot: 'player')
        .catchError((_) {});
  }

  void _onEvent(NativeEvent event) {
    switch (event) {
      case WaveformEvent(:final token, levels: final data) when token == _token && token != 0:
        levels.value = data;
      case WaveformDoneEvent(:final token) when token == _token && token != 0:
        final data = levels.value;
        final uri = _uri;
        if (data != null && uri != null) {
          _cache[uri] = data;
          if (_cache.length > _maxCached) _cache.remove(_cache.keys.first);
        }
        _token = 0;
      default:
    }
  }
}

/// The seek bar of the now-playing screen: the track's waveform, filled up to the position.
/// Drag or tap anywhere on it to seek.
class WaveformSeekBar extends StatefulWidget {
  const WaveformSeekBar({
    super.key,
    required this.levels,
    required this.positionMs,
    required this.durationMs,
    required this.onSeek,
    this.height = 64,
  });

  final Float64List? levels;
  final int positionMs;
  final int durationMs;
  final ValueChanged<int> onSeek;
  final double height;

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar> {
  /// Position under the finger while dragging.
  double? _dragFraction;

  /// Shown right after a seek until the player reports a position near it, so the bar doesn't
  /// jump back for a moment.
  int? _seekTargetMs;
  DateTime _seekTime = DateTime(0);

  void _seek(double fraction) {
    final ms = (fraction * widget.durationMs).round();
    _seekTargetMs = ms;
    _seekTime = DateTime.now();
    widget.onSeek(ms);
  }

  int get _shownMs {
    final drag = _dragFraction;
    if (drag != null) return (drag * widget.durationMs).round();
    final target = _seekTargetMs;
    if (target != null) {
      final settled = (widget.positionMs - target).abs() < 1500 ||
          DateTime.now().difference(_seekTime) > const Duration(milliseconds: 1200);
      if (!settled) return target;
      _seekTargetMs = null;
    }
    return widget.positionMs;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = widget.durationMs;
    final shownMs = math.max(0, math.min(_shownMs, duration));
    final fraction = duration > 0 ? shownMs / duration : 0.0;
    final timeStyle = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            double at(Offset p) => (p.dx / width).clamp(0.0, 1.0);
            const step = 10000;
            return Semantics(
              slider: true,
              label: 'Position',
              value: formatShort(shownMs),
              increasedValue: formatShort(math.min(duration, shownMs + step)),
              decreasedValue: formatShort(math.max(0, shownMs - step)),
              onIncrease: duration > 0 ? () => widget.onSeek(math.min(duration, shownMs + step)) : null,
              onDecrease: duration > 0 ? () => widget.onSeek(math.max(0, shownMs - step)) : null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: duration > 0 ? (d) => setState(() => _dragFraction = at(d.localPosition)) : null,
                onHorizontalDragUpdate: duration > 0 ? (d) => setState(() => _dragFraction = at(d.localPosition)) : null,
                onHorizontalDragEnd: duration > 0
                    ? (_) {
                        final target = _dragFraction;
                        setState(() => _dragFraction = null);
                        if (target != null) _seek(target);
                      }
                    : null,
                onTapUp: duration > 0 ? (d) => setState(() => _seek(at(d.localPosition))) : null,
                child: CustomPaint(
                  size: Size(width, widget.height),
                  painter: _SeekPainter(
                    levels: widget.levels,
                    fraction: fraction,
                    played: colors.primary,
                    remaining: colors.onSurfaceVariant.withValues(alpha: 0.28),
                    dragging: _dragFraction != null,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatShort(shownMs), style: timeStyle),
            Text(duration > 0 ? '-${formatShort(duration - shownMs)}' : '', style: timeStyle),
          ],
        ),
      ],
    );
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.levels,
    required this.fraction,
    required this.played,
    required this.remaining,
    required this.dragging,
  });

  final Float64List? levels;
  final double fraction;
  final Color played;
  final Color remaining;
  final bool dragging;

  static const _barWidth = 3.0;
  static const _gap = 2.5;
  static const _minHeight = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final data = levels;
    var maxLevel = 0.0;
    if (data != null) {
      for (final v in data) {
        if (v > maxLevel) maxLevel = v;
      }
    }
    final count = math.max(1, ((size.width + _gap) / (_barWidth + _gap)).floor());
    final step = size.width / count;
    final centerY = size.height / 2;
    final progressX = size.width * fraction;
    final paint = Paint()
      ..strokeWidth = _barWidth
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      var level = 0.0;
      if (data != null && data.isNotEmpty && maxLevel > 0) {
        final from = (i * data.length / count).floor();
        final to = math.max(from + 1, ((i + 1) * data.length / count).floor());
        for (var j = from; j < to && j < data.length; j++) {
          if (data[j] > level) level = data[j];
        }
        // A gentle curve lifts quiet passages so they still read as sound.
        level = math.pow(level / maxLevel, 0.7).toDouble();
      }
      final height = math.max(_minHeight, level * size.height);
      final half = math.max(0.0, height - _barWidth) / 2;
      final x = (i + 0.5) * step;
      paint.color = x <= progressX ? played : remaining;
      canvas.drawLine(Offset(x, centerY - half), Offset(x, centerY + half), paint);
    }

    if (dragging) {
      canvas.drawLine(
        Offset(progressX, 0),
        Offset(progressX, size.height),
        Paint()
          ..color = played
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.levels != levels ||
      old.fraction != fraction ||
      old.played != played ||
      old.remaining != remaining ||
      old.dragging != dragging;
}
