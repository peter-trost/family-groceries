import 'dart:async';

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Why the microphone can't take a sentence.
enum DictationProblem() {
  /// No recognizer, or the user refused the microphone or speech recognition.
  unavailable,

  /// The device can't recognize German without sending the audio to a
  /// server, and spoken words stay on the device (spec).
  noOfflineGerman,
}

/// What came of one listening session.
sealed class Dictated();

final class Heard(final String text) extends Dictated;

final class NothingHeard() extends Dictated;

final class Refused(final DictationProblem problem) extends Dictated;

/// Speech to text for the add field.
abstract interface class Dictation() {
  /// Null when [listen] can start, otherwise why it can't.
  Future<DictationProblem?> prepare();

  /// Listens until the speaker pauses, reporting the words heard so far.
  Future<Dictated> listen({required void Function(String words) onWords});

  /// Ends listening early; [listen] completes with what was heard.
  Future<void> stop();
}

/// The platform recognizer (Siri's on iOS, Google's on Android), in German
/// and on the device only.
class DeviceDictation({SpeechToText? speech}) implements Dictation {
  /// The app's own check (MainActivity.kt, AppDelegate.swift): with
  /// `onDevice` speech_to_text 7.5 falls back to the network recognizer on
  /// Android and can't tell whether German is installed.
  static const offlineGerman = MethodChannel('familygroceries/speech');

  /// The on-device recognizer's answer on Android when German isn't
  /// installed (SpeechRecognizer.ERROR_LANGUAGE_*).
  static const _noLanguage = {
    'error_language_not_supported',
    'error_language_unavailable',
  };

  final SpeechToText _speech = speech ?? SpeechToText();
  Completer<Dictated>? _done;
  var _heard = '';
  DictationProblem? _problem;

  void _finish() {
    final done = _done;
    if (done != null && !done.isCompleted) {
      done.complete(switch (_problem) {
        final problem? => Refused(problem),
        null when _heard.trim().isEmpty => NothingHeard(),
        null => Heard(_heard),
      });
    }
  }

  @override
  Future<DictationProblem?> prepare() async {
    final ready =
        _speech.isAvailable ||
        await _speech.initialize(
          onStatus: (status) {
            if (status == SpeechToText.doneStatus ||
                status == SpeechToText.notListeningStatus) {
              _finish();
            }
          },
          onError: (error) {
            if (_noLanguage.contains(error.errorMsg)) {
              _problem = DictationProblem.noOfflineGerman;
            }
            _finish();
          },
        );
    if (!ready) {
      return DictationProblem.unavailable;
    }
    try {
      return await offlineGerman.invokeMethod<bool>('offlineGerman') ?? false
          ? null
          : DictationProblem.noOfflineGerman;
    } on Exception {
      return DictationProblem.noOfflineGerman;
    }
  }

  @override
  Future<Dictated> listen({
    required void Function(String words) onWords,
  }) async {
    _heard = '';
    _problem = null;
    final done = _done = Completer<Dictated>();
    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'de_DE',
          onDevice: true,
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
    } on ListenFailedException {
      _problem = DictationProblem.unavailable;
      _finish();
    }
    return await done.future;
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    _finish();
  }
}
