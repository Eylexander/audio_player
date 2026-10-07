import 'package:flutter/material.dart';

import '../artwork.dart';
import '../cutter/editor_page.dart';
import '../native_bridge.dart';
import '../playlists/playlists_ui.dart';
import '../ui/playing_bars.dart';
import 'player_controller.dart';
import 'swipe_to_skip.dart';
import 'track_colors.dart';
import 'track_waveform.dart';

/// Slides the full player up from the bottom, like a sheet.
void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const NowPlayingPage(),
    transitionsBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
      ),
      child: child,
    ),
  ));
}

/// Full screen player in the colors of the song: cover, waveform seek bar and controls.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  final _player = PlayerController.instance;
  final _waveforms = TrackWaveforms.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _player,
      builder: (context, _) {
        final s = _player.state;
        return TrackThemed(
          uri: s.uri,
          child: Builder(builder: (context) => _buildPage(context, s)),
        );
      },
    );
  }

  Widget _buildPage(BuildContext context, PlayerState s) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final uri = s.uri;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
        ),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'NOW PLAYING',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 1.6),
            ),
            if (s.count > 1)
              Text('${s.index + 1} of ${s.count}', style: theme.textTheme.labelLarge?.copyWith(color: colors.onSurface)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Queue',
            onPressed: () => _showQueue(context),
            icon: const Icon(Icons.queue_music_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: GestureDetector(
        // Swipe down anywhere to close, like pulling a sheet away.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 500) Navigator.pop(context);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.primaryContainer, colors.surface],
              stops: const [0, 0.7],
            ),
          ),
          child: SafeArea(
            child: !s.hasItem
                ? Center(child: Text('Nothing is playing', style: theme.textTheme.titleMedium))
                : Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            // Swipe the cover sideways to skip.
                            child: SwipeToSkip(
                              uri: uri,
                              index: s.index,
                              hasNext: s.index < s.count - 1 || s.repeat != RepeatMode.off,
                              child: LayoutBuilder(
                                builder: (context, constraints) => DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(32),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.28),
                                        blurRadius: 36,
                                        offset: const Offset(0, 18),
                                      ),
                                    ],
                                  ),
                                  child: Hero(
                                    tag: 'now-playing-art',
                                    child: Artwork(uri: uri, size: constraints.biggest.shortestSide, radius: 32),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.title ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineSmall?.copyWith(color: colors.onSurface),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [s.artist ?? 'Unknown artist', if (s.album != null) s.album].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (uri != null)
                              IconButton.filledTonal(
                                tooltip: 'Add to playlist',
                                onPressed: () => showAddToPlaylistSheet(context, [
                                  Track(uri: uri, title: s.title ?? '', artist: s.artist, album: s.album, albumId: s.albumId),
                                ]),
                                icon: const Icon(Icons.playlist_add_rounded),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ValueListenableBuilder(
                          valueListenable: _waveforms.levels,
                          builder: (context, levels, _) => WaveformSeekBar(
                            levels: levels,
                            positionMs: s.positionMs,
                            durationMs: s.durationMs ?? 0,
                            onSeek: _player.seek,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Controls(state: s),
                        const SizedBox(height: 12),
                        if (uri != null)
                          TextButton.icon(
                            onPressed: () => openEditor(context, uri),
                            icon: const Icon(Icons.content_cut_rounded, size: 18),
                            label: const Text('Cut this song'),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQueue(BuildContext context) async {
    final queue = await NativeBridge.queue();
    if (!context.mounted) return;
    final current = _player.state.index;
    const rowHeight = 72.0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        final colors = theme.colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (sheet, scroll) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('Queue', style: theme.textTheme.headlineSmall),
                    const SizedBox(width: 10),
                    Text(
                      '${queue.length} ${queue.length == 1 ? 'song' : 'songs'}',
                      style: theme.textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemExtent: rowHeight,
                  itemCount: queue.length,
                  itemBuilder: (context, i) {
                    final track = queue[i];
                    final playing = i == current;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      leading: Artwork(uri: track.uri, size: 48, radius: 12),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: playing ? TextStyle(color: colors.primary) : null,
                      ),
                      subtitle: Text(track.artistOrUnknown, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: playing
                          ? ValueListenableBuilder(
                              valueListenable: _player.isPlaying,
                              builder: (context, isPlaying, _) => PlayingBars(playing: isPlaying, color: colors.primary),
                            )
                          : null,
                      onTap: () {
                        NativeBridge.skipTo(i);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    final player = PlayerController.instance;
    final s = state;
    final colors = Theme.of(context).colorScheme;

    Widget toggle({
      required String tooltip,
      required bool active,
      required IconData icon,
      required VoidCallback onPressed,
    }) =>
        active
            ? IconButton.filledTonal(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon))
            : IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon), color: colors.onSurfaceVariant);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        toggle(
          tooltip: s.shuffle ? 'Shuffle: on' : 'Shuffle: off',
          active: s.shuffle,
          icon: Icons.shuffle_rounded,
          onPressed: player.toggleShuffle,
        ),
        IconButton(
          tooltip: 'Previous',
          onPressed: player.previous,
          iconSize: 42,
          color: colors.onSurface,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        // A circle while paused, a rounded square while playing.
        TweenAnimationBuilder<double>(
          tween: Tween(end: s.isPlaying ? 26 : 44),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, radius, child) => SizedBox.square(
            dimension: 88,
            child: FilledButton(
              onPressed: player.togglePlay,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
              ),
              child: child,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: Icon(
              s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(s.isPlaying),
              size: 44,
              semanticLabel: s.isPlaying ? 'Pause' : 'Play',
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next',
          onPressed: s.index < s.count - 1 || s.repeat != RepeatMode.off ? player.next : null,
          iconSize: 42,
          color: colors.onSurface,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        toggle(
          tooltip: switch (s.repeat) {
            RepeatMode.off => 'Repeat: off',
            RepeatMode.all => 'Repeat: all',
            RepeatMode.one => 'Repeat: this song',
          },
          active: s.repeat != RepeatMode.off,
          icon: s.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          onPressed: player.cycleRepeat,
        ),
      ],
    );
  }
}
