import 'package:flutter/material.dart';

import '../artwork.dart';
import '../cutter/editor_page.dart';
import '../formatting.dart';
import '../native_bridge.dart';
import '../player/player_controller.dart';
import '../playlists/playlists_ui.dart';
import '../ui/common.dart';
import '../ui/playing_bars.dart';
import 'library_controller.dart';

enum _TrackAction { playNext, addToQueue, addToPlaylist, removeFromPlaylist, cut, share, delete }

/// A song row: tap plays it, the "more" button opens its actions. The song that's playing is
/// marked with bouncing bars over its cover.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.onRemoveFromPlaylist,
  });

  final Track track;
  final VoidCallback onTap;
  final String? subtitle;

  /// Short label before the subtitle, e.g. the file format.
  final String? badge;

  /// Set inside a playlist: adds "Remove from playlist" to the actions.
  final VoidCallback? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context) {
    final player = PlayerController.instance;
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([player.currentUri, player.isPlaying]),
      builder: (context, _) {
        final current = player.currentUri.value == track.uri;
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          leading: SizedBox.square(
            dimension: 52,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Artwork(uri: track.uri, size: 52, radius: 14),
                if (current)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(child: PlayingBars(playing: player.isPlaying.value, color: Colors.white)),
                  ),
              ],
            ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: current ? TextStyle(color: colors.primary) : null,
          ),
          subtitle: Row(
            children: [
              if (badge != null) ...[FormatBadge(badge!), const SizedBox(width: 6)],
              Expanded(
                child: Text(
                  subtitle ?? [track.artistOrUnknown, if (track.durationMs > 0) formatShort(track.durationMs)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          onTap: onTap,
          trailing: IconButton(
            tooltip: 'More',
            onPressed: () => showTrackActions(context, track, onRemoveFromPlaylist: onRemoveFromPlaylist),
            icon: const Icon(Icons.more_vert_rounded),
          ),
        );
      },
    );
  }
}

/// Bottom sheet with everything that can be done with [track].
Future<void> showTrackActions(BuildContext context, Track track, {VoidCallback? onRemoveFromPlaylist}) async {
  final action = await showModalBottomSheet<_TrackAction>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      final colors = theme.colorScheme;
      Widget item(IconData icon, String label, _TrackAction value, {bool destructive = false}) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Icon(icon, color: destructive ? colors.error : colors.onSurfaceVariant),
            title: Text(label, style: destructive ? TextStyle(color: colors.error) : null),
            onTap: () => Navigator.pop(sheet, value),
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  children: [
                    Artwork(uri: track.uri, size: 60, radius: 16),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            [track.artistOrUnknown, if (track.durationMs > 0) formatShort(track.durationMs)].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(indent: 24, endIndent: 24),
              const SizedBox(height: 4),
              item(Icons.playlist_play_rounded, 'Play next', _TrackAction.playNext),
              item(Icons.add_to_queue_rounded, 'Add to queue', _TrackAction.addToQueue),
              item(Icons.playlist_add_rounded, 'Add to playlist…', _TrackAction.addToPlaylist),
              if (onRemoveFromPlaylist != null)
                item(Icons.playlist_remove_rounded, 'Remove from playlist', _TrackAction.removeFromPlaylist),
              item(Icons.content_cut_rounded, 'Cut', _TrackAction.cut),
              item(Icons.share_rounded, 'Share', _TrackAction.share),
              item(Icons.delete_outline_rounded, 'Delete file', _TrackAction.delete, destructive: true),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  switch (action) {
    case _TrackAction.playNext:
      await NativeBridge.playNext(track);
      showSnack(messenger, '“${track.title}” will play next');
    case _TrackAction.addToQueue:
      await NativeBridge.addToQueue(track);
      showSnack(messenger, 'Added “${track.title}” to the queue');
    case _TrackAction.addToPlaylist:
      await showAddToPlaylistSheet(context, [track]);
    case _TrackAction.removeFromPlaylist:
      onRemoveFromPlaylist!();
    case _TrackAction.cut:
      await openEditor(context, track.uri);
    case _TrackAction.share:
      await NativeBridge.shareFile(track.uri);
    case _TrackAction.delete:
      await confirmDelete(context, track);
  }
}

/// Asks for confirmation, then deletes the file from the device.
Future<void> confirmDelete(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: colors.error),
        title: const Text('Delete file?'),
        content: Text(
          '“${track.displayName.isNotEmpty ? track.displayName : track.title}” will be permanently deleted from your device.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onError),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  try {
    await LibraryController.instance.delete(track);
  } catch (_) {
    showSnack(messenger, "Couldn't delete the file.");
  }
}

/// The two big buttons at the top of a playlist or a folder.
class PlayShuffleButtons extends StatelessWidget {
  const PlayShuffleButtons({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final player = PlayerController.instance;
    const size = Size.fromHeight(52);
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: tracks.isEmpty ? null : () => player.playAll(tracks),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: tracks.isEmpty ? null : () => player.shuffleAll(tracks),
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('Shuffle'),
          ),
        ),
      ],
    );
  }
}
