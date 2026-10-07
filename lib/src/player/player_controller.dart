import 'dart:async';

import 'package:flutter/foundation.dart';

import '../native_bridge.dart';

/// Mirrors the state of the background player for the UI.
class PlayerController extends ChangeNotifier {
  PlayerController._() {
    _events = NativeBridge.events.listen((event) {
      if (event is PlayerEvent) {
        state = event.state;
        currentUri.value = state.uri;
        isPlaying.value = state.isPlaying;
        notifyListeners();
      }
    });
    NativeBridge.refreshPlayer();
  }

  static final instance = PlayerController._();

  late final StreamSubscription<NativeEvent> _events;
  PlayerState state = const PlayerState();

  /// Narrower than listening to the controller, which also notifies on every position update:
  /// rows only need to know which song is current and whether it plays.
  final currentUri = ValueNotifier<String?>(null);
  final isPlaying = ValueNotifier<bool>(false);

  bool isCurrent(Track track) => state.uri == track.uri;

  Future<void> playAll(List<Track> tracks, {int index = 0}) => NativeBridge.play(tracks, index: index);

  Future<void> shuffleAll(List<Track> tracks) {
    if (tracks.isEmpty) return Future.value();
    final start = DateTime.now().microsecond % tracks.length;
    return NativeBridge.play(tracks, index: start, shuffle: true);
  }

  Future<void> togglePlay() => NativeBridge.togglePlay();

  Future<void> next() => NativeBridge.next();

  Future<void> previous() => NativeBridge.previous();

  Future<void> seek(int positionMs) => NativeBridge.seek(positionMs);

  Future<void> toggleShuffle() => NativeBridge.setShuffle(!state.shuffle);

  /// Off -> all -> one -> off, like most players.
  Future<void> cycleRepeat() => NativeBridge.setRepeat(switch (state.repeat) {
        RepeatMode.off => RepeatMode.all,
        RepeatMode.all => RepeatMode.one,
        RepeatMode.one => RepeatMode.off,
      });

  @override
  void dispose() {
    _events.cancel();
    currentUri.dispose();
    isPlaying.dispose();
    super.dispose();
  }
}
