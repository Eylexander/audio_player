import 'dart:async';

import 'package:flutter/material.dart';

import 'cutter/cutter_tab.dart';
import 'cutter/editor_page.dart';
import 'formatting.dart';
import 'library/folders_tab.dart';
import 'library/library_controller.dart';
import 'native_bridge.dart';
import 'player/mini_player.dart';
import 'player/now_playing_page.dart';
import 'player/player_controller.dart';
import 'player/track_waveform.dart';
import 'playlists/playlist_store.dart';
import 'playlists/playlists_tab.dart';
import 'search_page.dart';
import 'settings.dart';

/// Search and settings, at the top right of every tab.
List<Widget> homeActions(BuildContext context) => [
      IconButton(
        tooltip: 'Search',
        onPressed: () => openSearch(context),
        icon: const Icon(Icons.search_rounded),
      ),
      IconButton(
        tooltip: 'Settings',
        onPressed: () => showSettingsSheet(context),
        icon: const Icon(Icons.tune_rounded),
      ),
    ];

/// Main screen: Playlists (the default), Folders and Cutter, with the mini player above the
/// navigation bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late final StreamSubscription<NativeEvent> _events;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events = NativeBridge.events.listen((event) {
      if (event is IncomingEvent) _handleIncoming();
    });
    LibraryController.instance.load();
    PlaylistStore.instance.load();
    TrackWaveforms.init();
    _handleIncoming();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) LibraryController.instance.load();
  }

  /// A file from another app: "Share" opens it in the cutter, "Open with" plays it.
  Future<void> _handleIncoming() async {
    final incoming = await NativeBridge.takeIncoming();
    if (incoming == null || !mounted) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    if (!incoming.play) {
      await openEditor(context, incoming.uri);
      return;
    }
    var title = 'Audio';
    try {
      title = withoutExtension((await NativeBridge.probe(incoming.uri)).name);
    } catch (_) {}
    await PlayerController.instance.playAll([Track(uri: incoming.uri, title: title)]);
    if (mounted) openNowPlaying(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from another tab returns to Playlists before leaving the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        extendBody: true,
        body: _FadeIndexedStack(
          index: _tab,
          children: const [PlaylistsTab(), FoldersTab(), CutterTab()],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(safeArea: false),
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music_rounded),
                  label: 'Playlists',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder_rounded),
                  label: 'Folders',
                ),
                NavigationDestination(
                  icon: Icon(Icons.content_cut_outlined),
                  selectedIcon: Icon(Icons.content_cut_rounded),
                  label: 'Cutter',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps every tab alive (scroll positions survive) and fades the selected one in.
class _FadeIndexedStack extends StatefulWidget {
  const _FadeIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<_FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 240), value: 1);
  late final _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final _slide = Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(_fade);

  @override
  void didUpdateWidget(_FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: IndexedStack(
          index: widget.index,
          children: [
            for (final (i, child) in widget.children.indexed) TickerMode(enabled: i == widget.index, child: child),
          ],
        ),
      ),
    );
  }
}
