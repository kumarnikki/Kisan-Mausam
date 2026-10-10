import 'dart:async';
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

  String _latestTranscript = '';
  bool _finalDispatched = false;
  Timer? _silenceTimer;
  Function(String)? _activeOnResult;
  VoidCallback? _activeOnStopped;

  void _commitFinalSpeech() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    if (_finalDispatched) return;
    final finalWords = _latestTranscript.trim();
    if (finalWords.isEmpty) {
      _isListening = false;
      _activeOnStopped?.call();
      return;
    }
    _finalDispatched = true;
    _isListening = false;
    final cb = _activeOnResult;
    final stopCb = _activeOnStopped;
    _activeOnResult = null;
    _activeOnStopped = null;
    cb?.call(finalWords);
    stopCb?.call();
  }

  /// Start listening to user voice via real microphone.
  /// [onPartialResult] is called live as words are spoken;
  /// [onResult] is called ONLY ONCE with the full sentence after the user stops speaking.
  Future<bool> startListening({
    String lang = 'hi-IN',
    required Function(String recognizedWords) onResult,
    Function(String partialWords)? onPartialResult,
    Function(String error)? onError,
    VoidCallback? onListeningStarted,
    VoidCallback? onListeningStopped,
  }) async {
    _silenceTimer?.cancel();
    _latestTranscript = '';
    _finalDispatched = false;
    _activeOnResult = onResult;
    _activeOnStopped = onListeningStopped;
    _isListening = true;
    onListeningStarted?.call();

    // 1. Web browser implementation
    if (kIsWeb) {
      final success = VoiceWebHelper.startListening(
        lang: lang,
        onResult: (text) {
          _latestTranscript = text.trim();
          _commitFinalSpeech();
        },
        onError: (err) {
          _isListening = false;
          onError?.call(err);
          onListeningStopped?.call();
        },
        onEnd: () {
          _commitFinalSpeech();
        },
      );
      return success;
    }

    // 2. Mobile (Android/iOS) implementation
    try {
      if (!_isSttInitialized) {
        _isSttInitialized = await _speechToText.initialize(
          onError: (errorNotification) {
            // If we already captured words before a timeout/speech_timeout, commit them as a single message
            if (_latestTranscript.trim().isNotEmpty && !_finalDispatched) {
              _commitFinalSpeech();
              return;
            }
            _isListening = false;
            onError?.call(errorNotification.errorMsg);
            _activeOnStopped?.call();
          },
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              if (_latestTranscript.trim().isNotEmpty && !_finalDispatched) {
                _commitFinalSpeech();
              } else if (!_finalDispatched) {
                _isListening = false;
                _activeOnStopped?.call();
              }
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
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 30),
      );

      await _speechToText.listen(
        listenOptions: options,
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _latestTranscript = words;
            onPartialResult?.call(words);
          }

          if (result.finalResult) {
            _commitFinalSpeech();
          } else if (words.isNotEmpty) {
            // Debounce silence: wait 1.8s after the user's last word before sending the single complete message
            _silenceTimer?.cancel();
            _silenceTimer = Timer(const Duration(milliseconds: 1800), () async {
              try {
                if (_speechToText.isListening) {
                  await _speechToText.stop();
                }
              } catch (_) {}
              _commitFinalSpeech();
            });
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

  /// Stop microphone listening and commit any spoken sentence so far as a single message.
  Future<void> stopListening() async {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    if (kIsWeb) {
      _isListening = false;
      VoiceWebHelper.stopListening();
      if (_latestTranscript.trim().isNotEmpty && !_finalDispatched) {
        _commitFinalSpeech();
      }
      return;
    }
    try {
      if (_speechToText.isListening) {
        await _speechToText.stop();
      }
    } catch (e) {
      debugPrint('STT stop error: $e');
    }
    if (_latestTranscript.trim().isNotEmpty && !_finalDispatched) {
      _commitFinalSpeech();
    } else {
      _isListening = false;
    }
  }
}
