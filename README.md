# Audio Cutter

A personal Android music app, written in Flutter, in the clean style of the Fossify apps.

- **Playlists first**: create, rename, reorder and shuffle playlists. Add songs from anywhere in the app, or
  import `.m3u` playlists exported from another player (Fossify Music Player, for example).
- **Music player**: Tracks, Albums, Artists and Folders tabs, search, a mini player, a now-playing screen with a
  queue, and background playback with notification and lock-screen controls.
- **Video to audio**: keeps only the soundtrack of a downloaded video.
- **Cut audio**: trim any song or audio file. Drag the handles on the waveform or type exact times, and preview
  the part you selected before saving.

Cuts never lose quality. MP3, AAC (M4A) and Opus audio is copied without re-encoding. Other formats (FLAC, WAV,
Vorbis…) are saved as lossless FLAC. Files go to `Music/AudioCutter`.

You can also send files to the app from other apps: **Share** opens a file in the cutter, and **Open with** plays it.

Requires Android 10 or newer. The app only asks for access to your music library, and only for the player tabs.

## Build

```sh
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the debug key, so it installs directly but can't be published to a store.

Developer notes (architecture, cutting rules, testing status) are in [CLAUDE.md](CLAUDE.md).
