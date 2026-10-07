import 'package:flutter/material.dart';

import '../artwork.dart';
import '../formatting.dart';
import '../native_bridge.dart';
import '../player/player_controller.dart';
import '../ui/common.dart';
import '../ui/generated_cover.dart';
import 'playlist_store.dart';

/// Asks for a playlist name. Returns null if cancelled.
Future<String?> showPlaylistNameDialog(BuildContext context, {String title = 'New playlist', String initial = ''}) {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final name = controller.text.trim();
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Name'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: name.isEmpty ? null : () => Navigator.pop(context, name), child: const Text('Save')),
          ],
        );
      },
    ),
  );
}

/// Bottom sheet to put [tracks] into an existing or a new playlist.
Future<void> showAddToPlaylistSheet(BuildContext context, List<Track> tracks) async {
  final store = PlaylistStore.instance;
  await store.load();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);

  void added(Playlist playlist, int count) {
    showSnack(messenger, count == 0 ? 'Already in “${playlist.name}”' : 'Added ${songCount(count)} to “${playlist.name}”');
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (sheetContext, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text('Add to playlist', style: theme.textTheme.headlineSmall),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.add_rounded, color: colors.onPrimary),
              ),
              title: const Text('New playlist'),
              onTap: () async {
                final name = await showPlaylistNameDialog(sheetContext);
                if (name == null) return;
                final playlist = store.create(name);
                added(playlist, store.addTracks(playlist, tracks));
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            for (final playlist in store.playlists!)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: PlaylistCover(playlist: playlist, size: 52, radius: 14),
                title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(songCount(playlist.entries.length)),
                onTap: () {
                  added(playlist, store.addTracks(playlist, tracks));
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      );
    },
  );
}

Future<void> renamePlaylist(BuildContext context, Playlist playlist) async {
  final name = await showPlaylistNameDialog(context, title: 'Rename playlist', initial: playlist.name);
  if (name != null) PlaylistStore.instance.rename(playlist, name);
}

/// Returns true if the playlist was deleted.
Future<bool> deletePlaylist(BuildContext context, Playlist playlist) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: colors.error),
        title: const Text('Delete playlist?'),
        content: Text('“${playlist.name}” will be deleted. The songs themselves stay on your device.'),
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
  if (confirmed == true) PlaylistStore.instance.delete(playlist);
  return confirmed == true;
}

/// A mosaic of the first four songs' covers, the first song's cover for shorter playlists, or a
/// generated cover for an empty one.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, required this.size, this.radius = 16});

  final Playlist playlist;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tracks = PlaylistStore.instance.resolve(playlist).tracks;
    final Widget content;
    if (tracks.length >= 4) {
      final half = size / 2;
      Widget tile(int i) => Artwork(uri: tracks[i].uri, size: half, radius: 0);
      content = Column(
        children: [
          Row(children: [tile(0), tile(1)]),
          Row(children: [tile(2), tile(3)]),
        ],
      );
    } else if (tracks.isNotEmpty) {
      content = Artwork(uri: tracks.first.uri, size: size, radius: 0);
    } else {
      content = GeneratedCover(seed: playlist.id);
    }
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: content),
    );
  }
}

enum _PlaylistAction { play, shuffle, rename, delete }

/// Bottom sheet with the actions on a whole playlist.
Future<void> showPlaylistActions(BuildContext context, Playlist playlist) async {
  final store = PlaylistStore.instance;
  final resolved = store.resolve(playlist);
  final action = await showModalBottomSheet<_PlaylistAction>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      final colors = theme.colorScheme;
      final empty = resolved.tracks.isEmpty;
      Widget item(IconData icon, String label, _PlaylistAction value, {bool enabled = true, bool destructive = false}) =>
          ListTile(
            enabled: enabled,
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Icon(icon, color: destructive ? colors.error : null),
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
                    PlaylistCover(playlist: playlist, size: 60),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            playlistDetails(resolved),
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
              item(Icons.play_arrow_rounded, 'Play', _PlaylistAction.play, enabled: !empty),
              item(Icons.shuffle_rounded, 'Shuffle', _PlaylistAction.shuffle, enabled: !empty),
              item(Icons.edit_rounded, 'Rename', _PlaylistAction.rename),
              item(Icons.delete_outline_rounded, 'Delete playlist', _PlaylistAction.delete, destructive: true),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _PlaylistAction.play:
      await PlayerController.instance.playAll(resolved.tracks);
    case _PlaylistAction.shuffle:
      await PlayerController.instance.shuffleAll(resolved.tracks);
    case _PlaylistAction.rename:
      await renamePlaylist(context, playlist);
    case _PlaylistAction.delete:
      await deletePlaylist(context, playlist);
  }
}

/// "12 songs · 45 min".
String playlistDetails(ResolvedPlaylist resolved) => [
      songCount(resolved.tracks.length),
      if (resolved.tracks.isNotEmpty) formatTotalDuration(resolved.durationMs),
    ].join(' · ');
