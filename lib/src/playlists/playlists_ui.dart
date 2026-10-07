import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../artwork.dart';
import '../formatting.dart';
import '../native_bridge.dart';
import '../player/player_controller.dart';
import '../settings.dart';
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

/// Before the first move, offers "Media management" (Android 12+), which lets moves happen without a
/// confirmation for each file. Asked once; it can be changed later in Settings.
Future<void> offerManageMedia(BuildContext context) async {
  final settings = Settings.instance;
  if (settings.offeredManageMedia || await NativeBridge.canManageMedia() != false || !context.mounted) return;
  settings.setOfferedManageMedia();
  final allow = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      final colors = theme.colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.folder_special_rounded, size: 36, color: colors.primary),
              const SizedBox(height: 12),
              Text('Move songs without asking?', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Android confirms every move of a song another app downloaded. Turn on “Media management” for '
                'Audio Cutter once, and songs go into playlist folders without asking, including songs you add '
                'later.\n\nAndroid then asks about “photos and videos”: that’s how it labels the last permission '
                'moves need. Choose “Allow all”. Audio Cutter has no access to your photos.\n\n'
                'You can change it any time in Settings.',
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(sheet, false), child: const Text('Not now')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => Navigator.pop(sheet, true), child: const Text('Open settings')),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  if (allow == true) await NativeBridge.requestManageMedia();
}

/// Tells the user songs were added, once they're also moved when the playlist keeps its songs in
/// its folder (Android may ask for permission first). [inName] adds the playlist's name.
Future<void> reportAdded(ScaffoldMessengerState messenger, Playlist playlist, AddResult result, {bool inName = false}) async {
  final added = 'Added ${songCount(result.added)}${inName ? ' to “${playlist.name}”' : ''}';
  final moving = result.moved;
  if (moving == null) return showSnack(messenger, added);
  final moved = await moving.catchError((_) => 0);
  showSnack(messenger, switch (moved) {
    -1 => '$added. They stay in their folders: Android’s permission was declined',
    0 => added,
    _ when moved < result.added => '$added, moved ${songCount(moved)} to ${playlist.folder}',
    _ => '$added and moved to ${playlist.folder}',
  });
}

/// Bottom sheet to put [tracks] into an existing or a new playlist.
Future<void> showAddToPlaylistSheet(BuildContext context, List<Track> tracks) async {
  final store = PlaylistStore.instance;
  await store.load();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);

  void added(Playlist playlist, AddResult result) {
    if (result.added == 0) {
      showSnack(messenger, 'Already in “${playlist.name}”');
    } else {
      reportAdded(messenger, playlist, result, inName: true);
    }
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
        content: Text(
          '“${playlist.name}” will be deleted. The songs themselves stay on your device'
          '${playlist.folder != null ? ', and so does its folder (${playlist.folder})' : ''}.',
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
  if (confirmed == true) PlaylistStore.instance.delete(playlist);
  return confirmed == true;
}

/// The cover the user picked, else a mosaic of the first four songs' covers, the first song's
/// cover for shorter playlists, or a generated cover for an empty one.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, required this.size, this.radius = 16});

  final Playlist playlist;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tracks = PlaylistStore.instance.resolve(playlist).tracks;
    final design = CoverDesign.decode(playlist.cover);
    final Widget content;
    if (design != null) {
      content = GeneratedCover.design(design);
    } else if (tracks.length >= 4) {
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

enum _PlaylistAction { play, shuffle, rename, cover, delete }

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
              item(Icons.palette_outlined, 'Change cover', _PlaylistAction.cover),
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
    case _PlaylistAction.cover:
      await showCoverPicker(context, playlist);
    case _PlaylistAction.delete:
      await deletePlaylist(context, playlist);
  }
}

/// "12 songs · 45 min".
String playlistDetails(ResolvedPlaylist resolved) => [
      songCount(resolved.tracks.length),
      if (resolved.tracks.isNotEmpty) formatTotalDuration(resolved.durationMs),
    ].join(' · ');

/// Bottom sheet to give a playlist a generated cover, or go back to its songs' covers.
Future<void> showCoverPicker(BuildContext context, Playlist playlist) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CoverPicker(playlist: playlist),
    );

class _CoverPicker extends StatefulWidget {
  const _CoverPicker({required this.playlist});

  final Playlist playlist;

  @override
  State<_CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends State<_CoverPicker> {
  final _random = math.Random();
  late List<CoverDesign> _designs = _roll();

  /// Every style twice, each with its own colors.
  List<CoverDesign> _roll() => [
        for (var round = 0; round < 2; round++)
          for (final style in CoverStyle.values) CoverDesign(style, _random.nextInt(1 << 30).toString()),
      ];

  void _pick(String? cover) {
    PlaylistStore.instance.setCover(widget.playlist, cover);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final playlist = widget.playlist;
    final current = CoverDesign.decode(playlist.cover);
    // The current design stays first, so it can be kept while rolling new ones.
    final designs = [if (current != null) current, ..._designs.where((d) => d != current).take(current == null ? 12 : 11)];

    Widget option({required Widget child, required bool selected, required VoidCallback onTap, required String label}) =>
        Semantics(
          button: true,
          selected: selected,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? colors.primary : Colors.transparent, width: 3),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(15), child: child),
            ),
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Cover', style: theme.textTheme.headlineSmall)),
                TextButton.icon(
                  onPressed: () => setState(() => _designs = _roll()),
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            option(
              selected: current == null,
              label: 'Song covers',
              onTap: () => _pick(null),
              child: Container(
                color: colors.surfaceContainerHigh,
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    PlaylistCover(playlist: Playlist(id: playlist.id, name: '', entries: playlist.entries), size: 56, radius: 12),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Song covers', style: theme.textTheme.titleSmall),
                          Text(
                            'Made from the first songs’ cover art',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (final design in designs)
                  option(
                    selected: design == current,
                    label: '${design.style.name} cover',
                    onTap: () => _pick(design.encode()),
                    child: GeneratedCover.design(design),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
