# Audio Cutter

Personal Android app (Flutter UI + Kotlin media engine) written for the user, who likes the clean look of the
Fossify apps (Fossify Music Player in particular) but wanted more features. It does three things:

1. **Music player** in the style of Fossify Music Player, with background playback, notification and lock-screen controls.
2. **Video to audio**: keeps only the soundtrack of a downloaded video.
3. **Cut audio**: trims any audio file to the part you want to keep.

## What the user asked for (keep these in mind)

- **Playlists are the main way they use the app**. The Tracks/Albums/Artists tabs were removed at their request;
  the app has three tabs: Playlists (default), Folders, Cutter. Songs are found through Folders, search and the
  song picker.
- **Cuts must always keep the best possible quality**: no lossy re-encoding, ever (see "Cutting rules").
- Clean but **not generic** UI (see "Design"). Uses the Material You accent color on Android 12+. Light, dark and
  pure-black themes.

## Commands

The shell is Git Bash on Windows. JDK: `~/.jdks/jbr-21.0.9` (Android Studio's JBR isn't installed). Flutter
3.32.7 is in `~/SDKs/flutter`; Android SDK is in `%LOCALAPPDATA%/Android/Sdk`.

```sh
export JAVA_HOME=~/.jdks/jbr-21.0.9
flutter analyze
flutter test                      # test/formatting_test.dart
flutter build apk --debug         # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release       # release is signed with the debug key so it installs directly
```

Emulator: AVD `Medium_Phone_API_36.0` (x86_64). Start it with `$LOCALAPPDATA/Android/Sdk/emulator/emulator.exe -avd Medium_Phone_API_36.0`.
adb lives at `$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`.

## Architecture

- `lib/` is the Flutter UI only. No pub dependencies beyond the SDK (state is plain `ChangeNotifier` singletons).
  The Manrope font is bundled in `assets/fonts/` (SIL OFL), as static weights 400–800: Flutter doesn't map
  `FontWeight` onto a variable font's axis.
- `android/app/src/main/kotlin/com/eylexander/audio_cutter/` holds all media work, using Android codecs plus
  Media3 (ExoPlayer and session). There is no FFmpeg.
- Two platform channels, both implemented in `MediaBridge.kt`:
  - `audio_cutter/media` (methods). The `player*` methods are delegated to `PlayerBridge.kt`.
  - `audio_cutter/events`: maps with a `type` field: `incoming`, `player`, `waveform`, `waveformDone`, `cutProgress`,
    `preview`, `previewEnded`. They are parsed in `lib/src/native_bridge.dart` (`NativeEvent`).

| Path | Role |
| --- | --- |
| `lib/main.dart` | Loads settings before the first frame, builds light/dark/black themes from the accent color |
| `lib/src/theme.dart` | `AppTheme.build(scheme)` (every color comes from the scheme), `blacken`, `CoverPalette`, `stableHash` |
| `lib/src/settings.dart` | `Settings` (theme mode, pure black, playlist grid/list; saved natively) and the settings sheet |
| `lib/src/app_shell.dart` | NavigationBar (Playlists, Folders, Cutter), mini player above it, `homeActions`, files from other apps |
| `lib/src/search_page.dart` | Search across playlists, folders and songs |
| `lib/src/ui/` | `GeneratedCover`, `PlayingBars`, `HeaderScrollView` (big title page), `EmptyState`, `SectionLabel`, `FormatBadge` |
| `lib/src/native_bridge.dart` | All channel calls and models (`Track`, `PlayerState`, `MediaInfo`…) |
| `lib/src/playlists/playlist_store.dart` | Playlists model, persistence, matching entries to library tracks, M3U import |
| `lib/src/playlists/` (UI) | `playlists_tab.dart` (cover grid or list), `playlist_page.dart` (page, reorder, song picker), `playlists_ui.dart` (dialogs, sheets, mosaic cover) |
| `lib/src/library/` | `LibraryController` (MediaStore tracks plus folder grouping), Folders tab and page, `TrackTile` + action sheet |
| `lib/src/player/` | `PlayerController`, `MiniPlayer`, `NowPlayingPage`, `TrackColors`/`TrackThemed`, `TrackWaveforms` + `WaveformSeekBar` |
| `lib/src/cutter/` | Cutter tab, editor (waveform with bracket handles, typed times, preview, save), `EditorController` |
| `lib/src/artwork.dart` | Cover art via `ContentResolver.loadThumbnail`, LRU-cached **per file** in Dart; generated cover when none |
| `MediaBridge.kt` | Channel handler: picker, permissions, library, playlist file I/O, prefs, probe, waveform, cut, preview player |
| `PlayerBridge.kt` | `MediaController` to `PlaybackService`. Emits player state on change, plus every 250 ms while playing |
| `PlaybackService.kt` | `MediaSessionService` + ExoPlayer (audio focus, becoming-noisy, wake lock) |
| `media/AudioCutter.kt` | Quality-preserving cutter (see below) |
| `media/WaveformExtractor.kt` | Decodes audio into 1000 RMS buckets, pushed progressively |
| `media/MediaProbe.kt` | Name, size, duration, track types, audio codec |
| `data/AudioLibrary.kt` | MediaStore queries, saving cuts to `Music/AudioCutter`, delete (with system confirmation), thumbnails |

## Design

- Motif: the launcher icon's waveform bars and selection bracket. It shows up as generated covers (7 bars, outer
  ones faint, colors from `CoverPalette`: the accent plus five hues 60° apart at container tones, picked by a
  stable hash of the URI), the Cutter cards' drawings, the editor's bracket handles and the "playing" bars.
  Most of the user's files (downloads) have no cover art, so the generated covers matter.
- Big ExtraBold titles (`HeaderScrollView`); the title moves into the app bar on scroll.
- Track-colored screens: `TrackThemed` rebuilds the whole theme from the cover's colors
  (`ColorScheme.fromImageProvider`) or from the generated cover's hue, and animates between tracks. Used by the
  mini player, the now-playing screen and the playlist page (first song).
- Now-playing seek bar is the track's **real waveform**, decoded natively in the `player` waveform slot (the
  editor uses the `editor` slot, so they never cancel each other), only while that screen is open, 240 buckets,
  cached for 40 tracks. Its tokens are negative to never match the editor's.
- Pages put the mini player in `bottomNavigationBar` with `extendBody: true`; `HeaderScrollView` pads its end by
  `MediaQuery.paddingOf(context).bottom`. `MiniPlayer` keeps the system bar's height even when hidden.
- Theme setting: Flutter `ThemeMode`, plus `UiModeManager.setApplicationNightMode` on Android 12+ so the splash
  screen and window background match (no white flash). Settings are SharedPreferences strings (`getPrefs`/`setPref`).
- Song menus are bottom sheets (`showTrackActions`, `showPlaylistActions`), not popup menus.

## Cutting rules (`AudioCutter.kt`)

These rules come from the user's "always best quality" requirement:

- AAC is copied into `.m4a` with `MediaMuxer` (MPEG-4). MP3 is copied frame by frame into `.mp3`. Opus is copied
  into `.ogg` with `MediaMuxer` (OGG). None of these re-encode anything. Cuts land on frame boundaries (~20–26 ms).
- Everything else (FLAC, WAV, Vorbis, AC-3…) is decoded and written as **FLAC** with the platform encoder. These cuts
  are sample-accurate. The STREAMINFO total-sample count is patched afterwards, because a streaming encoder leaves it
  at 0. If there's no FLAC encoder (or it rejects float input, possible on Android 10–11), the fallback is WAV,
  which is also lossless.
- The decoder is asked for **float** PCM so 24-bit sources stay 24-bit, *except* for `audio/raw` tracks. Android's
  extractor already decodes `.flac` and WAV files to raw PCM, and the raw "decoder" is a passthrough that reports
  whatever encoding you request while still delivering 16-bit data. Requesting float there corrupted the output
  (duration halved). Don't reintroduce that.
- Media3 Transformer was used at first and then dropped: setting `AudioEncoderSettings` (a bitrate) forces it to
  re-encode even AAC sources.
- The output format and whether the audio is copied are reported by `probe` (`outputExtension`, `copiesOriginal`)
  and shown in the editor.

## Other gotchas found while testing

- MediaStore rows that haven't been scanned yet have NULL `is_ringtone`/`is_alarm`/`is_notification`. Filter with
  `IS NOT 1`, not `= 0`, or fresh downloads disappear from the library.
- Save cuts **without** `MIME_TYPE` in `ContentValues`, so MediaStore derives the type from the extension and keeps
  the file name intact.
- Media items lose their playback URI when going from a controller to the session.
  `PlaybackService.onAddMediaItems` rebuilds it from `mediaId`, which is the content URI.
- Notification artwork uses `content://media/external/audio/albumart/<albumId>`. It hasn't been checked visually.
- The editor's preview ExoPlayer takes audio focus, which pauses the music player. That's intended.
- **ANR when another screen covers the app** (e.g. the file picker): since Flutter 3.29, Dart runs on Android's
  main thread, and the main thread blocked in `FlutterJNI.onSurfaceDestroyed` for more than 5 s. The fix is
  `io.flutter.embedding.android.DisableMergedPlatformUIThread = true` (application meta-data in the manifest).
  Don't remove it. The renderer is Impeller (OpenGLES on the emulator).
- Snack bars shown after an `await` go through `showSnack` (`lib/src/ui/common.dart`), which waits for the end of
  the frame. Calling `showSnackBar` directly crashed ("Looking up a deactivated widget's ancestor") when a page
  was closing at that moment: a Scaffold stays registered with the messenger until it's disposed. Found with
  `adb shell monkey -p com.eylexander.audio_cutter --pct-syskeys 5 --pct-appswitch 0 --pct-anyevent 0 --throttle 30 -s 42 3000`
  (back up `Download/`, `Music/AudioCutter/` and `playlists.json` first: monkey can tap Delete).
- A Scaffold's `bottomNavigationBar` is **not** lifted above the keyboard. Screens with a search field and a bottom
  button (the song picker) pad the bar by `MediaQuery.viewInsetsOf(context).bottom`.

## Playlists

- Stored as JSON in `filesDir/playlists.json`, with the previous version in `playlists.json.bak`
  (native `readPlaylists` returns both; `writePlaylists` writes them).
- **Saving must never lose data.** An early version ran saves in parallel. Two back-to-back changes (create, then
  add songs, as in the M3U import) raced on the temp file, and a failed rename led to the real file being deleted.
  The user's own test playlist was lost that way. Now:
  - Native writes are `synchronized`: write and `fsync` a temp file, copy the current file to `.bak`, then
    `Files.move(…, ATOMIC_MOVE, REPLACE_EXISTING)`. Nothing is ever deleted.
  - Dart chains saves (`_saving.then(...)`) so they run in order, each one encoding the latest state.
  - Loading falls back to `.bak`. If the file can't be read (I/O error, or neither copy parses), `_canSave` is
    turned off for the session, so the file is never overwritten with an empty list.
- Each entry keeps `uri`, `title`, `displayName` and `sizeBytes`. If the URI no longer matches a library track, the
  entry is matched again by `displayName|sizeBytes`. Entries that still don't match count as "missing", and the page
  offers "Remove missing songs".
- Duplicate songs are skipped when adding.
- M3U import (`importM3u`): lines are matched to library tracks by file name, preferring a track whose
  `folder/displayName` is a suffix of the line. This is meant for playlists exported from Fossify Music Player.
- Songs can be added from: the song picker on the playlist page, any track's menu ("Add to playlist…"), the
  now-playing screen, and the editor's "Saved" bar.

## Status (2026-10-07)

Verified on the API 36 emulator:

- Video to audio (AAC copied, audio-only `.m4a`).
- Cuts: MP3 (output is a byte-exact slice of the source), Opus from `.opus` and `.mka` (to `.ogg`), FLAC 16-bit and
  24-bit (bit depth kept), Vorbis and WAV (to FLAC, sample-accurate durations). MediaStore parses all of them.
- The permission flow, library tabs, cover art, background playback (media session reports PLAYING), the mini player
  and the now-playing screen.
- Playlists: create; add songs through the picker (search included, songs kept in the order checked); reorder by
  long-press and drag; remove from playlist; delete a playlist (with confirmation); play; M3U import ("3 songs, 1
  not found" with one missing line, the right files matched by path). Changes survive force-stop and app restarts;
  the file and its `.bak` were checked directly after an import followed by an immediate force-stop.
- The release APK (`build/app/outputs/flutter-apk/app-release.apk`, 48 MB, includes all the fixes above): loads the
  playlists and plays one with full metadata.
- No ANR when opening the file picker since the merged-thread opt-out.

**Not verified yet:**

- The song picker's "Add" button above a **docked** keyboard. Gboard on the AVD switched to floating mode during
  scripted taps, so only the floating keyboard was tested.
- Notification and lock-screen artwork.
- "Share" and "Open with" coming from other apps. adb can't grant the URI permission a real share would.
- Deleting a file the app doesn't own (system confirmation dialog).
- Android 10–11 devices (the FLAC float encoder may be missing there, which triggers the WAV fallback).

## Testing on the emulator

- In Git Bash, set `MSYS_NO_PATHCONV=1` before `adb push … /sdcard/...`. Otherwise the path gets rewritten to `C:/Program Files/Git/sdcard`.
- `uiautomator dump` hangs while music plays, because the progress bar keeps the UI from ever going idle. Pause playback first.
- In the file picker, "Recent" shows no audio files. Open the side menu and go to Downloads.
- `adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Download/<file>` forces a scan.
- Test media is short fixtures from `androidx/media` (`libraries/test_data/src/test/assets/media/...`) plus a
  generated 60 s tone WAV. They are already in the AVD's `Download/`, and test cuts are in `Music/AudioCutter/`.
- `adb shell cmd uimode night yes|no` switches the emulator's dark mode (the app follows it on "System").
- Flutter semantics show up in the uiautomator dump as `content-desc` (title and subtitle joined by `&#10;`).
  Icon buttons expose their tooltip as Android tooltip text, not `content-desc`, so tap them by position.
- Long-press-and-drag (playlist reordering) needs raw events, because `input draganddrop` doesn't hold long enough:
  `input motionevent DOWN x y; sleep 1.2; input motionevent MOVE x y2 …; input motionevent UP x y2`.
- `Download/Road trip.m3u` on the AVD is an M3U test file (3 existing songs plus 1 missing one).
- After `adb install -r`, a file picker opened by the old process can stay on top of the task. Force-stop and
  relaunch before testing.
- `logcat -c` doesn't clear `am_anr` entries; use `logcat -b all -c`, and `dumpsys dropbox --print data_app_anr`
  for ANR stack traces.
- On a fresh emulator boot, the debug build takes ~10 s before its first frame. Wait before tapping.
- Debug and release are signed with the same key, so `adb install -r` switches between them and keeps app data.
  `run-as` (to read `files/playlists.json`) only works with the debug build.

## Possible next steps

Export playlists to M3U, sleep timer, equalizer, sort options for lists, and a better app name ("Audio Cutter" now
undersells the player).

## Redesign (2026-10-07)

Verified on the emulator: light, dark and pure black; Playlists grid; playlist page colored by its cover;
generated covers; mini player; now playing with the real waveform being drawn; Cutter tab with format badges;
settings sheet. Not yet checked after the redesign: the song picker, search, playlist reordering, the editor's
new handles, the Folders tab and the release build.
