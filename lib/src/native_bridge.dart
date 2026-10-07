import 'dart:typed_data';

import 'package:flutter/services.dart';

/// An audio file from the device's library (or one of the app's cuts).
class Track {
  const Track({
    required this.uri,
    required this.title,
    this.artist,
    this.album,
    this.albumId = 0,
    this.durationMs = 0,
    this.trackNumber = 0,
    this.sizeBytes = 0,
    this.dateAdded,
    this.displayName = '',
    this.folder = '',
  });

  factory Track.fromMap(Map<Object?, Object?> m) => Track(
        uri: m['uri'] as String,
        title: m['title'] as String,
        artist: m['artist'] as String?,
        album: m['album'] as String?,
        albumId: m['albumId'] as int? ?? 0,
        durationMs: m['durationMs'] as int? ?? 0,
        trackNumber: m['trackNumber'] as int? ?? 0,
        sizeBytes: m['sizeBytes'] as int? ?? 0,
        dateAdded: m['dateAddedMs'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['dateAddedMs'] as int),
        displayName: m['displayName'] as String? ?? '',
        folder: m['folder'] as String? ?? '',
      );

  final String uri;
  final String title;
  final String? artist;
  final String? album;
  final int albumId;
  final int durationMs;

  /// MediaStore track number: disc * 1000 + track.
  final int trackNumber;
  final int sizeBytes;
  final DateTime? dateAdded;
  final String displayName;

  /// Relative folder, e.g. "Music/Daft Punk".
  final String folder;

  String get artistOrUnknown => artist ?? 'Unknown artist';
  String get albumOrUnknown => album ?? 'Unknown album';

  Map<String, Object?> toPlayerMap() => {'uri': uri, 'title': title, 'artist': artist, 'album': album, 'albumId': albumId};
}

/// Basic facts about a file opened in the editor.
class MediaInfo {
  const MediaInfo({
    required this.uri,
    required this.name,
    required this.sizeBytes,
    required this.durationMs,
    required this.hasVideo,
    required this.hasAudio,
    required this.outputExtension,
    required this.copiesOriginal,
  });

  final String uri;
  final String name;
  final int? sizeBytes;
  final int durationMs;
  final bool hasVideo;
  final bool hasAudio;

  /// Extension of the saved cut: "m4a", "mp3", "ogg" or "flac".
  final String outputExtension;

  /// True when the original audio frames are copied (no re-encoding), false when it is stored as lossless FLAC.
  final bool copiesOriginal;
}

class SavedFile {
  const SavedFile(this.uri, this.name);

  final String uri;
  final String name;
}

class Incoming {
  const Incoming({required this.play, required this.uri});

  /// True for "Open with" (play it), false for "Share" (open it in the cutter).
  final bool play;
  final String uri;
}

class PlayerState {
  const PlayerState({
    this.uri,
    this.title,
    this.artist,
    this.album,
    this.albumId = 0,
    this.index = 0,
    this.count = 0,
    this.isPlaying = false,
    this.buffering = false,
    this.positionMs = 0,
    this.durationMs,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
  });

  factory PlayerState.fromMap(Map<Object?, Object?> m) => PlayerState(
        uri: m['uri'] as String?,
        title: m['title'] as String?,
        artist: m['artist'] as String?,
        album: m['album'] as String?,
        albumId: m['albumId'] as int? ?? 0,
        index: m['index'] as int? ?? 0,
        count: m['count'] as int? ?? 0,
        isPlaying: m['isPlaying'] as bool? ?? false,
        buffering: m['buffering'] as bool? ?? false,
        positionMs: m['positionMs'] as int? ?? 0,
        durationMs: m['durationMs'] as int?,
        shuffle: m['shuffle'] as bool? ?? false,
        repeat: RepeatMode.values[(m['repeat'] as int? ?? 0).clamp(0, 2)],
      );

  final String? uri;
  final String? title;
  final String? artist;
  final String? album;
  final int albumId;
  final int index;
  final int count;
  final bool isPlaying;
  final bool buffering;
  final int positionMs;
  final int? durationMs;
  final bool shuffle;
  final RepeatMode repeat;

  bool get hasItem => uri != null;
}

/// Same order as Media3's `Player.REPEAT_MODE_*` constants.
enum RepeatMode { off, one, all }

/// Events pushed by the Android side.
sealed class NativeEvent {
  const NativeEvent();

  static NativeEvent? parse(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw['type']) {
      'incoming' => const IncomingEvent(),
      'player' => PlayerEvent(PlayerState.fromMap(raw)),
      'waveform' => WaveformEvent(raw['token'] as int, raw['levels'] as Float64List),
      'waveformDone' => WaveformDoneEvent(raw['token'] as int),
      'cutProgress' => CutProgressEvent(raw['progress'] as int),
      'preview' => PreviewPositionEvent(raw['positionMs'] as int),
      'previewEnded' => const PreviewEndedEvent(),
      _ => null,
    };
  }
}

class IncomingEvent extends NativeEvent {
  const IncomingEvent();
}

class PlayerEvent extends NativeEvent {
  const PlayerEvent(this.state);

  final PlayerState state;
}

class WaveformEvent extends NativeEvent {
  const WaveformEvent(this.token, this.levels);

  final int token;
  final Float64List levels;
}

class WaveformDoneEvent extends NativeEvent {
  const WaveformDoneEvent(this.token);

  final int token;
}

class CutProgressEvent extends NativeEvent {
  const CutProgressEvent(this.progress);

  /// 0-100.
  final int progress;
}

class PreviewPositionEvent extends NativeEvent {
  const PreviewPositionEvent(this.positionMs);

  final int positionMs;
}

class PreviewEndedEvent extends NativeEvent {
  const PreviewEndedEvent();
}

/// Thin wrapper over the platform channels implemented in `MediaBridge.kt` and `PlayerBridge.kt`.
class NativeBridge {
  NativeBridge._();

  static const _methods = MethodChannel('audio_cutter/media');
  static const _events = EventChannel('audio_cutter/events');

  static final Stream<NativeEvent> events = _events
      .receiveBroadcastStream()
      .map(NativeEvent.parse)
      .where((e) => e != null)
      .cast<NativeEvent>()
      .asBroadcastStream();

  // Files and library

  /// Opens the system file picker. Returns a content uri, or null if the user backed out.
  static Future<String?> pickFile({required bool video}) =>
      _methods.invokeMethod<String>('pickFile', {'kind': video ? 'video' : 'audio'});

  /// Opens the system file picker on playlist files (.m3u).
  static Future<String?> pickPlaylistFile() => _methods.invokeMethod<String>('pickFile', {'kind': 'playlist'});

  /// Reads a small text file picked by the user. Returns its name and content.
  static Future<({String? name, String text})> readTextFile(String uri) async {
    final map = (await _methods.invokeMapMethod<String, Object?>('readTextFile', {'uri': uri}))!;
    return (name: map['name'] as String?, text: map['text'] as String? ?? '');
  }

  /// The saved playlists as JSON, and the previous version kept as a backup (null when absent).
  static Future<({String? main, String? backup})> readPlaylists() async {
    final map = (await _methods.invokeMapMethod<String, Object?>('readPlaylists'))!;
    return (main: map['main'] as String?, backup: map['backup'] as String?);
  }

  static Future<void> writePlaylists(String json) => _methods.invokeMethod('writePlaylists', {'json': json});

  /// A file another app shared with us or asked us to open, if any (consumed on read).
  static Future<Incoming?> takeIncoming() async {
    final map = await _methods.invokeMapMethod<String, Object?>('takeIncoming');
    if (map == null) return null;
    return Incoming(play: map['action'] == 'play', uri: map['uri'] as String);
  }

  /// The app's settings, saved natively in SharedPreferences.
  static Future<Map<String, String>> prefs() async =>
      await _methods.invokeMapMethod<String, String>('getPrefs') ?? const {};

  /// Saving "theme" also tells Android 12+ which night mode to use for the splash screen.
  static Future<void> setPref(String key, String value) => _methods.invokeMethod('setPref', {'key': key, 'value': value});

  /// The Material You accent color on Android 12+, null on older versions.
  static Future<int?> accentColor() => _methods.invokeMethod<int>('accentColor');

  static Future<bool> hasLibraryPermission() async => await _methods.invokeMethod<bool>('hasLibraryPermission') ?? false;

  static Future<bool> requestLibraryPermission() async =>
      await _methods.invokeMethod<bool>('requestLibraryPermission') ?? false;

  static Future<void> openAppSettings() => _methods.invokeMethod('openAppSettings');

  static Future<List<Track>> listTracks() => _tracks('listTracks');

  /// The cuts saved by the app, newest first.
  static Future<List<Track>> listSaved() => _tracks('listSaved');

  static Future<List<Track>> _tracks(String method) async {
    final list = await _methods.invokeListMethod<Map<Object?, Object?>>(method) ?? const [];
    return [for (final m in list) Track.fromMap(m)];
  }

  /// Embedded cover art as JPEG bytes, or null when the file has none.
  static Future<Uint8List?> artwork(String uri, int sizePx) =>
      _methods.invokeMethod<Uint8List>('artwork', {'uri': uri, 'size': sizePx});

  /// Returns false when the user declined the system confirmation.
  static Future<bool> deleteFile(String uri) async => await _methods.invokeMethod<bool>('deleteFile', {'uri': uri}) ?? false;

  static Future<void> shareFile(String uri) => _methods.invokeMethod('shareFile', {'uri': uri});

  /// Copies songs into a folder such as "Music/Playlists/Road trip", skipping those already there.
  /// Returns how many were copied.
  static Future<int> copyToFolder(List<String> uris, String folder) async =>
      await _methods.invokeMethod<int>('copyToFolder', {'uris': uris, 'folder': folder}) ?? 0;

  /// Moves the app's own files from one folder to another.
  static Future<void> renameFolder(String from, String to) =>
      _methods.invokeMethod('renameFolder', {'from': from, 'to': to});

  /// Deletes a file the app created in [folder]. Returns false if it wasn't there or isn't the app's.
  static Future<bool> deleteFromFolder(String folder, String name) async =>
      await _methods.invokeMethod<bool>('deleteFromFolder', {'folder': folder, 'name': name}) ?? false;

  // Cutter

  static Future<MediaInfo> probe(String uri) async {
    final map = (await _methods.invokeMapMethod<String, Object?>('probe', {'uri': uri}))!;
    return MediaInfo(
      uri: uri,
      name: map['name'] as String,
      sizeBytes: map['sizeBytes'] as int?,
      durationMs: map['durationMs'] as int,
      hasVideo: map['hasVideo'] as bool,
      hasAudio: map['hasAudio'] as bool,
      outputExtension: map['outputExtension'] as String,
      copiesOriginal: map['copiesOriginal'] as bool,
    );
  }

  /// Decodes [uri] into loudness levels, pushed as [WaveformEvent]s. Each [slot] ("editor" or
  /// "player") runs one job at a time: starting a new one cancels the previous one in that slot.
  static Future<void> startWaveform(
    String uri, {
    required int durationMs,
    required int token,
    int buckets = 1000,
    String slot = 'editor',
  }) =>
      _methods.invokeMethod('startWaveform', {
        'uri': uri,
        'durationMs': durationMs,
        'token': token,
        'buckets': buckets,
        'slot': slot,
      });

  static Future<void> cancelWaveform({String slot = 'editor'}) => _methods.invokeMethod('cancelWaveform', {'slot': slot});

  /// Saves [startMs]..[endMs] of [uri] to Music/AudioCutter as "[name].ext". Throws a
  /// [PlatformException] on failure (code `cancelled`, `cut_failed` or `busy`).
  static Future<SavedFile> cut({
    required String uri,
    required int startMs,
    required int endMs,
    required String name,
  }) async {
    final map = (await _methods.invokeMapMethod<String, Object?>('cut', {
      'uri': uri,
      'startMs': startMs,
      'endMs': endMs,
      'name': name,
    }))!;
    return SavedFile(map['uri'] as String, map['name'] as String);
  }

  static Future<void> cancelCut() => _methods.invokeMethod('cancelCut');

  static Future<void> previewPrepare(String uri) => _methods.invokeMethod('previewPrepare', {'uri': uri});

  static Future<void> previewStart(String uri, int startMs, int endMs) =>
      _methods.invokeMethod('previewStart', {'uri': uri, 'startMs': startMs, 'endMs': endMs});

  static Future<void> previewSetEnd(int endMs) => _methods.invokeMethod('previewSetEnd', {'endMs': endMs});

  static Future<void> previewStop() => _methods.invokeMethod('previewStop');

  static Future<void> previewRelease() => _methods.invokeMethod('previewRelease');

  // Music player

  static Future<void> play(List<Track> tracks, {int index = 0, bool shuffle = false}) => _methods.invokeMethod(
        'playerPlay',
        {'items': [for (final t in tracks) t.toPlayerMap()], 'index': index, 'shuffle': shuffle},
      );

  static Future<void> togglePlay() => _methods.invokeMethod('playerToggle');

  static Future<void> next() => _methods.invokeMethod('playerNext');

  static Future<void> previous() => _methods.invokeMethod('playerPrevious');

  static Future<void> seek(int positionMs) => _methods.invokeMethod('playerSeek', {'positionMs': positionMs});

  static Future<void> skipTo(int index) => _methods.invokeMethod('playerSkipTo', {'index': index});

  static Future<void> setShuffle(bool enabled) => _methods.invokeMethod('playerSetShuffle', {'enabled': enabled});

  static Future<void> setRepeat(RepeatMode mode) => _methods.invokeMethod('playerSetRepeat', {'mode': mode.index});

  static Future<void> playNext(Track track) => _methods.invokeMethod('playerAddNext', {'item': track.toPlayerMap()});

  static Future<void> addToQueue(Track track) => _methods.invokeMethod('playerAddToQueue', {'item': track.toPlayerMap()});

  static Future<List<Track>> queue() => _tracks('playerQueue');

  /// Asks the player to send its current state again.
  static Future<void> refreshPlayer() => _methods.invokeMethod('playerRefresh');
}
