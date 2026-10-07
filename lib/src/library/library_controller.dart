import 'package:flutter/foundation.dart';

import '../native_bridge.dart';

class Folder {
  Folder(this.path, this.tracks);

  final String path;
  final List<Track> tracks;

  String get name => path.isEmpty ? '/' : path.split('/').last;

  int get durationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);
}

int _compareText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// The device's music (all songs, and the same songs grouped by folder) and the app's own cuts.
class LibraryController extends ChangeNotifier {
  LibraryController._();

  static final instance = LibraryController._();

  /// Null until checked.
  bool? hasPermission;

  /// Null while loading.
  List<Track>? tracks;
  List<Track>? savedCuts;

  List<Folder> folders = const [];

  Folder? folder(String path) => folders.where((f) => f.path == path).firstOrNull;

  Future<void> load() async {
    hasPermission = await NativeBridge.hasLibraryPermission();
    final cuts = NativeBridge.listSaved();
    if (hasPermission!) {
      try {
        _setTracks(await NativeBridge.listTracks());
      } catch (_) {
        _setTracks(const []);
      }
    }
    try {
      savedCuts = await cuts;
    } catch (_) {
      savedCuts = const [];
    }
    notifyListeners();
  }

  Future<void> requestPermission() async {
    if (await NativeBridge.requestLibraryPermission()) {
      await load();
    } else {
      hasPermission = false;
      notifyListeners();
    }
  }

  /// Returns false if the user declined the system confirmation.
  Future<bool> delete(Track track) async {
    final deleted = await NativeBridge.deleteFile(track.uri);
    if (deleted) await load();
    return deleted;
  }

  /// Where playlist folders live. Their copies are hidden while the original is still elsewhere.
  static const playlistsPath = 'Music/Playlists/';

  void _setTracks(List<Track> found) {
    // The same file (name and size) in several places: keep those outside the playlist folders,
    // or a single one if they're all in playlist folders.
    final byFile = <String, List<Track>>{};
    for (final t in found) {
      byFile.putIfAbsent('${t.displayName}|${t.sizeBytes}', () => []).add(t);
    }
    bool inPlaylistFolder(Track t) => '${t.folder}/'.startsWith(playlistsPath);
    final all = [
      for (final same in byFile.values)
        if (same.length == 1)
          same.first
        else if (same.any((t) => !inPlaylistFolder(t)))
          ...same.where((t) => !inPlaylistFolder(t))
        else
          same.first,
    ];

    tracks = [...all]..sort((a, b) => _compareText(a.title, b.title));

    final byFolder = <String, List<Track>>{};
    for (final t in all) {
      byFolder.putIfAbsent(t.folder, () => []).add(t);
    }

    folders = [
      for (final entry in byFolder.entries) Folder(entry.key, entry.value..sort((a, b) => _compareText(a.title, b.title))),
    ]..sort((a, b) => _compareText(a.name, b.name));
  }
}
