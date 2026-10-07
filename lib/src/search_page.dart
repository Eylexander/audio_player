import 'package:flutter/material.dart';

import 'library/folders_tab.dart';
import 'library/library_controller.dart';
import 'library/track_tile.dart';
import 'native_bridge.dart';
import 'player/mini_player.dart';
import 'player/player_controller.dart';
import 'playlists/playlist_page.dart';
import 'playlists/playlist_store.dart';
import 'playlists/playlists_tab.dart';
import 'ui/common.dart';

void openSearch(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));
}

/// Search across playlists, folders and songs (title, artist, album, file name).
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _text = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _text,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.titleMedium,
          decoration: const InputDecoration(
            hintText: 'Songs, playlists, folders',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: () {
                _text.clear();
                setState(() => _query = '');
              },
              icon: const Icon(Icons.close_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([LibraryController.instance, PlaylistStore.instance]),
        builder: (context, _) => _results(context),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  Widget _results(BuildContext context) {
    final query = _query;
    if (query.isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Find anything',
        message: 'Songs by title, artist, album or file name, and your playlists and folders.',
      );
    }
    final library = LibraryController.instance;
    final playlists = [
      for (final p in PlaylistStore.instance.playlists ?? const <Playlist>[])
        if (p.name.toLowerCase().contains(query)) p,
    ];
    final folders = [
      for (final f in library.folders)
        if (f.path.toLowerCase().contains(query)) f,
    ];
    final tracks = [
      for (final t in library.tracks ?? const <Track>[])
        if (matchesTrack(t, query)) t,
    ];
    if (playlists.isEmpty && folders.isEmpty && tracks.isEmpty) {
      return EmptyState(icon: Icons.search_off_rounded, title: 'No results', message: 'Nothing matches “$_query”.');
    }
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (playlists.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionLabel('Playlists', trailing: '${playlists.length}')),
          SliverList.builder(
            itemCount: playlists.length,
            itemBuilder: (context, i) => PlaylistTile(playlist: playlists[i]),
          ),
        ],
        if (folders.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionLabel('Folders', trailing: '${folders.length}')),
          SliverList.builder(
            itemCount: folders.length,
            itemBuilder: (context, i) => FolderTile(folder: folders[i]),
          ),
        ],
        if (tracks.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionLabel('Songs', trailing: '${tracks.length}')),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) => TrackTile(
              track: tracks[i],
              onTap: () => PlayerController.instance.playAll(tracks, index: i),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
      ],
    );
  }
}
