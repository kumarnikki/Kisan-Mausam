class VoiceWebHelper {
  static bool get isSupported => false;

  static void speak(String text, {String lang = 'hi-IN'}) {}

  static void stopSpeaking() {}

  static bool get isSpeaking => false;

  static bool startListening({
    String lang = 'hi-IN',
    required Function(String text) onResult,
    required Function(String error) onError,
    required Function() onEnd,
  }) => false;

  static void stopListening() {}
}
