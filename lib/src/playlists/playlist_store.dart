import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../formatting.dart';
import '../library/library_controller.dart';
import '../native_bridge.dart';
import '../settings.dart';

/// A song in a playlist. Besides the MediaStore uri, the file name and size are kept so the
/// song can be found again if the uri changes (file moved, media database rebuilt...).
class PlaylistEntry {
  const PlaylistEntry({required this.uri, required this.title, required this.displayName, required this.sizeBytes});

  factory PlaylistEntry.fromTrack(Track t) =>
      PlaylistEntry(uri: t.uri, title: t.title, displayName: t.displayName, sizeBytes: t.sizeBytes);

  factory PlaylistEntry.fromJson(Map<String, Object?> json) => PlaylistEntry(
        uri: json['uri'] as String,
        title: json['title'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        sizeBytes: json['sizeBytes'] as int? ?? 0,
      );

  final String uri;
  final String title;
  final String displayName;
  final int sizeBytes;

  Map<String, Object?> toJson() => {'uri': uri, 'title': title, 'displayName': displayName, 'sizeBytes': sizeBytes};
}

class Playlist {
  Playlist({required this.id, required this.name, required this.entries, this.cover, this.folder});

  factory Playlist.fromJson(Map<String, Object?> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        entries: [
          for (final e in json['entries'] as List<Object?>) PlaylistEntry.fromJson((e as Map).cast<String, Object?>()),
        ],
        cover: json['cover'] as String?,
        folder: json['folder'] as String?,
      );

  final String id;
  String name;
  final List<PlaylistEntry> entries;

  /// A generated cover picked by the user ([CoverDesign.encode]), or null for the songs' covers.
  String? cover;

  /// The folder holding copies of its songs, e.g. "Music/Playlists/Road trip". Null until the
  /// first copy.
  String? folder;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'entries': [for (final e in entries) e.toJson()],
        if (cover != null) 'cover': cover,
        if (folder != null) 'folder': folder,
      };
}

/// A playlist's songs as playable tracks. [entryIndexes] maps each track back to its entry.
class ResolvedPlaylist {
  const ResolvedPlaylist(this.tracks, this.entryIndexes, this.missing);

  final List<Track> tracks;
  final List<int> entryIndexes;

  /// Entries whose file can't be found anymore.
  final int missing;

  int get durationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);
}

/// The user's playlists, saved as JSON in the app's private storage.
class PlaylistStore extends ChangeNotifier {
  PlaylistStore._() {
    LibraryController.instance.addListener(notifyListeners); // Resolution depends on the library.
  }

  static final instance = PlaylistStore._();

  /// Null until loaded.
  List<Playlist>? playlists;

  Future<void>? _loading;

  /// Saves run one after another: two saves in flight could otherwise land in the wrong order.
  Future<void> _saving = Future.value();

  /// False when the saved file couldn't be read: it must not be overwritten then, or the user's
  /// playlists would be replaced by an empty list.
  bool _canSave = true;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final saved = await NativeBridge.readPlaylists();
      playlists = _parse(saved.main) ?? _parse(saved.backup) ?? [];
      // Both copies exist but neither parses: keep them for a possible manual recovery.
      if (saved.main != null && _parse(saved.main) == null && _parse(saved.backup) == null) _canSave = false;
    } catch (_) {
      playlists = [];
      _canSave = false;
    }
    notifyListeners();
  }

  static List<Playlist>? _parse(String? json) {
    if (json == null) return null;
    try {
      return [for (final p in jsonDecode(json) as List<Object?>) Playlist.fromJson((p as Map).cast<String, Object?>())];
    } catch (_) {
      return null;
    }
  }

  void _changed() {
    notifyListeners();
    if (!_canSave) return;
    _saving = _saving.then((_) async {
      try {
        // Encoded when the write actually starts, so it's always the latest state.
        await NativeBridge.writePlaylists(jsonEncode([for (final p in playlists!) p.toJson()]));
      } catch (_) {
        // Keep going: the next change saves everything again.
      }
    });
  }

  Playlist create(String name) {
    final playlist = Playlist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name, entries: []);
    playlists!.add(playlist);
    _changed();
    return playlist;
  }

  void rename(Playlist playlist, String name) {
    if (name == playlist.name) return;
    playlist.name = name;
    final old = playlist.folder;
    if (old != null) {
      final folder = _folderFor(playlist);
      if (folder != old) {
        playlist.folder = folder;
        _copying = _copying.then((_) => NativeBridge.renameFolder(old, folder)).then(_reloadLibrary, onError: (_) {});
      }
    }
    _changed();
  }

  void setCover(Playlist playlist, String? cover) {
    playlist.cover = cover;
    _changed();
  }

  void delete(Playlist playlist) {
    playlists!.remove(playlist);
    _changed();
  }

  /// Adds the tracks that aren't in the playlist yet (the same file in its folder counts as
  /// already there). Returns how many were added.
  int addTracks(Playlist playlist, List<Track> tracks) {
    final present = {for (final e in playlist.entries) ...[e.uri, '${e.displayName}|${e.sizeBytes}']};
    var added = 0;
    for (final t in tracks) {
      if (present.contains(t.uri) || present.contains('${t.displayName}|${t.sizeBytes}')) continue;
      present.addAll([t.uri, '${t.displayName}|${t.sizeBytes}']);
      playlist.entries.add(PlaylistEntry.fromTrack(t));
      added++;
    }
    if (added > 0) {
      _changed();
      syncFolder(playlist);
    }
    return added;
  }

  void removeEntry(Playlist playlist, int entryIndex) {
    final entry = playlist.entries[entryIndex];
    final folder = playlist.folder;
    // Its copy goes too, but only while the original is still there: the copy may be all that's left.
    if (folder != null) {
      _index(LibraryController.instance.tracks ?? const []);
      final original = _byUri[entry.uri];
      if (original != null && original.folder != folder) {
        _copying = _copying
            .then((_) => NativeBridge.deleteFromFolder(folder, entry.displayName))
            .then(_reloadLibrary, onError: (_) {});
      }
    }
    playlist.entries.removeAt(entryIndex);
    _changed();
  }

  /// Folder operations run one after another, like saves.
  Future<void> _copying = Future.value();

  Future<void> _reloadLibrary(Object? changed) async {
    if (changed != 0 && changed != false) await LibraryController.instance.load();
  }

  /// "Music/Playlists/(name)", made safe as a folder name and not used by another playlist.
  String _folderFor(Playlist playlist) {
    var name = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim().replaceFirst(RegExp(r'^\.+'), '');
    if (name.isEmpty) name = 'Playlist';
    final taken = {for (final p in playlists ?? const <Playlist>[]) if (p != playlist && p.folder != null) p.folder!.toLowerCase()};
    var folder = 'Music/Playlists/$name';
    for (var i = 2; taken.contains(folder.toLowerCase()); i++) {
      folder = 'Music/Playlists/$name ($i)';
    }
    return folder;
  }

  /// Copies the playlist's songs into its folder (when that setting is on). Returns how many
  /// files were copied.
  Future<int> syncFolder(Playlist playlist, {bool force = false}) {
    if (!force && !Settings.instance.playlistFolders) return Future.value(0);
    if (playlist.folder == null) {
      playlist.folder = _folderFor(playlist);
      _changed();
    }
    final done = _copying.then((_) async {
      final folder = playlist.folder;
      final uris = [for (final t in resolve(playlist).tracks) if (t.folder != folder) t.uri];
      if (folder == null || uris.isEmpty) return 0;
      final copied = await NativeBridge.copyToFolder(uris, folder);
      await _reloadLibrary(copied);
      return copied;
    });
    _copying = done.catchError((_) => 0);
    return done;
  }

  void moveEntry(Playlist playlist, int from, int to) {
    if (from == to) return;
    playlist.entries.insert(to, playlist.entries.removeAt(from));
    _changed();
  }

  /// Drops the entries whose files are gone.
  void removeMissing(Playlist playlist) {
    final resolved = resolve(playlist);
    final keep = resolved.entryIndexes.toSet();
    final kept = [for (final (i, e) in playlist.entries.indexed) if (keep.contains(i)) e];
    playlist.entries
      ..clear()
      ..addAll(kept);
    _changed();
  }

  /// Lookup tables over the library, rebuilt only when the library list is replaced.
  List<Track>? _indexed;
  Map<String, Track> _byUri = const {};
  Map<String, Track> _byFile = const {};

  void _index(List<Track> library) {
    if (identical(library, _indexed)) return;
    _indexed = library;
    _byUri = {for (final t in library) t.uri: t};
    _byFile = {for (final t in library) '${t.displayName}|${t.sizeBytes}': t};
  }

  /// Matches the entries with the library. Without library access, the saved data is used as is.
  ResolvedPlaylist resolve(Playlist playlist) {
    final library = LibraryController.instance.tracks;
    final tracks = <Track>[];
    final indexes = <int>[];
    if (library == null || LibraryController.instance.hasPermission != true) {
      final cuts = {for (final t in LibraryController.instance.savedCuts ?? const <Track>[]) t.uri: t};
      for (final (i, e) in playlist.entries.indexed) {
        tracks.add(cuts[e.uri] ?? Track(uri: e.uri, title: e.title, displayName: e.displayName, sizeBytes: e.sizeBytes));
        indexes.add(i);
      }
      return ResolvedPlaylist(tracks, indexes, 0);
    }
    _index(library);
    var missing = 0;
    for (final (i, e) in playlist.entries.indexed) {
      final track = _byUri[e.uri] ?? _byFile['${e.displayName}|${e.sizeBytes}'];
      if (track == null) {
        missing++;
      } else {
        tracks.add(track);
        indexes.add(i);
      }
    }
    return ResolvedPlaylist(tracks, indexes, missing);
  }

  /// Imports an .m3u/.m3u8 playlist (e.g. exported from Fossify Music Player). Songs are matched
  /// with the library by path, falling back to the file name. Returns the new playlist and how
  /// many lines couldn't be matched.
  Future<({Playlist playlist, int unmatched})> importM3u(String uri) async {
    final file = await NativeBridge.readTextFile(uri);
    final library = LibraryController.instance.tracks ?? const <Track>[];
    final byName = <String, List<Track>>{};
    for (final t in library) {
      byName.putIfAbsent(t.displayName.toLowerCase(), () => []).add(t);
    }

    final tracks = <Track>[];
    var unmatched = 0;
    for (final raw in const LineSplitter().convert(file.text)) {
      final line = raw.trim().replaceAll('\\', '/');
      if (line.isEmpty || line.startsWith('#')) continue;
      final path = Uri.tryParse(line)?.hasScheme == true && line.startsWith('file:')
          ? Uri.decodeFull(Uri.parse(line).path)
          : line;
      final candidates = byName[path.split('/').last.toLowerCase()] ?? const <Track>[];
      final lowerPath = path.toLowerCase();
      final match = candidates.where((t) => lowerPath.endsWith('${t.folder}/${t.displayName}'.toLowerCase())).firstOrNull ??
          candidates.firstOrNull;
      if (match == null) {
        unmatched++;
      } else {
        tracks.add(match);
      }
    }

    final name = withoutExtension(file.name ?? 'Imported playlist');
    final playlist = create(name.isEmpty ? 'Imported playlist' : name);
    addTracks(playlist, tracks);
    return (playlist: playlist, unmatched: unmatched);
  }
}
