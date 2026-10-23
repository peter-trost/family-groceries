import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OfflineSpeech") {
      OfflineSpeech.register(with: registrar)
    }
  }
}

/// Answers lib/list/dictation.dart's check: speech_to_text reports a device
/// without on-device German only once listening has started.
final class OfflineSpeech: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "familygroceries/speech", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(OfflineSpeech(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "offlineGerman" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(SFSpeechRecognizer(locale: Locale(identifier: "de_DE"))?.supportsOnDeviceRecognition ?? false)
  }
}
