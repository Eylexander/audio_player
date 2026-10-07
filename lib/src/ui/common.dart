import 'package:flutter/material.dart';

/// Shows a snack bar once the current frame is over. Snack bars that follow an `await` can
/// otherwise land while a closing page's Scaffold is deactivated but not yet disposed (it stays
/// registered with the messenger until then), and `showSnackBar` throws on it.
void showSnack(ScaffoldMessengerState messenger, String text) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (messenger.mounted) messenger.showSnackBar(SnackBar(content: Text(text)));
  });
  WidgetsBinding.instance.scheduleFrame();
}

/// A friendly placeholder for empty lists, missing permissions and searches with no results.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(30)),
              child: Icon(icon, size: 40, color: colors.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Small heading above a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Row(
        children: [
          Text(text, style: theme.textTheme.titleMedium?.copyWith(color: colors.primary)),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: theme.textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// A tiny label such as "FLAC" next to a file's details.
class FormatBadge extends StatelessWidget {
  const FormatBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: colors.onSecondaryContainer, letterSpacing: 0.6),
      ),
    );
  }
}
