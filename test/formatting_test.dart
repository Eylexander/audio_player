import 'package:audio_cutter/src/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatPrecise', () {
    expect(formatPrecise(0), '0:00.0');
    expect(formatPrecise(75300), '1:15.3');
    expect(formatPrecise(3725000), '1:02:05.0');
    expect(formatPrecise(-5), '0:00.0');
  });

  test('formatShort', () {
    expect(formatShort(205000), '3:25');
    expect(formatShort(3725000), '1:02:05');
  });

  test('parseTime accepts the usual notations', () {
    expect(parseTime('42'), 42000);
    expect(parseTime('1:15.3'), 75300);
    expect(parseTime('1 15,3'), 75300);
    expect(parseTime('1:02:05'), 3725000);
    expect(parseTime(formatPrecise(3725400)), 3725400);
  });

  test('parseTime rejects garbage', () {
    expect(parseTime(''), isNull);
    expect(parseTime('abc'), isNull);
    expect(parseTime('1:-2'), isNull);
    expect(parseTime('1::2'), isNull);
    expect(parseTime('1:2:3:4'), isNull);
  });

  test('sanitizeFileName', () {
    expect(sanitizeFileName('a/b:c*?.mp3'), 'a_b_c__.mp3');
    expect(sanitizeFileName('  ..hidden.. '), 'hidden');
  });

  test('withoutExtension', () {
    expect(withoutExtension('My video.mp4'), 'My video');
    expect(withoutExtension('.nomedia'), '.nomedia');
    expect(withoutExtension('noext'), 'noext');
  });

  test('formatTotalDuration', () {
    expect(formatTotalDuration(4200), '4 s');
    expect(formatTotalDuration(45 * 60000), '45 min');
    expect(formatTotalDuration(65 * 60000), '1 h 05 min');
  });

  test('formatSize', () {
    expect(formatSize(512), '512 B');
    expect(formatSize(2 * 1024 * 1024 + 400 * 1024), '2.4 MB');
  });
}
