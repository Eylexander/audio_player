import 'package:flutter/material.dart';

import '../artwork.dart';
import '../native_bridge.dart';
import 'now_playing_page.dart';
import 'player_controller.dart';
import 'track_colors.dart';

/// Floating card at the bottom of the screens while something is loaded in the player, in the
/// colors of the song. Tap or swipe up to open the full player, swipe sideways to skip.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.safeArea = true});

  /// False when something below (the navigation bar) already keeps clear of the system bar.
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final player = PlayerController.instance;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final s = player.state;
        if (!s.hasItem) {
          // Still reserve the system bar's height, so pages can scroll their end clear of it.
          return safeArea ? const SafeArea(top: false, child: SizedBox(width: double.infinity)) : const SizedBox.shrink();
        }
        return SafeArea(
          top: false,
          bottom: safeArea,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: TrackThemed(uri: s.uri, child: _MiniPlayerCard(state: s)),
          ),
        );
      },
    );
  }
}

class _MiniPlayerCard extends StatelessWidget {
  const _MiniPlayerCard({required this.state});

  final PlayerState state;

  @override
  Widget build(BuildContext context) {
    final player = PlayerController.instance;
    final s = state;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = s.durationMs ?? 0;
    final progress = duration > 0 ? (s.positionMs / duration).clamp(0.0, 1.0) : 0.0;
    final foreground = colors.onPrimaryContainer;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final velocity = d.primaryVelocity ?? 0;
        if (velocity < -300) {
          player.next();
        } else if (velocity > 300) {
          player.previous();
        }
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -300) openNowPlaying(context);
      },
      child: Material(
        color: colors.primaryContainer,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openNowPlaying(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(
              children: [
                Hero(tag: 'now-playing-art', child: Artwork(uri: s.uri, size: 48, radius: 14)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: foreground),
                      ),
                      Text(
                        s.artist ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: foreground.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.square(
                        dimension: 40,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 2.5,
                          strokeCap: StrokeCap.round,
                          color: foreground,
                          backgroundColor: foreground.withValues(alpha: 0.16),
                        ),
                      ),
                      IconButton(
                        tooltip: s.isPlaying ? 'Pause' : 'Play',
                        onPressed: player.togglePlay,
                        color: foreground,
                        icon: Icon(s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Next',
                  color: foreground,
                  onPressed: s.index < s.count - 1 || s.repeat != RepeatMode.off ? player.next : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
