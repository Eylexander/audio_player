import 'package:flutter/material.dart';

import 'native_bridge.dart';
import 'player/mini_player.dart';
import 'theme.dart';
import 'ui/common.dart';
import 'ui/header_scroll_view.dart';

/// The user's preferences, saved natively (SharedPreferences).
class Settings extends ChangeNotifier {
  Settings._();

  static final instance = Settings._();

  ThemeMode themeMode = ThemeMode.system;

  /// True black backgrounds in the dark theme.
  bool pureBlack = false;

  /// Playlists as a grid of covers (true) or a list.
  bool playlistGrid = true;

  /// The user was already offered "Media management" before a move ([offerManageMedia]).
  bool offeredManageMedia = false;

  /// Called before the first frame, so a saved dark theme doesn't start out light.
  Future<void> load() async {
    try {
      final prefs = await NativeBridge.prefs().timeout(const Duration(seconds: 2));
      themeMode = ThemeMode.values.asNameMap()[prefs['theme']] ?? ThemeMode.system;
      pureBlack = prefs['pureBlack'] == 'true';
      playlistGrid = prefs['playlistView'] != 'list';
      offeredManageMedia = prefs['offeredManageMedia'] == 'true';
    } catch (_) {
      // Keep the defaults.
    }
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == themeMode) return;
    themeMode = mode;
    _save('theme', mode.name);
  }

  void setPureBlack(bool value) {
    if (value == pureBlack) return;
    pureBlack = value;
    _save('pureBlack', '$value');
  }

  void setPlaylistGrid(bool value) {
    if (value == playlistGrid) return;
    playlistGrid = value;
    _save('playlistView', value ? 'grid' : 'list');
  }

  void setOfferedManageMedia() {
    if (offeredManageMedia) return;
    offeredManageMedia = true;
    _save('offeredManageMedia', 'true');
  }

  void _save(String key, String value) {
    notifyListeners();
    NativeBridge.setPref(key, value).catchError((_) {});
  }
}

const sourceUrl = 'https://github.com/Eylexander/audio_player';

Future<void> openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));

/// Theme, version and source. The playlist layout is switched from the Playlists tab itself.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Future<({String name, int code})> _version = NativeBridge.appInfo();
  late Future<bool?> _manageMedia = NativeBridge.canManageMedia();

  Future<void> _requestManageMedia() async {
    // Asked again afterwards: the answer given right as the permission dialog closes can be stale.
    final granted = NativeBridge.requestManageMedia().then((_) => NativeBridge.canManageMedia());
    setState(() => _manageMedia = granted);
  }

  Future<void> _openSource() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await NativeBridge.openUrl(sourceUrl)) showSnack(messenger, 'No browser to open $sourceUrl');
  }

  @override
  Widget build(BuildContext context) {
    final settings = Settings.instance;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      extendBody: true,
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => HeaderScrollView(
          title: 'Settings',
          slivers: [
            const SliverToBoxAdapter(child: SectionLabel('Theme')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    for (final (i, mode) in ThemeMode.values.indexed) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _ThemeChoice(
                          mode: mode,
                          black: settings.pureBlack,
                          selected: settings.themeMode == mode,
                          onTap: () => settings.setThemeMode(mode),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: const Text('Pure black'),
                subtitle: const Text('Black backgrounds in the dark theme. Easier on OLED screens and batteries.'),
                value: settings.pureBlack,
                onChanged: settings.themeMode == ThemeMode.light ? null : settings.setPureBlack,
              ),
            ),
            SliverToBoxAdapter(
              child: FutureBuilder(
                future: _manageMedia,
                builder: (context, snapshot) {
                  // Android 10 and 11 don't have this access.
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final granted = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Files'),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                        leading: Icon(granted ? Icons.folder_special_rounded : Icons.folder_outlined),
                        title: const Text('Move songs without asking'),
                        subtitle: Text(
                          granted
                              ? 'On. Playlists move songs into their folders without a confirmation for each file.'
                              : 'Android asks before each move into a playlist folder. Allow “Media management” '
                                  'to skip that (Android also asks about “photos and videos”: choose “Allow all”).',
                        ),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                        onTap: _requestManageMedia,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SectionLabel('About')),
            SliverToBoxAdapter(
              child: FutureBuilder(
                future: _version,
                builder: (context, snapshot) {
                  final version = snapshot.data;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Version'),
                    subtitle: Text(switch ((version, snapshot.hasError)) {
                      (_, true) => 'Unknown',
                      (null, _) => '…',
                      (final v?, _) => '${v.name} (build ${v.code})',
                    }),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: const Icon(Icons.code_rounded),
                title: const Text('Source code'),
                subtitle: Text(sourceUrl.replaceFirst('https://', '')),
                trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                onTap: _openSource,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Cuts never lose quality: the audio is copied as it is, or stored as lossless FLAC. '
                  'Saved to Music/AudioCutter.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const MiniPlayer(),
    );
  }
}

/// A miniature screen in the colors of [mode], to pick the theme by sight.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.mode, required this.black, required this.selected, required this.onTap});

  final ThemeMode mode;
  final bool black;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final seed = colors.primary;
    final light = AppTheme.scheme(seed, Brightness.light);
    final dark = AppTheme.scheme(seed, Brightness.dark, black: black);
    final label = switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 104,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 3 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 15 : 17),
                child: switch (mode) {
                  ThemeMode.light => _MiniScreen(light),
                  ThemeMode.dark => _MiniScreen(dark),
                  ThemeMode.system => Row(
                      children: [
                        Expanded(child: _MiniScreen(light)),
                        Expanded(child: _MiniScreen(dark)),
                      ],
                    ),
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[Icon(Icons.check_circle_rounded, size: 16, color: colors.primary), const SizedBox(width: 4)],
                Text(label, style: theme.textTheme.labelLarge?.copyWith(color: selected ? colors.primary : colors.onSurface)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniScreen extends StatelessWidget {
  const _MiniScreen(this.scheme);

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    Widget line(double widthFactor, double height, Color color) => FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: Alignment.centerLeft,
          child: Container(
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
          ),
        );
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(0.7, 8, scheme.onSurface),
          const SizedBox(height: 6),
          line(0.45, 5, scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          const Spacer(),
          Container(
            height: 22,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Expanded(child: line(0.8, 4, scheme.onPrimaryContainer.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
