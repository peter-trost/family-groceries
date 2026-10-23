import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Speech to text for the add field.
abstract interface class Dictation() {
  /// False when the device can't recognize speech or the user refused the
  /// microphone.
  Future<bool> prepare();

  /// Listens until the speaker pauses, reporting the words heard so far.
  /// Completes with the final text, or null when nothing was understood.
  Future<String?> listen({required void Function(String words) onWords});

  /// Ends listening early; [listen] completes with what was heard.
  Future<void> stop();
}

/// The platform recognizer (Siri's on iOS, Google's on Android), in German.
class DeviceDictation() implements Dictation {
  final _speech = SpeechToText();
  Completer<String?>? _done;
  var _heard = '';

  void _finish() {
    final done = _done;
    if (done != null && !done.isCompleted) {
      done.complete(_heard.trim().isEmpty ? null : _heard);
    }
  }

  @override
  Future<bool> prepare() async =>
      _speech.isAvailable ||
      await _speech.initialize(
        onStatus: (status) {
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            _finish();
          }
        },
        onError: (_) => _finish(),
      );

  @override
  Future<String?> listen({required void Function(String words) onWords}) async {
    _heard = '';
    final done = _done = Completer<String?>();
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'de_DE',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
      onResult: (result) {
        _heard = result.recognizedWords;
        onWords(_heard);
        if (result.finalResult) {
          _finish();
        }
      },
    );
    return await done.future;
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    _finish();
  }
}
