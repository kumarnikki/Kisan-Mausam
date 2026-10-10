import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class VoiceWebHelper {
  static bool get isSupported => true;

  static void speak(String text, {String lang = 'hi-IN'}) {
    try {
      final kisanVoice = globalContext.getProperty('kisanVoice'.toJS) as JSObject?;
      if (kisanVoice != null) {
        kisanVoice.callMethod('speak'.toJS, text.toJS, lang.toJS);
      }
    } catch (_) {}
  }

  static void stopSpeaking() {
    try {
      final kisanVoice = globalContext.getProperty('kisanVoice'.toJS) as JSObject?;
      if (kisanVoice != null) {
        kisanVoice.callMethod('stopSpeaking'.toJS);
      }
    } catch (_) {}
  }

  static bool get isSpeaking {
    try {
      final kisanVoice = globalContext.getProperty('kisanVoice'.toJS) as JSObject?;
      if (kisanVoice != null) {
        final res = kisanVoice.callMethod('isSpeaking'.toJS) as JSBoolean?;
        return res?.toDart ?? false;
      }
    } catch (_) {}
    return false;
  }

  static bool startListening({
    String lang = 'hi-IN',
    required Function(String text) onResult,
    required Function(String error) onError,
    required Function() onEnd,
  }) {
    try {
      final kisanVoice = globalContext.getProperty('kisanVoice'.toJS) as JSObject?;
      if (kisanVoice != null) {
        final onResultJS = ((JSString val) {
          onResult(val.toDart);
        }).toJS;
        final onErrorJS = ((JSString err) {
          onError(err.toDart);
        }).toJS;
        final onEndJS = (() {
          onEnd();
        }).toJS;

        final res = kisanVoice.callMethod(
          'startListening'.toJS,
          lang.toJS,
          onResultJS,
          onErrorJS,
          onEndJS,
        ) as JSBoolean?;
        return res?.toDart ?? false;
      }
    } catch (_) {}
    return false;
  }

  static void stopListening() {
    try {
      final kisanVoice = globalContext.getProperty('kisanVoice'.toJS) as JSObject?;
      if (kisanVoice != null) {
        kisanVoice.callMethod('stopListening'.toJS);
      }
    } catch (_) {}
  }
}
