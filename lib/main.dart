import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_shell.dart';
import 'src/native_bridge.dart';
import 'src/settings.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Settings.instance.load();
  runApp(const AudioCutterApp());
}

class AudioCutterApp extends StatefulWidget {
  const AudioCutterApp({super.key});

  @override
  State<AudioCutterApp> createState() => _AudioCutterAppState();
}

class _AudioCutterAppState extends State<AudioCutterApp> {
  /// Used on Android < 12, where there's no system accent color to follow.
  static const _fallbackSeed = Color(0xFF3949AB);

  Color _seed = _fallbackSeed;
  final _themes = <(Color, Brightness, bool), ThemeData>{};

  @override
  void initState() {
    super.initState();
    NativeBridge.accentColor().then((argb) {
      if (argb != null && mounted) setState(() => _seed = Color(argb));
    }, onError: (_) {});
  }

  ThemeData _theme(Brightness brightness, {bool black = false}) => _themes.putIfAbsent(
        (_seed, brightness, black),
        () => AppTheme.build(
          AppTheme.scheme(_seed, brightness, black: black),
          covers: CoverPalette.forSeed(_seed, brightness),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final settings = Settings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Audio Cutter',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark, black: settings.pureBlack),
        themeMode: settings.themeMode,
        // Status and navigation bar icons that match the theme, under every screen.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: Theme.of(context).appBarTheme.systemOverlayStyle!,
          child: child!,
        ),
        home: const AppShell(),
      ),
    );
  }
}
