package com.petertrost.familygroceries

import android.content.Intent
import android.os.Build
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "familygroceries/speech")
            .setMethodCallHandler { call, result ->
                if (call.method == "offlineGerman") offlineGerman(result::success) else result.notImplemented()
            }
    }

    /**
     * Whether speech_to_text's onDevice listening gets the on-device recognizer
     * (otherwise it silently uses the network one) and that recognizer has German.
     */
    private fun offlineGerman(answer: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        ) {
            answer(false)
            return
        }
        // Android 12 can't list on-device languages. Without German, listening
        // fails with ERROR_LANGUAGE_UNAVAILABLE, which the app explains the same way.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            answer(true)
            return
        }
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
        recognizer.checkRecognitionSupport(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH),
            mainExecutor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    recognizer.destroy()
                    answer(support.installedOnDeviceLanguages.any { it.startsWith("de") })
                }

                override fun onError(error: Int) {
                    recognizer.destroy()
                    answer(false)
                }
            },
        )
    }
}
