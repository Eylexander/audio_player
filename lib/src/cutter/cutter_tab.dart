import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../formatting.dart';
import '../library/library_controller.dart';
import '../library/track_tile.dart';
import '../native_bridge.dart';
import '../player/player_controller.dart';
import '../ui/common.dart';
import '../ui/header_scroll_view.dart';
import 'editor_page.dart';

/// The two cutter entry points (cut audio, video to audio) and the cuts saved so far.
class CutterTab extends StatelessWidget {
  const CutterTab({super.key});

  Future<void> _pick(BuildContext context, {required bool video}) async {
    final uri = await NativeBridge.pickFile(video: video);
    if (uri != null && context.mounted) await openEditor(context, uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final library = LibraryController.instance;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final saved = library.savedCuts;
        return RefreshIndicator(
          onRefresh: library.load,
          edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
          child: HeaderScrollView(
            title: 'Cutter',
            subtitle: 'Lossless: the audio is never re-encoded',
            actions: homeActions(context),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ToolCard(
                            art: _ToolArt.cut,
                            background: colors.primaryContainer,
                            foreground: colors.onPrimaryContainer,
                            title: 'Cut audio',
                            subtitle: 'Keep just the part of a song you want',
                            onTap: () => _pick(context, video: false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ToolCard(
                            art: _ToolArt.video,
                            background: colors.tertiaryContainer,
                            foreground: colors.onTertiaryContainer,
                            title: 'Video to audio',
                            subtitle: 'Keep only the soundtrack of a video',
                            onTap: () => _pick(context, video: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SectionLabel('Saved cuts', trailing: saved == null || saved.isEmpty ? null : '${saved.length}'),
              ),
              if (saved == null)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                )
              else if (saved.isEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.content_cut_rounded, color: colors.onSurfaceVariant),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Nothing yet. Your cuts are saved to Music/AudioCutter and listed here. '
                            'Any song can also be cut from its menu.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: saved.length,
                  itemBuilder: (context, i) {
                    final track = saved[i];
                    final dot = track.displayName.lastIndexOf('.');
                    return TrackTile(
                      track: track,
                      badge: dot > 0 ? track.displayName.substring(dot + 1).toUpperCase() : null,
                      subtitle: [
                        if (track.durationMs > 0) formatShort(track.durationMs),
                        formatSize(track.sizeBytes),
                        if (track.dateAdded != null) formatDate(track.dateAdded!),
                      ].join(' · '),
                      onTap: () => PlayerController.instance.playAll(saved, index: i),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _ToolArt { cut, video }

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.art,
    required this.background,
    required this.foreground,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final _ToolArt art;
  final Color background;
  final Color foreground;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 56,
                width: double.infinity,
                child: CustomPaint(painter: _ToolArtPainter(art, foreground)),
              ),
              const SizedBox(height: 20),
              Text(title, style: theme.textTheme.titleMedium?.copyWith(color: foreground)),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: foreground.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Little drawings in the style of the launcher icon: waveform bars with a selection bracket
/// for "Cut audio", a film frame turning into bars for "Video to audio".
class _ToolArtPainter extends CustomPainter {
  _ToolArtPainter(this.art, this.color);

  final _ToolArt art;
  final Color color;

  static const _heights = [0.22, 0.42, 0.7, 1.0, 0.55, 0.32, 0.18, 0.36, 0.6, 0.3];

  void _bars(Canvas canvas, Size size, double left, int count, bool Function(int i) strong) {
    const barWidth = 4.0;
    const gap = 4.0;
    final paint = Paint()
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    final centerY = size.height / 2;
    for (var i = 0; i < count; i++) {
      final x = left + i * (barWidth + gap) + barWidth / 2;
      final half = math.max(0.0, size.height * 0.8 * _heights[i % _heights.length] - barWidth) / 2;
      paint.color = strong(i) ? color : color.withValues(alpha: 0.4);
      canvas.drawLine(Offset(x, centerY - half), Offset(x, centerY + half), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (art) {
      case _ToolArt.cut:
        const count = 9;
        _bars(canvas, size, 0, count, (i) => i >= 2 && i <= 4);
        // The bracket around the kept part, as in the icon.
        final stroke = Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        const left = 2 * 8.0 - 4;
        const right = 5 * 8.0;
        canvas.drawPath(
          Path()
            ..moveTo(left + 4, 1)
            ..lineTo(left, 1)
            ..lineTo(left, size.height - 1)
            ..lineTo(left + 4, size.height - 1)
            ..moveTo(right - 4, 1)
            ..lineTo(right, 1)
            ..lineTo(right, size.height - 1)
            ..lineTo(right - 4, size.height - 1),
          stroke,
        );
      case _ToolArt.video:
        // A film frame with sprocket holes...
        final frame = RRect.fromRectAndRadius(Rect.fromLTWH(1, 6, 40, size.height - 12), const Radius.circular(6));
        canvas.drawRRect(
          frame,
          Paint()
            ..color = color.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
        final holes = Paint()..color = color.withValues(alpha: 0.4);
        for (var i = 0; i < 4; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(6 + i * 8.5, 10, 4, 4), const Radius.circular(1)),
            holes,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(6 + i * 8.5, size.height - 14, 4, 4), const Radius.circular(1)),
            holes,
          );
        }
        // ...an arrow...
        final arrow = Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final y = size.height / 2;
        canvas.drawPath(
          Path()
            ..moveTo(50, y)
            ..lineTo(64, y)
            ..moveTo(59, y - 5)
            ..lineTo(64, y)
            ..lineTo(59, y + 5),
          arrow,
        );
        // ...and the sound that's kept.
        _bars(canvas, size, 74, 5, (_) => true);
    }
  }

  @override
  bool shouldRepaint(_ToolArtPainter old) => old.art != art || old.color != color;
}
