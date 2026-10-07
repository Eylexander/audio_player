import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'native_bridge.dart';
import 'ui/generated_cover.dart';

class _CacheEntry {
  _CacheEntry(this.future);

  final Future<Uint8List?> future;
  bool done = false;
  Uint8List? bytes;
}

/// Cover art of a track, or a generated cover when the file has none.
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.uri, required this.size, this.radius = 12});

  final String? uri;
  final double size;
  final double radius;

  /// Insertion-ordered (Dart maps are), which makes it a simple LRU cache. Keyed by file, not
  /// album: MediaStore puts loose files (e.g. all of Download/) in one "album" per folder.
  static final _cache = <String, _CacheEntry>{};
  static const _maxEntries = 300;

  static _CacheEntry _entry(String uri, int px) {
    final key = '$uri@$px';
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached; // Move to the most recently used end.
    if (_cache.length >= _maxEntries) _cache.remove(_cache.keys.first);
    late final _CacheEntry entry;
    entry = _CacheEntry(NativeBridge.artwork(uri, px).catchError((_) => null).then((bytes) {
      entry
        ..bytes = bytes
        ..done = true;
      return bytes;
    }));
    return _cache[key] = entry;
  }

  /// JPEG bytes of the cover at about [px] pixels, or null when the file has none.
  static Future<Uint8List?> load(String uri, int px) => _entry(uri, px).future;

  @override
  Widget build(BuildContext context) {
    final source = uri;
    // Round the requested size up to a few buckets so list rows and pages share the cache.
    final wanted = size * MediaQuery.devicePixelRatioOf(context);
    final px = wanted <= 160 ? 160 : wanted <= 320 ? 320 : 720;

    Widget content(Uint8List? bytes) => bytes == null
        ? GeneratedCover(key: const ValueKey('generated'), seed: source ?? '')
        : Image.memory(
            bytes,
            key: const ValueKey('art'),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );

    final Widget image;
    if (source == null) {
      image = content(null);
    } else {
      final entry = _entry(source, px);
      image = entry.done
          ? content(entry.bytes) // Already known: draw it right away, no fade while scrolling.
          : FutureBuilder<Uint8List?>(
              future: entry.future,
              builder: (context, snapshot) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: snapshot.connectionState == ConnectionState.done
                    ? content(snapshot.data)
                    : ColoredBox(
                        key: const ValueKey('loading'),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const SizedBox.expand(),
                      ),
              ),
            );
    }

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: image),
    );
  }
}
