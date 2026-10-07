import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../formatting.dart';
import '../library/folders_tab.dart';
import '../library/library_controller.dart';
import '../native_bridge.dart';
import '../player/player_controller.dart';
import '../settings.dart';
import '../ui/common.dart';
import '../ui/header_scroll_view.dart';
import 'playlist_page.dart';
import 'playlist_store.dart';
import 'playlists_ui.dart';

/// First tab, and the heart of the app: the user's playlists.
class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  Future<void> _create(BuildContext context) async {
    final name = await showPlaylistNameDialog(context);
    if (name == null || !context.mounted) return;
    openPlaylist(context, PlaylistStore.instance.create(name));
  }

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = await NativeBridge.pickPlaylistFile();
    if (uri == null) return;
    try {
      final result = await PlaylistStore.instance.importM3u(uri);
      final count = result.playlist.entries.length;
      showSnack(
        messenger,
        'Imported “${result.playlist.name}”: ${songCount(count)}'
        '${result.unmatched > 0 ? ', ${result.unmatched} not found on this device' : ''}',
      );
    } catch (_) {
      showSnack(messenger, "Couldn't read this playlist file.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = PlaylistStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, Settings.instance]),
      builder: (context, _) {
        final playlists = store.playlists;
        final noAccess = LibraryController.instance.hasPermission == false;
        final songs = playlists?.fold(0, (sum, p) => sum + p.entries.length) ?? 0;
        return HeaderScrollView(
          title: 'Playlists',
          subtitle: playlists == null || playlists.isEmpty
              ? null
              : '${playlists.length} ${playlists.length == 1 ? 'playlist' : 'playlists'} · ${songCount(songs)}',
          actions: homeActions(context),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => _create(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New playlist'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: noAccess ? null : () => _import(context),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Import .m3u'),
                    ),
                  ],
                ),
              ),
            ),
            if (playlists == null)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (noAccess)
              const SliverFillRemaining(hasScrollBody: false, child: PermissionNeeded())
            else if (playlists.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: 'No playlists yet',
                  message: 'Create one and add songs to it, or import an .m3u playlist exported from another '
                      'player. Any song’s menu can also add it to a playlist.',
                ),
              )
            else if (Settings.instance.playlistGrid)
              _PlaylistGrid(playlists: playlists)
            else
              SliverList.builder(
                itemCount: playlists.length,
                itemBuilder: (context, i) => PlaylistTile(playlist: playlists[i]),
              ),
          ],
        );
      },
    );
  }
}

class _PlaylistGrid extends StatelessWidget {
  const _PlaylistGrid({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const padding = 12.0;
        const spacing = 4.0;
        final available = constraints.crossAxisExtent - 2 * padding;
        final columns = math.max(2, (available / 220).floor());
        final tileWidth = (available - (columns - 1) * spacing) / columns;
        // Cover, then the name and details under it.
        final tileHeight = tileWidth + 22 + textScaler.scale(24) + textScaler.scale(18);
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: padding),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: 6,
              mainAxisExtent: tileHeight,
            ),
            itemCount: playlists.length,
            itemBuilder: (context, i) => _PlaylistCard(playlist: playlists[i]),
          ),
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final resolved = PlaylistStore.instance.resolve(playlist);
    return Semantics(
      container: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => openPlaylist(context, playlist),
        onLongPress: () => showPlaylistActions(context, playlist),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    PlaylistCover(playlist: playlist, size: constraints.maxWidth, radius: 20),
                    if (resolved.tracks.isNotEmpty)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
                          ),
                          child: IconButton.filled(
                            tooltip: 'Play ${playlist.name}',
                            onPressed: () => PlayerController.instance.playAll(resolved.tracks),
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  playlistDetails(resolved),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A playlist as a row (list view and search results).
class PlaylistTile extends StatelessWidget {
  const PlaylistTile({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final resolved = PlaylistStore.instance.resolve(playlist);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: PlaylistCover(playlist: playlist, size: 52, radius: 14),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(playlistDetails(resolved)),
      onTap: () => openPlaylist(context, playlist),
      onLongPress: () => showPlaylistActions(context, playlist),
      trailing: IconButton(
        tooltip: 'More',
        onPressed: () => showPlaylistActions(context, playlist),
        icon: const Icon(Icons.more_vert_rounded),
      ),
    );
  }
}
