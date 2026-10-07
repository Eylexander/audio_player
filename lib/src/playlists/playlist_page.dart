import 'package:flutter/material.dart';

import '../artwork.dart';
import '../formatting.dart';
import '../library/folders_tab.dart';
import '../library/library_controller.dart';
import '../library/track_tile.dart';
import '../native_bridge.dart';
import '../player/mini_player.dart';
import '../player/player_controller.dart';
import '../player/track_colors.dart';
import '../ui/common.dart';
import '../ui/header_scroll_view.dart';
import 'playlist_store.dart';
import 'playlists_ui.dart';

void openPlaylist(BuildContext context, Playlist playlist) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlist: playlist)));
}

enum _PageAction { rename, removeMissing, delete }

/// One playlist: play, shuffle, add, remove and reorder songs. The page takes on the colors of
/// its first song's cover.
class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.playlist});

  final Playlist playlist;

  static const _coverSize = 208.0;

  Future<void> _addSongs(BuildContext context) async {
    final picked = await Navigator.of(context).push<List<Track>>(
      MaterialPageRoute(builder: (_) => TrackPickerPage(playlist: playlist)),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    final added = PlaylistStore.instance.addTracks(playlist, picked);
    showSnack(ScaffoldMessenger.of(context), 'Added ${songCount(added)}');
  }

  @override
  Widget build(BuildContext context) {
    final store = PlaylistStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final resolved = store.resolve(playlist);
        final tracks = resolved.tracks;
        return TrackThemed(
          uri: tracks.firstOrNull?.uri,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final colors = theme.colorScheme;
              return Scaffold(
                extendBody: true,
                body: Stack(
                  children: [
                    // Ambient glow in the playlist's colors, behind the header.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 520,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [colors.primaryContainer, colors.surface],
                          ),
                        ),
                      ),
                    ),
                    HeaderScrollView(
                      title: playlist.name,
                      transparentAppBar: true,
                      collapseOffset: _coverSize + 40,
                      actions: [
                        IconButton(
                          tooltip: 'Add songs',
                          onPressed: () => _addSongs(context),
                          icon: const Icon(Icons.playlist_add_rounded),
                        ),
                        PopupMenuButton<_PageAction>(
                          tooltip: 'More',
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (action) async {
                            switch (action) {
                              case _PageAction.rename:
                                await renamePlaylist(context, playlist);
                              case _PageAction.removeMissing:
                                store.removeMissing(playlist);
                              case _PageAction.delete:
                                if (await deletePlaylist(context, playlist) && context.mounted) Navigator.pop(context);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: _PageAction.rename, child: Text('Rename')),
                            if (resolved.missing > 0)
                              const PopupMenuItem(value: _PageAction.removeMissing, child: Text('Remove missing songs')),
                            const PopupMenuItem(value: _PageAction.delete, child: Text('Delete playlist')),
                          ],
                        ),
                      ],
                      header: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: Column(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.shadow.withValues(alpha: 0.22),
                                    blurRadius: 28,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: PlaylistCover(playlist: playlist, size: _coverSize, radius: 28),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              playlist.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium?.copyWith(color: colors.onSurface),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              playlistDetails(resolved),
                              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            if (tracks.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              PlayShuffleButtons(tracks: tracks),
                            ],
                          ],
                        ),
                      ),
                      slivers: [
                        if (resolved.missing > 0)
                          SliverToBoxAdapter(
                            child: _MissingBanner(count: resolved.missing, onRemove: () => store.removeMissing(playlist)),
                          ),
                        if (tracks.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: EmptyState(
                              icon: Icons.music_note_rounded,
                              title: 'Nothing here yet',
                              message: 'Pick songs from your library to fill this playlist.',
                              action: FilledButton.icon(
                                onPressed: () => _addSongs(context),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add songs'),
                              ),
                            ),
                          )
                        else ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                              child: Row(
                                children: [
                                  Icon(Icons.drag_indicator_rounded, size: 16, color: colors.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Long-press a song, then drag it to reorder',
                                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverReorderableList(
                            itemCount: tracks.length,
                            onReorder: (from, to) {
                              if (to > from) to--;
                              store.moveEntry(playlist, resolved.entryIndexes[from], resolved.entryIndexes[to]);
                            },
                            proxyDecorator: (child, index, animation) => Material(
                              color: colors.surfaceContainerHigh,
                              elevation: 6,
                              shadowColor: colors.shadow.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(16),
                              child: child,
                            ),
                            itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                              key: ValueKey('${resolved.entryIndexes[i]}:${tracks[i].uri}'),
                              index: i,
                              child: TrackTile(
                                track: tracks[i],
                                onTap: () => PlayerController.instance.playAll(tracks, index: i),
                                onRemoveFromPlaylist: () => store.removeEntry(playlist, resolved.entryIndexes[i]),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                bottomNavigationBar: const MiniPlayer(),
              );
            },
          ),
        );
      },
    );
  }
}

class _MissingBanner extends StatelessWidget {
  const _MissingBanner({required this.count, required this.onRemove});

  final int count;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(
            children: [
              Icon(Icons.link_off_rounded, color: colors.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${songCount(count)} not found on this device (moved or deleted).',
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.onErrorContainer),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: colors.onErrorContainer),
                onPressed: onRemove,
                child: const Text('Remove'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick songs from the library (with search). Returns them in the order they were checked.
/// Songs already in the playlist are shown as such and can't be picked twice.
class TrackPickerPage extends StatefulWidget {
  const TrackPickerPage({super.key, required this.playlist});

  final Playlist playlist;

  @override
  State<TrackPickerPage> createState() => _TrackPickerPageState();
}

class _TrackPickerPageState extends State<TrackPickerPage> {
  final _selected = <String, Track>{}; // Insertion-ordered: keeps the order songs were checked.
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final library = LibraryController.instance;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final present = {
      for (final e in widget.playlist.entries) e.uri,
      for (final t in PlaylistStore.instance.resolve(widget.playlist).tracks) t.uri,
    };
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add songs'),
            Text(
              'to “${widget.playlist.name}”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search songs, artists, albums',
                prefixIcon: Icon(Icons.search_rounded),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          if (library.hasPermission == false) return const PermissionNeeded();
          final all = library.tracks;
          if (all == null) return const Center(child: CircularProgressIndicator());
          final tracks = _query.isEmpty ? all : all.where((t) => matchesTrack(t, _query)).toList();
          if (tracks.isEmpty) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matching songs',
              message: _query.isEmpty ? null : 'Nothing matches “$_query”.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final track = tracks[i];
              final already = present.contains(track.uri);
              final checked = already || _selected.containsKey(track.uri);
              return CheckboxListTile(
                value: checked,
                selected: _selected.containsKey(track.uri),
                selectedTileColor: colors.secondaryContainer.withValues(alpha: 0.5),
                checkboxShape: const CircleBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                onChanged: already
                    ? null
                    : (v) => setState(() => v == true ? _selected[track.uri] = track : _selected.remove(track.uri)),
                secondary: Artwork(uri: track.uri, size: 52, radius: 14),
                title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  already
                      ? 'Already in this playlist'
                      : [track.artistOrUnknown, if (track.durationMs > 0) formatShort(track.durationMs)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          );
        },
      ),
      // Lifted above the keyboard, so the button stays reachable while searching.
      bottomNavigationBar: Material(
        color: colors.surfaceContainer,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
            child: FilledButton.icon(
              onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.values.toList()),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(_selected.isEmpty ? 'Select songs' : 'Add ${songCount(_selected.length)}'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Search over a song's title, artist, album and file name. [query] must be lowercase.
bool matchesTrack(Track t, String query) =>
    t.title.toLowerCase().contains(query) ||
    (t.artist?.toLowerCase().contains(query) ?? false) ||
    (t.album?.toLowerCase().contains(query) ?? false) ||
    t.displayName.toLowerCase().contains(query);
