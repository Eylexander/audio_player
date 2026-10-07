import 'dart:async';

import 'package:flutter/material.dart';

import 'player_controller.dart';

/// Drag [child] sideways to skip songs: it follows the finger, slides out, and the next song
/// slides in from the other side. A song change from anywhere else (buttons, notification)
/// slides the new song in too, from the side it comes from.
class SwipeToSkip extends StatefulWidget {
  const SwipeToSkip({
    super.key,
    required this.uri,
    required this.index,
    required this.hasNext,
    required this.child,
  });

  /// The song shown, and its place in the queue: they tell which way a change goes.
  final String? uri;
  final int index;
  final bool hasNext;
  final Widget child;

  @override
  State<SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends State<SwipeToSkip> with SingleTickerProviderStateMixin {
  /// Horizontal offset as a fraction of the width: -1 is fully out to the left.
  late final _offset = AnimationController.unbounded(vsync: this);
  double _width = 1;

  /// Set while a swiped-out song waits for the player to switch: the side the next one enters from.
  double? _enterFrom;
  Timer? _enterTimeout;

  @override
  void dispose() {
    _enterTimeout?.cancel();
    _offset.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SwipeToSkip old) {
    super.didUpdateWidget(old);
    if (old.uri == widget.uri) return;
    if (_enterFrom != null) {
      _enter();
    } else if (old.uri != null && widget.uri != null) {
      // Changed from elsewhere: a short slide from the side the song comes from.
      final from = widget.index >= old.index ? 0.35 : -0.35;
      _offset.value = from;
      _offset.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  void _enter() {
    final from = _enterFrom ?? 0;
    _enterFrom = null;
    _enterTimeout?.cancel();
    _offset.value = from;
    _offset.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_enterFrom != null) return;
    var value = _offset.value + (d.primaryDelta ?? 0) / _width;
    // Resist past the last song.
    if (!widget.hasNext && value < 0) value = _offset.value + (d.primaryDelta ?? 0) / _width * 0.3;
    _offset.value = value;
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    if (_enterFrom != null) return;
    final velocity = (d.primaryVelocity ?? 0) / _width; // Widths per second.
    final value = _offset.value;
    final toNext = (value < -0.3 || velocity < -1.2) && widget.hasNext && velocity < 0.5;
    final toPrevious = (value > 0.3 || velocity > 1.2) && velocity > -0.5;
    if (!toNext && !toPrevious) {
      await _offset.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutBack);
      return;
    }
    final out = toNext ? -1.0 : 1.0;
    _enterFrom = -out;
    await _offset.animateTo(out, duration: const Duration(milliseconds: 150), curve: Curves.easeIn);
    final player = PlayerController.instance;
    toNext ? player.next() : player.previous();
    // "Previous" may restart the same song, which brings no new uri: come back in anyway.
    _enterTimeout = Timer(const Duration(milliseconds: 450), () {
      if (mounted && _enterFrom != null) _enter();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth.isFinite && constraints.maxWidth > 0 ? constraints.maxWidth : 1;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: AnimatedBuilder(
            animation: _offset,
            builder: (context, child) {
              final value = _offset.value;
              return Opacity(
                opacity: (1 - value.abs() * 0.9).clamp(0.0, 1.0),
                child: Transform.translate(offset: Offset(value * _width, 0), child: child),
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
