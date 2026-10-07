import 'package:flutter/material.dart';

import '../artwork.dart';
import '../theme.dart';

/// Themes taken from a track's cover art, or from the hue of its generated cover when it has
/// none. Used by the player and the playlist page so they take on the colors of their music.
abstract final class TrackColors {
  static final _cache = <String, Future<ThemeData>>{};
  static const _maxEntries = 60;

  static Future<ThemeData> themeFor(String uri, ThemeData base) {
    final black = base.brightness == Brightness.dark && base.colorScheme.surface == Colors.black;
    final key = '$uri|${base.brightness.name}|$black';
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;
    if (_cache.length >= _maxEntries) _cache.remove(_cache.keys.first);
    return _cache[key] = _compute(uri, base, black);
  }

  static Future<ThemeData> _compute(String uri, ThemeData base, bool black) async {
    final covers = base.extension<CoverPalette>()!;
    final brightness = base.brightness;
    ColorScheme? scheme;
    final bytes = await Artwork.load(uri, 160);
    if (bytes != null) {
      try {
        scheme = await ColorScheme.fromImageProvider(provider: MemoryImage(bytes), brightness: brightness);
      } catch (_) {
        // Undecodable image: fall back to the generated cover's color.
      }
    }
    scheme ??= ColorScheme.fromSeed(seedColor: covers.pick(stableHash(uri)).$1, brightness: brightness);
    if (black) scheme = AppTheme.blacken(scheme);
    return AppTheme.build(scheme, covers: covers);
  }
}

/// Recolors [child] with the theme of the track at [uri], fading from one track's colors to the
/// next. Keeps the surrounding theme until the colors are ready.
class TrackThemed extends StatefulWidget {
  const TrackThemed({super.key, required this.uri, required this.child});

  final String? uri;
  final Widget child;

  @override
  State<TrackThemed> createState() => _TrackThemedState();
}

class _TrackThemedState extends State<TrackThemed> {
  ThemeData? _theme;
  Object? _request;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(TrackThemed old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) _resolve();
  }

  void _resolve() {
    final uri = widget.uri;
    final base = Theme.of(context);
    if (uri == null) {
      _request = null;
      _theme = null;
      return;
    }
    final future = TrackColors.themeFor(uri, base);
    if (identical(future, _request)) return;
    _request = future;
    future.then((theme) {
      if (mounted && identical(_request, future)) setState(() => _theme = theme);
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final theme = _theme;
    return AnimatedTheme(
      data: theme != null && theme.brightness == base.brightness ? theme : base,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}
