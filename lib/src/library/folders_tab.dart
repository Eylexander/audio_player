import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../formatting.dart';
import '../native_bridge.dart';
import '../player/mini_player.dart';
import '../player/player_controller.dart';
import '../theme.dart';
import '../ui/common.dart';
import '../ui/header_scroll_view.dart';
import 'library_controller.dart';
import 'track_tile.dart';

/// Shown instead of the library while the app can't read the music.
class PermissionNeeded extends StatefulWidget {
  const PermissionNeeded({super.key});

  @override
  State<PermissionNeeded> createState() => _PermissionNeededState();
}

class _PermissionNeededState extends State<PermissionNeeded> {
  bool _askedOnce = false;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.library_music_rounded,
      title: 'Your music lives here',
      message: 'Allow access to the audio files on this device to play them and build playlists.',
      action: Column(
        children: [
          FilledButton(
            onPressed: () async {
              await LibraryController.instance.requestPermission();
              if (mounted) setState(() => _askedOnce = true);
            },
            child: const Text('Allow access'),
          ),
          if (_askedOnce) TextButton(onPressed: NativeBridge.openAppSettings, child: const Text('Open app settings')),
        ],
      ),
    );
  }
}

/// Second tab: the library grouped by folder.
class FoldersTab extends StatelessWidget {
  const FoldersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final library = LibraryController.instance;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final tracks = library.tracks;
        final folders = library.folders;
        return RefreshIndicator(
          onRefresh: library.load,
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
          child: HeaderScrollView(
            title: 'Folders',
            subtitle: tracks == null || tracks.isEmpty
                ? null
                : '${folders.length} ${folders.length == 1 ? 'folder' : 'folders'} · ${songCount(tracks.length)}',
            actions: homeActions(context),
            slivers: [
              if (library.hasPermission == false)
                const SliverFillRemaining(hasScrollBody: false, child: PermissionNeeded())
              else if (tracks == null)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
              else if (tracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.folder_off_rounded,
                    title: 'No music found',
                    message: 'Audio files on this device show up here, grouped by folder.',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: folders.length,
                  itemBuilder: (context, i) => FolderTile(folder: folders[i]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class FolderTile extends StatelessWidget {
  const FolderTile({super.key, required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = CoverPalette.of(context).pick(stableHash(folder.path));
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
        child: Icon(Icons.folder_rounded, color: foreground),
      ),
      title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [songCount(folder.tracks.length), if (folder.path.isNotEmpty) folder.path].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Play folder',
        onPressed: () => PlayerController.instance.playAll(folder.tracks),
        icon: const Icon(Icons.play_arrow_rounded),
      ),
      onTap: () => openFolder(context, folder.path),
    );
  }
}

void openFolder(BuildContext context, String path) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FolderPage(path: path)));
}

/// The songs of one folder. Looked up again on every library change, so deleted files go away.
class FolderPage extends StatelessWidget {
  const FolderPage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final library = LibraryController.instance;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final folder = library.folder(path);
        final tracks = folder?.tracks ?? const <Track>[];
        final name = folder?.name ?? (path.isEmpty ? '/' : path.split('/').last);
        return Scaffold(
          extendBody: true,
          body: HeaderScrollView(
            title: name,
            subtitle: [
              if (path.isNotEmpty) path,
              songCount(tracks.length),
              if (tracks.isNotEmpty) formatTotalDuration(folder!.durationMs),
            ].join(' · '),
            slivers: [
              if (tracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(icon: Icons.folder_off_rounded, title: 'This folder is empty'),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(child: PlayShuffleButtons(tracks: tracks)),
                ),
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackTile(
                    track: tracks[i],
                    onTap: () => PlayerController.instance.playAll(tracks, index: i),
                  ),
                ),
              ],
            ],
          ),
          bottomNavigationBar: const MiniPlayer(),
        );
      },
    );
  }
}
