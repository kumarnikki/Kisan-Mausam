import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/farm_profile.dart';
import '../../models/weather_models.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String>? tips;
  final String? kvkContact;
  final String timestamp;
  final bool isError;
  final String? retryQuery;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.tips,
    this.kvkContact,
    required this.timestamp,
    this.isError = false,
    this.retryQuery,
  });
}

class KrishiSahayakScreen extends StatefulWidget {
  final FarmProfile? farm;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final WeatherData? weather;
  final String? lang;
  final VoidCallback? onBack;
  final String? initialPrompt;

  const KrishiSahayakScreen({
    super.key,
    this.farm,
    this.locationName,
    this.latitude,
    this.longitude,
    this.weather,
    this.lang,
    this.onBack,
    this.initialPrompt,
  });

  @override
  State<KrishiSahayakScreen> createState() => _KrishiSahayakScreenState();
}

class _KrishiSahayakScreenState extends State<KrishiSahayakScreen>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final VoiceService _voiceService = VoiceService();

  bool _isRecording = false;
  bool _isLoading = false;
  bool _isSpeaking = false;
  int? _speakingMessageIndex;
  bool _micPermissionDenied = false;
  bool _hasCustomApiKey = false;
  String _lang = 'hi';
  bool _hasTypedText = false;

  late AnimationController _pulseController;
  late AnimationController _waveController;

  final List<ChatMessage> _messages = [];

  List<Map<String, dynamic>> get _starterChips {
    final isEn = _lang == 'en';
    return [
      {
        'label': isEn ? 'Should I irrigate today?' : 'क्या आज पानी दूं?',
        'icon': Icons.water_drop_rounded,
      },
      {
        'label': isEn ? 'How to protect from frost?' : 'पाले से कैसे बचाएं?',
        'icon': Icons.ac_unit_rounded,
      },
      {
        'label': isEn ? 'Heatwave protection?' : 'लू से बचाव के उपाय?',
        'icon': Icons.wb_sunny_rounded,
      },
      {
        'label': isEn ? 'Organic pest control?' : 'कीट नियंत्रण उपाय?',
        'icon': Icons.pest_control_rounded,
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textController.addListener(_onTextChanged);
    _initScreen();
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasTypedText && mounted) {
      setState(() => _hasTypedText = hasText);
    }
  }

  Future<void> _initScreen() async {
    final savedLang = widget.lang ?? await StorageService.getLanguage();
    final key = await StorageService.getGeminiApiKey();
    if (!mounted) return;
    setState(() {
      _lang = savedLang;
      _hasCustomApiKey = key != null && key.isNotEmpty;
    });

    if (widget.initialPrompt != null && widget.initialPrompt!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendMessage(widget.initialPrompt!);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant KrishiSahayakScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lang != null && widget.lang != _lang) {
      setState(() => _lang = widget.lang!);
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _pulseController.dispose();
    _waveController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _voiceService.stopListening();
    _voiceService.stopSpeaking();
    super.dispose();
  }

  String _formatTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String _getWeatherConditionDescription(int code) {
    final isEn = _lang == 'en';
    if (code == 0) return isEn ? 'Clear Sky' : 'साफ धूप';
    if (code >= 1 && code <= 3) return isEn ? 'Partly Cloudy' : 'हल्के बादल';
    if (code == 45 || code == 48) return isEn ? 'Foggy' : 'कोहरा';
    if (code >= 51 && code <= 55) return isEn ? 'Light Drizzle' : 'हल्की बूंदाबांदी';
    if (code >= 61 && code <= 65) return isEn ? 'Rain' : 'बारिश';
    if (code >= 80 && code <= 82) return isEn ? 'Heavy Showers' : 'तेज बौछारें';
    if (code >= 95) return isEn ? 'Thunderstorm' : 'गरज-चमक के साथ तूफान';
    return isEn ? 'Normal Weather' : 'सामान्य मौसम';
  }

  String get _greetingText {
    final isEn = _lang == 'en';
    final village = widget.locationName ??
        widget.farm?.getVillage(_lang) ??
        (isEn ? 'Your Farm' : 'आपका खेत');
    final crop = widget.farm?.getCurrentCrop(_lang) ??
        (isEn ? 'Wheat' : 'गेहूं');
    final temp = widget.weather?.current.temperature;
    final tempStr = temp != null ? ' (${temp.toStringAsFixed(1)}°C)' : '';
    return isEn
        ? 'Namaste! $village$tempStr • $crop. Ask about weather, irrigation, or crop protection.'
        : 'राम-राम! $village$tempStr • $crop। मौसम, सिंचाई या फसल सुरक्षा पर सीधा सवाल पूछें।';
  }

  void _speakMessage(String text, int index) {
    _voiceService.stopSpeaking();
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() {
      _isSpeaking = true;
      _speakingMessageIndex = index;
      if (!disableAnimations) _waveController.repeat();
    });
    _voiceService.speak(
      text,
      lang: _lang == 'en' ? 'en-IN' : 'hi-IN',
      onStart: () {
        if (mounted) {
          setState(() {
            _isSpeaking = true;
            _speakingMessageIndex = index;
            if (!disableAnimations) _waveController.repeat();
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _speakingMessageIndex = null;
            _waveController.stop();
            _waveController.reset();
          });
        }
      },
    );
  }

  void _stopSpeaking() {
    _voiceService.stopSpeaking();
    setState(() {
      _isSpeaking = false;
      _speakingMessageIndex = null;
      _waveController.stop();
      _waveController.reset();
    });
  }

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    _textController.clear();
    setState(() {
      _hasTypedText = false;
      _messages.add(ChatMessage(
        text: query,
        isUser: true,
        timestamp: _formatTime(),
      ));
      _isLoading = true;
    });

    _scrollToBottom();

    final apiKey = await StorageService.getGeminiApiKey();
    final res = await _apiService.askAiAdvisor(
      widget.farm?.id ?? 1,
      query,
      apiKey: apiKey,
      lat: widget.latitude ?? widget.farm?.latitude,
      lon: widget.longitude ?? widget.farm?.longitude,
      locationName: widget.locationName ?? widget.farm?.village,
      currentTemp: widget.weather?.current.temperature,
      currentHumidity: widget.weather?.current.relativeHumidity,
      currentWind: widget.weather?.current.windSpeed,
      weatherCondition: widget.weather != null
          ? _getWeatherConditionDescription(widget.weather!.current.weatherCode)
          : null,
      crop: widget.farm?.currentCrop,
      cropStage: widget.farm?.cropStage,
      lang: _lang,
    );

    if (!mounted) return;

    if (res != null) {
      final reply = res['reply_text'] ??
          (_lang == 'en'
              ? 'Could not retrieve answer.'
              : 'उत्तर प्राप्त नहीं हो सका।');
      final rawTips = (res['actionable_tips'] as List?)?.cast<String>() ?? [];
      // Filter out any KVK repeat from action points and cap at max 2 items
      final filteredTips = rawTips
          .where((t) =>
              !t.contains('1800-180-1551') &&
              !t.toLowerCase().contains('kvk helpline') &&
              !t.contains('KVK हेल्पलाइन'))
          .take(2)
          .toList();

      final newIndex = _messages.length;
      setState(() {
        _messages.add(ChatMessage(
          text: reply,
          isUser: false,
          tips: filteredTips,
          timestamp: _formatTime(),
        ));
        _isLoading = false;
      });

      _speakMessage(reply, newIndex);
    } else {
      setState(() {
        _messages.add(ChatMessage(
          text: _lang == 'en'
              ? 'Could not connect to weather service. Check your connection and tap Retry.'
              : 'मौसम सेवा से संपर्क नहीं हो पाया। इंटरनेट जांचें और पुनः प्रयास करें।',
          isUser: false,
          timestamp: _formatTime(),
          isError: true,
          retryQuery: query,
        ));
        _isLoading = false;
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (disableAnimations) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await _voiceService.stopListening();
      _pulseController.stop();
      _pulseController.reset();
      setState(() => _isRecording = false);
      if (_textController.text.trim().isNotEmpty) {
        _sendMessage(_textController.text.trim());
      }
      return;
    }

    _stopSpeaking();
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() {
      _isRecording = true;
      _micPermissionDenied = false;
      if (!disableAnimations) _pulseController.repeat(reverse: true);
    });

    final started = await _voiceService.startListening(
      lang: _lang == 'en' ? 'en_IN' : 'hi_IN',
      onPartialResult: (partial) {
        if (mounted) {
          setState(() {
            _textController.text = partial;
            _hasTypedText = partial.trim().isNotEmpty;
          });
        }
      },
      onResult: (recognizedWords) {
        if (!mounted) return;
        _pulseController.stop();
        _pulseController.reset();
        setState(() => _isRecording = false);
        if (recognizedWords.trim().isNotEmpty) {
          _sendMessage(recognizedWords);
        }
      },
      onListeningStopped: () {
        if (mounted) {
          _pulseController.stop();
          _pulseController.reset();
          setState(() => _isRecording = false);
        }
      },
    );

    if (!started && mounted) {
      _pulseController.stop();
      _pulseController.reset();
      setState(() {
        _isRecording = false;
        _micPermissionDenied = true;
      });
    }
  }

  Future<void> _callKvk([String? number]) async {
    final cleanNumber = (number ?? '1800-180-1551').replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleanNumber);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _lang == 'en'
              ? 'Kisan Call Center (KVK): 1800-180-1551'
              : 'किसान कॉल सेंटर (KVK): 1800-180-1551',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showApiKeyDialog() async {
    final currentKey = await StorageService.getGeminiApiKey() ?? '';
    final controller = TextEditingController(text: currentKey);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
        ),
        title: Row(
          children: [
            Icon(Icons.key_rounded, color: AppTheme.primaryActionColor(ctx)),
            const SizedBox(width: AppTheme.s8),
            Expanded(
              child: Text(
                _lang == 'en' ? 'Gemini AI API Key' : 'Gemini AI API कुंजी',
                style: AppTheme.sectionStyle.copyWith(
                  color: AppTheme.textPrimary(ctx),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _lang == 'en'
                  ? 'Enter your Google Gemini API key for custom cloud responses, or leave blank to use default.'
                  : 'कस्टम Gemini AI कुंजी दर्ज करें, या डिफ़ॉल्ट सेवा के लिए खाली छोड़ें।',
              style: TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary(ctx),
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.s12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'AIzaSy...',
                prefixIcon: Icon(Icons.vpn_key_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_lang == 'en' ? 'Cancel' : 'रद्द करें'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(100, 48),
            ),
            onPressed: () async {
              await StorageService.saveGeminiApiKey(controller.text.trim());
              if (!mounted) return;
              setState(() {
                _hasCustomApiKey = controller.text.trim().isNotEmpty;
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(_lang == 'en' ? 'Save' : 'सुरक्षित करें'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _lang == 'en';
    final locText = widget.locationName ??
        widget.farm?.getVillage(_lang) ??
        (isEn ? 'Your Farm' : 'मेरा खेत');
    final cropText = widget.farm?.getCurrentCrop(_lang) ??
        (isEn ? 'Wheat' : 'गेहूं');
    final hasUserMessages = _messages.any((m) => m.isUser);
    final showBack = widget.onBack != null || Navigator.of(context).canPop();

    return Scaffold(
      body: AmbientBackground(
        quiet: true,
        weatherCode: widget.weather?.current.weatherCode ?? 0,
        isDay: widget.weather?.current.isDay ?? true,
        temperature: widget.weather?.current.temperature ?? 28.0,
        sunrise: widget.weather?.daily.isNotEmpty == true
            ? widget.weather!.daily.first.sunrise
            : null,
        sunset: widget.weather?.daily.isNotEmpty == true
            ? widget.weather!.daily.first.sunset
            : null,
        child: SafeArea(
          child: Column(
            children: [
              // 1. Slim 1-line Header with overflow "..." menu for Gemini API key
              Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.s16,
                  vertical: AppTheme.s8,
                ),
                child: Row(
                  children: [
                    if (showBack) ...[
                      Semantics(
                        button: true,
                        label: isEn ? 'Back' : 'वापस जाएं',
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: AppTheme.textPrimary(context),
                          ),
                          onPressed: () {
                            if (widget.onBack != null) {
                              widget.onBack!();
                            } else {
                              Navigator.of(context).maybePop();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppTheme.s4),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isEn ? 'Krishi Sahayak' : 'किसान मौसम कृषि सहायक',
                            style: AppTheme.sectionStyle.copyWith(
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          Text(
                            '$locText - $cropText',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: AppTheme.textPrimary(context),
                      ),
                      tooltip: isEn ? 'More options' : 'अधिक विकल्प',
                      onSelected: (val) {
                        if (val == 'api_key') {
                          _showApiKeyDialog();
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem<String>(
                          value: 'api_key',
                          child: Row(
                            children: [
                              Icon(
                                Icons.key_rounded,
                                size: 20,
                                color: _hasCustomApiKey
                                    ? AppTheme.primaryActionColor(ctx)
                                    : AppTheme.textSecondary(ctx),
                              ),
                              const SizedBox(width: AppTheme.s8),
                              Text(
                                isEn ? 'Gemini API key' : 'Gemini API कुंजी',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 2. Single Slim ICAR / KVK Compliance Line (Only KVK reference on the screen)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.s16),
                child: AppSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.s12,
                    vertical: 6,
                  ),
                  borderRadius: AppTheme.rInput,
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        size: 16,
                        color: AppTheme.primaryActionColor(context),
                      ),
                      const SizedBox(width: AppTheme.s8),
                      Expanded(
                        child: Text(
                          isEn
                              ? 'Verify chemical doses with your KVK (1800-180-1551)'
                              : 'ICAR मानक: रासायनिक मात्रा अपने KVK (1800-180-1551) से सत्यापित करें',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary(context),
                            height: 1.35,
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: isEn
                            ? 'Call KVK 1800-180-1551'
                            : 'KVK 1800-180-1551 पर कॉल करें',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppTheme.rInput),
                          onTap: () => _callKvk('1800-180-1551'),
                          child: SizedBox(
                            width: 48,
                            height: 40,
                            child: Icon(
                              Icons.call_rounded,
                              size: 18,
                              color: AppTheme.primaryActionColor(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_micPermissionDenied)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.s16,
                    AppTheme.s8,
                    AppTheme.s16,
                    0,
                  ),
                  child: InfoBanner(
                    icon: Icons.mic_off_rounded,
                    iconColor: AppTheme.semanticWarningText(context),
                    text: isEn
                        ? 'Microphone permission denied. Please enable mic access or type below.'
                        : 'माइक्रोफ़ोन अनुमति उपलब्ध नहीं है। कृपया अनुमति दें या नीचे टाइप करें।',
                  ),
                ),

              // 3. Body: Empty state OR Chat message list
              Expanded(
                child: !hasUserMessages && _messages.isEmpty
                    ? _buildEmptyState(isEn)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.s16,
                          vertical: AppTheme.s12,
                        ),
                        itemCount: _messages.length + (_isLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return _buildTypingIndicator(isEn);
                          }
                          final msg = _messages[index];
                          return _buildAnimatedMessage(msg, index);
                        },
                      ),
              ),

              // 4. After first message, starter chips become one horizontal scroll row above input
              if (hasUserMessages || _messages.isNotEmpty)
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.s16,
                      vertical: 4,
                    ),
                    itemCount: _starterChips.length,
                    separatorBuilder: (_, index) => const SizedBox(width: AppTheme.s8),
                    itemBuilder: (context, index) {
                      final chip = _starterChips[index];
                      return _buildStarterChip(
                        chip['label'] as String,
                        chip['icon'] as IconData,
                      );
                    },
                  ),
                ),

              // 5. Unified Input Bar: TextField + 56dp circular Mic/Send button
              _buildInputBar(isEn),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isEn) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.s16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: AppTheme.s16),
          AppSurface(
            padding: const EdgeInsets.all(AppTheme.s16),
            child: Text(
              _greetingText,
              textAlign: TextAlign.center,
              style: AppTheme.bodyStyle.copyWith(
                color: AppTheme.textPrimary(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.s24),
          // Large centered mic button with "Tap and speak"
          Semantics(
            button: true,
            label: isEn ? 'Tap and speak' : 'बोलने के लिए टैप करें',
            child: GestureDetector(
              onTap: _toggleRecording,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      final scale = _isRecording
                          ? 1.0 + (_pulseController.value * 0.12)
                          : 1.0;
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecording
                                ? AppTheme.danger
                                : AppTheme.primaryButtonFill(context),
                          ),
                          child: const Icon(
                            Icons.mic_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppTheme.s8),
                  Text(
                    _isRecording
                        ? (isEn ? 'Listening... speak now' : 'सुन रहे हैं... अब बोलें')
                        : (isEn ? 'Tap and speak' : 'बोलने के लिए टैप करें'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _isRecording
                          ? AppTheme.semanticDangerText(context)
                          : AppTheme.primaryActionColor(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.s24),
          // 4 Starter Chips
          Wrap(
            spacing: AppTheme.s8,
            runSpacing: AppTheme.s8,
            alignment: WrapAlignment.center,
            children: _starterChips.map((chip) {
              return _buildStarterChip(
                chip['label'] as String,
                chip['icon'] as IconData,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStarterChip(String label, IconData icon) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.rChip),
        onTap: () => _sendMessage(label),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.s12,
              vertical: AppTheme.s8,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceFill(context),
              borderRadius: BorderRadius.circular(AppTheme.rChip),
              border: Border.all(
                color: AppTheme.borderColor(context),
                width: AppTheme.borderWidth(context),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: AppTheme.primaryActionColor(context),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedMessage(ChatMessage msg, int index) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final child = msg.isUser
        ? _buildUserBubble(msg)
        : _buildAssistantBubble(msg, index);

    if (disableAnimations) return child;

    return TweenAnimationBuilder<double>(
      key: ValueKey('msg_$index'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, w) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1.0 - value) * 12),
            child: w,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildUserBubble(ChatMessage msg) {
    final fill = AppTheme.primaryButtonFill(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: AppTheme.s8, bottom: AppTheme.s8, left: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.s16,
          vertical: AppTheme.s12,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppTheme.rCard),
            topRight: Radius.circular(AppTheme.rCard),
            bottomLeft: Radius.circular(AppTheme.rCard),
            bottomRight: Radius.circular(AppTheme.s4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppTheme.s4),
            Text(
              msg.timestamp,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(ChatMessage msg, int index) {
    final isEn = _lang == 'en';
    final isThisSpeaking = _isSpeaking && _speakingMessageIndex == index;
    final tips = msg.tips ?? const <String>[];

    return Container(
      margin: const EdgeInsets.only(top: AppTheme.s8, bottom: AppTheme.s8, right: 24),
      child: AppSurface(
        padding: const EdgeInsets.all(AppTheme.s16),
        borderRadius: AppTheme.rCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    msg.text,
                    style: AppTheme.bodyStyle.copyWith(
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.s8),
                // Speaker icon button or inline Stop control when TTS is playing on this message
                if (isThisSpeaking)
                  Semantics(
                    button: true,
                    label: isEn ? 'Stop audio' : 'आवाज़ रोकें',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rInput),
                      onTap: _stopSpeaking,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppTheme.rInput),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildInlineWaveform(),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.stop_circle_rounded,
                              size: 22,
                              color: AppTheme.semanticDangerText(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Semantics(
                    button: true,
                    label: isEn ? 'Listen to response' : 'उत्तर सुनें',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rInput),
                      onTap: () => _speakMessage(msg.text, index),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 22,
                          color: AppTheme.primaryActionColor(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // Compact Action Points checklist (max 2 items)
            if (tips.isNotEmpty) ...[
              const SizedBox(height: AppTheme.s12),
              ...tips.take(2).map(
                    (tip) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.s4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(
                              Icons.check_circle_outline_rounded,
                              size: 16,
                              color: AppTheme.primaryActionColor(context),
                            ),
                          ),
                          const SizedBox(width: AppTheme.s8),
                          Expanded(
                            child: Text(
                              tip,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary(context),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],

            if (msg.isError && msg.retryQuery != null) ...[
              const SizedBox(height: AppTheme.s8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _sendMessage(msg.retryQuery!),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(isEn ? 'Retry' : 'पुनः प्रयास करें'),
                ),
              ),
            ],

            const SizedBox(height: AppTheme.s4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                msg.timestamp,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineWaveform() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (i) {
            final h = 6.0 +
                10.0 *
                    (0.5 +
                        0.5 *
                            math.sin(
                                (_waveController.value * 2 * math.pi) + (i * 0.9)));
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: AppTheme.semanticDangerText(context),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildTypingIndicator(bool isEn) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.s8),
        child: AppSurface(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.s16,
            vertical: AppTheme.s12,
          ),
          borderRadius: AppTheme.rCard,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryActionColor(context),
                ),
              ),
              const SizedBox(width: AppTheme.s12),
              Text(
                isEn ? 'Preparing advice...' : 'सलाह तैयार की जा रही है...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isEn) {
    final primaryFill = AppTheme.primaryButtonFill(context);
    final showSend = _hasTypedText && !_isRecording;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.s16,
        AppTheme.s8,
        AppTheme.s16,
        AppTheme.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: _isRecording
                    ? (isEn ? 'Listening...' : 'सुन रहे हैं...')
                    : (isEn ? 'Ask by speaking or typing...' : 'बोलकर या लिखकर पूछें...'),
                hintStyle: TextStyle(
                  color: _isRecording
                      ? AppTheme.semanticDangerText(context)
                      : AppTheme.textSecondary(context),
                  fontWeight: _isRecording ? FontWeight.w700 : FontWeight.w400,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.s16,
                  vertical: 14,
                ),
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: AppTheme.s8),
          // Single trailing 56dp circular button: Mic when empty, Send when text is present
          Semantics(
            button: true,
            label: showSend
                ? (isEn ? 'Send message' : 'संदेश भेजें')
                : (isEn ? 'Speak question' : 'बोलकर सवाल पूछें'),
            child: GestureDetector(
              onTap: showSend
                  ? () => _sendMessage(_textController.text)
                  : _toggleRecording,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  final scale = _isRecording
                      ? 1.0 + (_pulseController.value * 0.08)
                      : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRecording ? AppTheme.danger : primaryFill,
                      ),
                      child: Icon(
                        showSend
                            ? Icons.send_rounded
                            : (_isRecording ? Icons.mic_rounded : Icons.mic_none),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
