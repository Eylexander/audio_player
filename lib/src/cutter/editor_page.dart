import 'package:flutter/material.dart';

import '../formatting.dart';
import '../library/library_controller.dart';
import '../native_bridge.dart';
import '../player/player_controller.dart';
import '../playlists/playlists_ui.dart';
import 'editor_controller.dart';
import 'waveform_selector.dart';

/// Opens [uri] in the editor, and refreshes the library once the user is done.
Future<void> openEditor(BuildContext context, String uri) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EditorPage(uri: uri)));
  LibraryController.instance.load();
}

/// Pick the part to keep, preview it and save it, without losing quality.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.uri});

  final String uri;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final EditorController _controller = EditorController(widget.uri);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final title = switch (c.info) {
          MediaInfo(hasVideo: true) => 'Video to audio',
          MediaInfo() => 'Cut audio',
          null => '',
        };
        return PopScope(
          canPop: !c.isSaving,
          child: Scaffold(
            appBar: AppBar(title: Text(title)),
            body: c.isLoading
                ? const Center(child: CircularProgressIndicator())
                : c.loadError != null
                    ? _ErrorView(message: c.loadError!)
                    : _EditorBody(controller: c),
            bottomNavigationBar: c.info == null ? null : _SaveBar(controller: c),
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton.tonal(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
          ],
        ),
      ),
    );
  }
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final info = c.info!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locked = c.isSaving;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _FileHeader(info: info),
        const SizedBox(height: 20),
        IgnorePointer(
          ignoring: locked,
          child: WaveformSelector(
            levels: c.levels,
            durationMs: c.durationMs,
            startMs: c.startMs,
            endMs: c.endMs,
            playheadMs: c.playheadMs,
            onStartChanged: c.setStart,
            onEndChanged: c.setEnd,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (c.analyzing) ...[
              const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Drawing waveform…', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ] else
              Expanded(
                child: Text(
                  'Drag the handles, or tap the waveform, to choose the part to keep.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _TimeCard(
                label: 'Start',
                ms: c.startMs,
                enabled: !locked,
                onNudge: c.nudgeStart,
                onEdit: () => _editTime(context, 'Start time', c.startMs, c.setStart),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimeCard(
                label: 'End',
                ms: c.endMs,
                enabled: !locked,
                onNudge: c.nudgeEnd,
                onEdit: () => _editTime(context, 'End time', c.endMs, c.setEnd),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Length', style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant)),
                  Text(
                    formatPrecise(c.selectionMs),
                    style: theme.textTheme.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
            if (!c.isFullRange)
              TextButton(onPressed: locked ? null : c.selectAll, child: const Text('Select all')),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: locked ? null : c.togglePreview,
              icon: Icon(c.previewing ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(c.previewing ? 'Stop' : 'Preview'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        TextField(
          controller: c.nameController,
          enabled: !locked,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'File name',
            suffixText: '.${info.outputExtension}',
            prefixIcon: const Icon(Icons.edit_outlined),
          ),
        ),
        const SizedBox(height: 16),
        _QualityNote(info: info),
      ],
    );
  }

  Future<void> _editTime(BuildContext context, String title, int currentMs, ValueChanged<int> onSet) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _TimeDialog(title: title, initialMs: currentMs, maxMs: controller.durationMs),
    );
    if (result != null) onSet(result);
  }
}

/// Tells what the saved file will be, and that nothing is lost.
class _QualityNote extends StatelessWidget {
  const _QualityNote({required this.info});

  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final format = info.outputExtension.toUpperCase();
    final text = info.copiesOriginal
        ? 'Saved as $format with the original audio copied as-is: no re-encoding, no quality loss.'
        : 'Saved as $format, a lossless format: the cut keeps the full quality of the original.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_rounded, color: colors.onSecondaryContainer),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.copiesOriginal ? 'Original quality' : 'Lossless',
                  style: theme.textTheme.titleSmall?.copyWith(color: colors.onSecondaryContainer),
                ),
                const SizedBox(height: 2),
                Text(text, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSecondaryContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.info});

  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final details = [
      info.hasVideo ? 'Video' : 'Audio',
      formatShort(info.durationMs),
      if (info.sizeBytes != null) formatSize(info.sizeBytes!),
    ].join(' · ');
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Icon(info.hasVideo ? Icons.movie_rounded : Icons.music_note_rounded, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(details, style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.label,
    required this.ms,
    required this.enabled,
    required this.onNudge,
    required this.onEdit,
  });

  final String label;
  final int ms;
  final bool enabled;
  final ValueChanged<int> onNudge;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
        child: Column(
          children: [
            Text(label.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: colors.primary, letterSpacing: 1.2)),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? onEdit : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  formatPrecise(ms),
                  style: theme.textTheme.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  tooltip: '-0.1 s',
                  onPressed: enabled ? () => onNudge(-1) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: '+0.1 s',
                  onPressed: enabled ? () => onNudge(1) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeDialog extends StatefulWidget {
  const _TimeDialog({required this.title, required this.initialMs, required this.maxMs});

  final String title;
  final int initialMs;
  final int maxMs;

  @override
  State<_TimeDialog> createState() => _TimeDialogState();
}

class _TimeDialogState extends State<_TimeDialog> {
  late final TextEditingController _text = TextEditingController(text: formatPrecise(widget.initialMs))
    ..selection = TextSelection(baseOffset: 0, extentOffset: formatPrecise(widget.initialMs).length);

  int? get _value {
    final ms = parseTime(_text.text);
    return ms != null && ms <= widget.maxMs ? ms : null;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.datetime,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (value != null) Navigator.pop(context, value);
        },
        decoration: InputDecoration(
          hintText: 'm:ss.s',
          helperText: 'Between 0:00.0 and ${formatPrecise(widget.maxMs)}',
          errorText: value == null ? 'Enter a time like 1:23.4' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: value == null ? null : () => Navigator.pop(context, value), child: const Text('Set')),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final Widget content = switch (c.phase) {
      SavePhase.running => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: c.progress == null ? null : c.progress! / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Text(c.progress == null ? 'Saving…' : 'Saving… ${c.progress}%')),
                TextButton(onPressed: c.cancelSave, child: const Text('Cancel')),
              ],
            ),
          ],
        ),
      SavePhase.done => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Saved to Music/AudioCutter as “${c.saved!.name}”', style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => PlayerController.instance.playAll([
                    Track(uri: c.saved!.uri, title: withoutExtension(c.saved!.name)),
                  ]),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Add to playlist',
                  onPressed: () => showAddToPlaylistSheet(context, [
                    Track(uri: c.saved!.uri, title: withoutExtension(c.saved!.name), displayName: c.saved!.name),
                  ]),
                  icon: const Icon(Icons.playlist_add_rounded),
                ),
                IconButton.outlined(
                  tooltip: 'Share',
                  onPressed: () => NativeBridge.shareFile(c.saved!.uri),
                  icon: const Icon(Icons.share_outlined),
                ),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ],
            ),
          ],
        ),
      SavePhase.idle || SavePhase.failed => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.saveError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colors.error),
                    const SizedBox(width: 12),
                    Expanded(child: Text(c.saveError!, style: TextStyle(color: colors.error))),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: c.save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.save_alt_rounded),
                label: Text(c.phase == SavePhase.failed ? 'Try again' : 'Save audio'),
              ),
            ),
          ],
        ),
    };

    return Material(
      color: colors.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.bottomCenter,
            child: content,
          ),
        ),
      ),
    );
  }
}
