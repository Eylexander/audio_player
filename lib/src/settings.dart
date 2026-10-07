import 'package:flutter/material.dart';

import 'native_bridge.dart';
import 'theme.dart';

/// The user's preferences, saved natively (SharedPreferences).
class Settings extends ChangeNotifier {
  Settings._();

  static final instance = Settings._();

  ThemeMode themeMode = ThemeMode.system;

  /// True black backgrounds in the dark theme.
  bool pureBlack = false;

  /// Playlists as a grid of covers (true) or a list.
  bool playlistGrid = true;

  /// Called before the first frame, so a saved dark theme doesn't start out light.
  Future<void> load() async {
    try {
      final prefs = await NativeBridge.prefs().timeout(const Duration(seconds: 2));
      themeMode = ThemeMode.values.asNameMap()[prefs['theme']] ?? ThemeMode.system;
      pureBlack = prefs['pureBlack'] == 'true';
      playlistGrid = prefs['playlistView'] != 'list';
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

  void _save(String key, String value) {
    notifyListeners();
    NativeBridge.setPref(key, value).catchError((_) {});
  }
}

Future<void> showSettingsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SettingsSheet(),
    );

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final settings = Settings.instance;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 20),
              Text('Theme', style: theme.textTheme.titleSmall?.copyWith(color: colors.primary)),
              const SizedBox(height: 12),
              Row(
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
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pure black'),
                subtitle: const Text('Black backgrounds in the dark theme. Easier on OLED screens and batteries.'),
                value: settings.pureBlack,
                onChanged: settings.themeMode == ThemeMode.light ? null : settings.setPureBlack,
              ),
              const SizedBox(height: 12),
              Text('Playlists', style: theme.textTheme.titleSmall?.copyWith(color: colors.primary)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded), label: Text('Covers')),
                    ButtonSegment(value: false, icon: Icon(Icons.view_list_rounded), label: Text('List')),
                  ],
                  selected: {settings.playlistGrid},
                  onSelectionChanged: (value) => settings.setPlaylistGrid(value.first),
                ),
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 16),
              Text('Audio Cutter', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Cuts never lose quality: the audio is copied as it is, or stored as lossless FLAC. '
                'Saved to Music/AudioCutter.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
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
