// phase-04
// speech_to_text behind a seam. One-shot dictation: start, collect
// until the recognizer emits a final result, stop. The widget layer
// shows a live partial overlay via a status callback-free design —
// this port only ever RESOLVES once with the settled sentence.
//
// speech_to_text runs on the device speech service — offline where
// the OEM supports it. UDAO adds no network permission of its own,
// so nothing UDAO-controlled ever uploads audio.
//
// The plugin's own finalTimeout (2s after last partial) already
// promotes a stalled partial to final; we ALSO keep the last partial
// ourselves so a bare `notListening` (user paused, service gave up)
// still resolves with something usable instead of an error.
import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';

abstract class VoiceInput {
  /// Whether a speech service exists on this device.
  Future<bool> initialize();

  /// Dictates once. Resolves with the final recognized sentence.
  /// `Err(CaptureFailure('voice_timeout'))` if nothing at all was
  /// heard within [timeout]; `Err(CaptureFailure('voice_error'))`
  /// if the recognizer errored; `Err(CaptureFailure(
  /// 'voice_unavailable'))` if no speech service exists.
  Future<Result<String>> listenOnce({
    String localeId = 'en-IN',
    Duration timeout = const Duration(seconds: 12),
  });

  /// Hard stop (user dismissed the sheet mid-listen).
  Future<void> stop();
}

class SpeechToTextInput implements VoiceInput {
  SpeechToTextInput({stt.SpeechToText? speech})
      : _speech = speech ?? stt.SpeechToText();

  final stt.SpeechToText _speech;

  Completer<Result<String>>? _pending;
  String _lastPartial = '';

  @override
  Future<bool> initialize() => _speech.initialize(
        // Callback param types are inferred from the plugin typedefs
        // (SpeechRecognitionError lives in its own library — the
        // annotation would need an extra import for zero value).
        onError: (error) => _settleErr('voice_error'),
        onStatus: (String status) {
          if (status == 'notListening') {
            _settleFromServiceEnd();
          }
        },
      );

  @override
  Future<Result<String>> listenOnce({
    String localeId = 'en-IN',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!_speech.isAvailable) {
      final bool ok = await initialize();
      if (!ok) {
        return const Err<String>(CaptureFailure('voice_unavailable'));
      }
    }

    final Completer<Result<String>> completer =
        Completer<Result<String>>();
    _pending = completer;
    _lastPartial = '';

    unawaited(
      _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            _complete(Ok<String>(result.recognizedWords));
          } else if (result.recognizedWords.trim().isNotEmpty) {
            _lastPartial = result.recognizedWords;
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
          localeId: localeId,
        ),
      ),
    );

    final Timer timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _speech.stop();
        _settlePartialOrTimeout();
      }
    });

    return completer.future.whenComplete(timer.cancel);
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    _settleFromServiceEnd();
  }

  // ---- internals ---------------------------------------------------

  void _complete(Result<String> value) {
    final Completer<Result<String>>? pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(value);
    }
  }

  void _settleErr(String code) =>
      _complete(Err<String>(CaptureFailure(code)));

  /// Service ended without a final result: keep the best partial
  /// (Hinglish speakers pause mid-sentence), else report timeout.
  void _settleFromServiceEnd() => _settlePartialOrTimeout();

  void _settlePartialOrTimeout() {
    final String partial = _lastPartial.trim();
    if (partial.isNotEmpty) {
      _complete(Ok<String>(partial));
    } else {
      _settleErr('voice_timeout');
    }
  }
}
