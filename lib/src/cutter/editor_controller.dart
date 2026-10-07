import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../formatting.dart';
import '../native_bridge.dart';

enum SavePhase { idle, running, done, failed }

/// State and actions of the editor screen for one file.
class EditorController extends ChangeNotifier {
  EditorController(this.uri) {
    _events = NativeBridge.events.listen(_onEvent);
    nameController.addListener(_onNameChanged);
    _load();
  }

  static const minSelectionMs = 100;
  static const nudgeMs = 100;
  static int _nextToken = 0;

  final String uri;
  final nameController = TextEditingController();
  final int _token = ++_nextToken;
  late final StreamSubscription<NativeEvent> _events;
  String _lastName = '';
  bool _disposed = false;

  MediaInfo? info;
  String? loadError;

  int startMs = 0;
  int endMs = 0;

  /// Loudness per time slice, filled in progressively. Null until the first chunk is decoded.
  Float64List? levels;
  bool analyzing = false;

  bool previewing = false;
  int? playheadMs;

  SavePhase phase = SavePhase.idle;
  int? progress;
  SavedFile? saved;
  String? saveError;

  bool get isLoading => info == null && loadError == null;
  int get durationMs => info?.durationMs ?? 0;
  int get selectionMs => endMs - startMs;
  bool get isSaving => phase == SavePhase.running;
  bool get isFullRange => startMs == 0 && endMs == durationMs;

  Future<void> _load() async {
    try {
      final result = await NativeBridge.probe(uri);
      if (_disposed) return;
      if (!result.hasAudio) {
        loadError = "This file doesn't contain any audio.";
      } else if (result.durationMs <= 0) {
        loadError = "Couldn't read how long this file is.";
      } else {
        info = result;
        endMs = result.durationMs;
        analyzing = true;
        nameController.text = sanitizeFileName(withoutExtension(result.name));
        NativeBridge.startWaveform(uri, durationMs: result.durationMs, token: _token);
        NativeBridge.previewPrepare(uri);
      }
    } on PlatformException {
      if (_disposed) return;
      loadError = "Couldn't open this file. It may have been moved or its format isn't supported.";
    }
    notifyListeners();
  }

  void _onEvent(NativeEvent event) {
    switch (event) {
      case WaveformEvent(:final token, levels: final data) when token == _token:
        levels = data;
      case WaveformDoneEvent(:final token) when token == _token:
        analyzing = false;
      case PreviewPositionEvent(:final positionMs) when previewing:
        playheadMs = positionMs;
      case PreviewEndedEvent() when previewing:
        previewing = false;
        playheadMs = null;
      case CutProgressEvent(progress: final value) when isSaving:
        progress = value;
      default:
        return;
    }
    notifyListeners();
  }

  // Selection

  void setStart(int ms) {
    startMs = ms.clamp(0, math.max(0, endMs - minSelectionMs));
    _selectionChanged(restartPreview: true);
  }

  void setEnd(int ms) {
    endMs = ms.clamp(math.min(durationMs, startMs + minSelectionMs), durationMs);
    _selectionChanged();
  }

  void nudgeStart(int steps) => setStart(startMs + steps * nudgeMs);

  void nudgeEnd(int steps) => setEnd(endMs + steps * nudgeMs);

  void selectAll() {
    startMs = 0;
    endMs = durationMs;
    _selectionChanged(restartPreview: true);
  }

  void _selectionChanged({bool restartPreview = false}) {
    if (previewing) {
      if (restartPreview) {
        NativeBridge.previewStart(uri, startMs, endMs);
      } else {
        NativeBridge.previewSetEnd(endMs);
      }
    }
    _resetFinishedSave();
    notifyListeners();
  }

  void _onNameChanged() {
    if (nameController.text == _lastName) return;
    _lastName = nameController.text;
    if (phase == SavePhase.done || phase == SavePhase.failed) {
      _resetFinishedSave();
      notifyListeners();
    }
  }

  /// After a save (or a failure), any change means the user is preparing another save.
  void _resetFinishedSave() {
    if (phase == SavePhase.done || phase == SavePhase.failed) {
      phase = SavePhase.idle;
      saved = null;
      saveError = null;
    }
  }

  // Preview

  void togglePreview() {
    if (previewing) {
      stopPreview();
      return;
    }
    previewing = true;
    playheadMs = startMs;
    NativeBridge.previewStart(uri, startMs, endMs);
    notifyListeners();
  }

  void stopPreview() {
    if (!previewing) return;
    previewing = false;
    playheadMs = null;
    NativeBridge.previewStop();
    notifyListeners();
  }

  // Save

  Future<void> save() async {
    if (info == null || isSaving) return;
    stopPreview();
    final name = sanitizeFileName(nameController.text);
    phase = SavePhase.running;
    progress = null;
    saved = null;
    saveError = null;
    notifyListeners();
    try {
      final result = await NativeBridge.cut(uri: uri, startMs: startMs, endMs: endMs, name: name.isEmpty ? 'audio' : name);
      if (_disposed) return;
      saved = result;
      phase = SavePhase.done;
    } on PlatformException catch (e) {
      if (_disposed) return;
      if (e.code == 'cancelled') {
        phase = SavePhase.idle;
      } else {
        phase = SavePhase.failed;
        saveError = "Couldn't save the audio${e.message != null ? ': ${e.message}' : '.'}";
      }
    }
    notifyListeners();
  }

  void cancelSave() {
    if (isSaving) NativeBridge.cancelCut();
  }

  @override
  void dispose() {
    _disposed = true;
    _events.cancel();
    if (isSaving) NativeBridge.cancelCut();
    NativeBridge.cancelWaveform();
    NativeBridge.previewRelease();
    nameController.dispose();
    super.dispose();
  }
}
