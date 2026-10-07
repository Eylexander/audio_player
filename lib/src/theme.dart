import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Background and bar colors for generated covers ([GeneratedCover]): the accent and five hues
/// spread around it, all at Material container tones so they sit well together.
@immutable
class CoverPalette extends ThemeExtension<CoverPalette> {
  const CoverPalette(this.swatches);

  final List<(Color background, Color bars)> swatches;

  (Color, Color) pick(int hash) => swatches[hash % swatches.length];

  static CoverPalette of(BuildContext context) => Theme.of(context).extension<CoverPalette>()!;

  static final _cache = <(Color, Brightness), CoverPalette>{};

  static CoverPalette forSeed(Color seed, Brightness brightness) => _cache.putIfAbsent((seed, brightness), () {
        final hsl = HSLColor.fromColor(seed);
        return CoverPalette([
          for (var i = 0; i < 6; i++)
            () {
              final s = ColorScheme.fromSeed(
                seedColor: hsl.withHue((hsl.hue + i * 60) % 360).toColor(),
                brightness: brightness,
              );
              return (s.primaryContainer, s.onPrimaryContainer);
            }(),
        ]);
      });

  @override
  CoverPalette copyWith({List<(Color, Color)>? swatches}) => CoverPalette(swatches ?? this.swatches);

  @override
  CoverPalette lerp(CoverPalette? other, double t) {
    if (other == null || other.swatches.length != swatches.length) return this;
    return CoverPalette([
      for (var i = 0; i < swatches.length; i++)
        (
          Color.lerp(swatches[i].$1, other.swatches[i].$1, t)!,
          Color.lerp(swatches[i].$2, other.swatches[i].$2, t)!,
        ),
    ]);
  }
}

/// FNV-1a: unlike [String.hashCode], the same text gives the same number on every run.
int stableHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

abstract final class AppTheme {
  static const font = 'Manrope';

  static ColorScheme scheme(Color seed, Brightness brightness, {bool black = false}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return black && brightness == Brightness.dark ? blacken(scheme) : scheme;
  }

  /// The dark scheme on true black, for OLED screens. Containers keep a trace of their tint.
  static ColorScheme blacken(ColorScheme s) {
    Color darker(Color c) => Color.lerp(c, Colors.black, 0.5)!;
    return s.copyWith(
      surface: Colors.black,
      surfaceDim: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: darker(s.surfaceContainerLow),
      surfaceContainer: darker(s.surfaceContainer),
      surfaceContainerHigh: darker(s.surfaceContainerHigh),
      surfaceContainerHighest: darker(s.surfaceContainerHighest),
    );
  }

  static TextTheme _text(TextTheme t) {
    TextStyle? w(TextStyle? style, FontWeight weight, double spacing) =>
        style?.copyWith(fontWeight: weight, letterSpacing: spacing);
    return t.copyWith(
      displayLarge: w(t.displayLarge, FontWeight.w800, -1.6),
      displayMedium: w(t.displayMedium, FontWeight.w800, -1.4),
      displaySmall: w(t.displaySmall, FontWeight.w800, -1.2),
      headlineLarge: w(t.headlineLarge, FontWeight.w800, -1.0),
      headlineMedium: w(t.headlineMedium, FontWeight.w800, -0.8),
      headlineSmall: w(t.headlineSmall, FontWeight.w800, -0.5),
      titleLarge: w(t.titleLarge, FontWeight.w700, -0.3),
      titleMedium: w(t.titleMedium, FontWeight.w700, -0.1),
      titleSmall: w(t.titleSmall, FontWeight.w700, 0),
      bodyLarge: w(t.bodyLarge, FontWeight.w500, 0),
      bodyMedium: w(t.bodyMedium, FontWeight.w500, 0),
      bodySmall: w(t.bodySmall, FontWeight.w500, 0.1),
      labelLarge: w(t.labelLarge, FontWeight.w700, 0.1),
      labelMedium: w(t.labelMedium, FontWeight.w700, 0.2),
      labelSmall: w(t.labelSmall, FontWeight.w700, 0.4),
    );
  }

  /// Every color comes from [s], so a screen can be recolored by building a theme from another
  /// scheme (see `TrackThemed`).
  static ThemeData build(ColorScheme s, {required CoverPalette covers}) {
    final dark = s.brightness == Brightness.dark;
    final base = ThemeData(colorScheme: s, fontFamily: font);
    final text = _text(base.textTheme);
    final overlay = (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
    const rounded16 = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)));
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: s.surface,
      extensions: [covers],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        foregroundColor: s.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: s.onSurface),
        systemOverlayStyle: overlay,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: s.surfaceContainer,
        indicatorColor: s.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected) ? s.onSurface : s.onSurfaceVariant,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 44), textStyle: text.labelLarge),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44), textStyle: text.labelLarge),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: text.labelLarge)),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700, color: s.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: s.onSurfaceVariant),
        leadingAndTrailingTextStyle: text.labelMedium?.copyWith(color: s.onSurfaceVariant),
        minVerticalPadding: 10,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceContainerHigh,
        titleTextStyle: text.headlineSmall?.copyWith(color: s.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceContainerLow,
        modalBackgroundColor: s.surfaceContainerLow,
        showDragHandle: true,
        dragHandleColor: s.onSurfaceVariant.withValues(alpha: 0.4),
      ),
      popupMenuTheme: PopupMenuThemeData(color: s.surfaceContainerHigh, shape: rounded16),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: s.onInverseSurface),
        actionTextColor: s.inversePrimary,
        shape: rounded16,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerHighest,
        border: const OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(16))),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: s.primary, width: 2),
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: s.error, width: 1.5),
          borderRadius: const BorderRadius.all(Radius.circular(16)),
        ),
      ),
      dividerTheme: DividerThemeData(color: s.outlineVariant.withValues(alpha: 0.5), space: 1),
    );
  }
}
