import 'package:flutter/material.dart';

/// A scrolling page that opens on a big bold title (or a custom [header]). The title moves into
/// the app bar once the header has scrolled away.
///
/// Meant for a Scaffold with `extendBody: true`: the end of the list is padded so the last rows
/// can scroll clear of the mini player.
class HeaderScrollView extends StatefulWidget {
  const HeaderScrollView({
    super.key,
    required this.title,
    this.subtitle,
    this.header,
    this.actions = const [],
    required this.slivers,
    this.transparentAppBar = false,
    this.collapseOffset = 56,
  });

  final String title;
  final String? subtitle;

  /// Replaces the big title and [subtitle].
  final Widget? header;
  final List<Widget> actions;
  final List<Widget> slivers;

  /// Lets a background drawn behind the page show through until content scrolls under the bar.
  final bool transparentAppBar;

  /// How far to scroll before the title shows in the app bar.
  final double collapseOffset;

  @override
  State<HeaderScrollView> createState() => _HeaderScrollViewState();
}

class _HeaderScrollViewState extends State<HeaderScrollView> {
  final _scroll = ScrollController();
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final collapsed = _scroll.offset > widget.collapseOffset;
      if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final resting = widget.transparentAppBar ? Colors.transparent : colors.surface;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.scrolledUnder) ? colors.surfaceContainer : resting,
          ),
          title: AnimatedOpacity(
            opacity: _collapsed ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: Text(widget.title),
          ),
          actions: [...widget.actions, const SizedBox(width: 4)],
        ),
        SliverToBoxAdapter(
          child: widget.header ??
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: theme.textTheme.displaySmall?.copyWith(color: colors.onSurface)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle!,
                        style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
        ),
        ...widget.slivers,
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
      ],
    );
  }
}
