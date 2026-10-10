import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'voice_web_helper.dart';

/// Unified Voice Service providing real Text-To-Speech (TTS)
/// and real Speech-To-Text (STT) for Hindi ('hi-IN') and Indian English ('en-IN')
/// across both Web (localhost:3000) and Android mobile devices.
class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  bool _isTtsInitialized = false;
  bool _isSttInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  /// Clean text from markdown bold/bullets so speech synthesis sounds fluent.
  static String cleanTextForSpeech(String raw) {
    var text = raw;
    text = text.replaceAll(RegExp(r'\*\*|\*|#{1,6}\s*'), '');
    text = text.replaceAll(RegExp(r'^[•\-\*]\s*', multiLine: true), ' ');
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'[#_~`]'), '');
    return text.trim();
  }

  /// Initialize TTS engine on mobile devices
  Future<void> _ensureTtsInitialized() async {
    if (_isTtsInitialized || kIsWeb) return;
    try {
      await _flutterTts.setLanguage('hi-IN');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isTtsInitialized = true;
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  /// Speak text aloud in Hindi (or specified locale)
  Future<void> speak(
    String text, {
    String lang = 'hi-IN',
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    final clean = cleanTextForSpeech(text);
    if (clean.isEmpty) return;

    if (kIsWeb) {
      onStart?.call();
      VoiceWebHelper.speak(clean, lang: lang);
      return;
    }

    try {
      await _ensureTtsInitialized();
      _flutterTts.setStartHandler(() {
        onStart?.call();
      });
      _flutterTts.setCompletionHandler(() {
        onDone?.call();
      });
      _flutterTts.setCancelHandler(() {
        onDone?.call();
      });
      _flutterTts.setErrorHandler((msg) {
        onDone?.call();
      });

      await _flutterTts.setLanguage(lang);
      await _flutterTts.speak(clean);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      onDone?.call();
    }
  }

  /// Stop any active speech playback immediately
  Future<void> stopSpeaking() async {
    if (kIsWeb) {
      VoiceWebHelper.stopSpeaking();
      return;
    }
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
  }

  /// Start listening to user voice via real microphone
  Future<bool> startListening({
    String lang = 'hi-IN',
    required Function(String recognizedWords) onResult,
    Function(String error)? onError,
    VoidCallback? onListeningStarted,
    VoidCallback? onListeningStopped,
  }) async {
    _isListening = true;
    onListeningStarted?.call();

    // 1. Web browser implementation
    if (kIsWeb) {
      final success = VoiceWebHelper.startListening(
        lang: lang,
        onResult: (text) {
          _isListening = false;
          onResult(text);
          onListeningStopped?.call();
        },
        onError: (err) {
          _isListening = false;
          onError?.call(err);
          onListeningStopped?.call();
        },
        onEnd: () {
          _isListening = false;
          onListeningStopped?.call();
        },
      );
      return success;
    }

    // 2. Mobile (Android/iOS) implementation
    try {
      if (!_isSttInitialized) {
        _isSttInitialized = await _speechToText.initialize(
          onError: (errorNotification) {
            _isListening = false;
            onError?.call(errorNotification.errorMsg);
            onListeningStopped?.call();
          },
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              _isListening = false;
              onListeningStopped?.call();
            }
          },
        );
      }

      if (!_isSttInitialized) {
        _isListening = false;
        onError?.call('Microphone permission or speech recognition unavailable');
        onListeningStopped?.call();
        return false;
      }

      final options = stt.SpeechListenOptions(
        localeId: lang.replaceAll('-', '_'),
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
      );

      await _speechToText.listen(
        listenOptions: options,
        onResult: (result) {
          if (result.finalResult || result.recognizedWords.isNotEmpty) {
            onResult(result.recognizedWords);
            if (result.finalResult) {
              _isListening = false;
              onListeningStopped?.call();
            }
          }
        },
      );
      return true;
    } catch (e) {
      _isListening = false;
      onError?.call(e.toString());
      onListeningStopped?.call();
      return false;
    }
  }

  /// Stop microphone listening
  Future<void> stopListening() async {
    _isListening = false;
    if (kIsWeb) {
      VoiceWebHelper.stopListening();
      return;
    }
    try {
      if (_speechToText.isListening) {
        await _speechToText.stop();
      }
    } catch (e) {
      debugPrint('STT stop error: $e');
    }
  }
}
