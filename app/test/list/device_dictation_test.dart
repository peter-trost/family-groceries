import 'package:family_groceries/list/dictation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// The native side of speech_to_text: records what the app asked for.
class _Recognizer() extends SpeechToTextPlatform {
  final listened = <SpeechListenOptions?>[];

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async => true;

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    listened.add(options);
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}

  void says(String words) => onTextRecognition!(
    '{"alternates":[{"recognizedWords":"$words","confidence":0.9}],'
    '"resultType":${ResultType.finalResult.value}}',
  );

  void fails(String error) =>
      onError!('{"errorMsg":"$error","permanent":true}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Recognizer recognizer;
  late DeviceDictation dictation;

  void offlineGerman({required bool installed}) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            DeviceDictation.offlineGerman,
            (call) async => call.method == 'offlineGerman' ? installed : null,
          );

  setUp(() {
    recognizer = _Recognizer();
    SpeechToTextPlatform.instance = recognizer;
    dictation = DeviceDictation(speech: SpeechToText.withMethodChannel());
  });

  test('listens in German on the device only', () async {
    offlineGerman(installed: true);
    expect(await dictation.prepare(), isNull);

    final dictated = dictation.listen(onWords: (_) {});
    await pumpEventQueue();
    recognizer.says('Milch und Brot');

    expect(
      await dictated,
      isA<Heard>().having((h) => h.text, 'text', 'Milch und Brot'),
    );
    final options = recognizer.listened.single!;
    expect(options.onDevice, isTrue);
    expect(options.localeId, 'de_DE');
  });

  test('without offline German it never starts listening', () async {
    offlineGerman(installed: false);
    expect(await dictation.prepare(), DictationProblem.noOfflineGerman);
    expect(recognizer.listened, isEmpty);
  });

  test('a platform without the check counts as no offline German', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DeviceDictation.offlineGerman, null);
    expect(await dictation.prepare(), DictationProblem.noOfflineGerman);
  });

  for (final error in [
    'error_language_not_supported',
    'error_language_unavailable',
  ]) {
    test(
      'the on-device recognizer reporting $error is no offline German',
      () async {
        offlineGerman(installed: true);
        await dictation.prepare();
        final dictated = dictation.listen(onWords: (_) {});
        await pumpEventQueue();
        recognizer.fails(error);

        expect(
          await dictated,
          isA<Refused>().having(
            (r) => r.problem,
            'problem',
            DictationProblem.noOfflineGerman,
          ),
        );
      },
    );
  }

  test('other recognizer errors end with nothing heard', () async {
    offlineGerman(installed: true);
    await dictation.prepare();
    final dictated = dictation.listen(onWords: (_) {});
    await pumpEventQueue();
    recognizer.fails('error_no_match');

    expect(await dictated, isA<NothingHeard>());
  });
}
