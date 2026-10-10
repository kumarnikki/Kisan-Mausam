import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/voice_service.dart';
import '../../services/storage_service.dart';
import '../../models/farm_profile.dart';
import '../../models/weather_models.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String>? tips;
  final String? kvkContact;
  final String timestamp;
  final String? category;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.tips,
    this.kvkContact,
    required this.timestamp,
    this.category,
  });
}

class KrishiSahayakScreen extends StatefulWidget {
  final FarmProfile? farm;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final WeatherData? weather;

  const KrishiSahayakScreen({
    super.key,
    this.farm,
    this.locationName,
    this.latitude,
    this.longitude,
    this.weather,
  });

  @override
  State<KrishiSahayakScreen> createState() => _KrishiSahayakScreenState();
}

class _KrishiSahayakScreenState extends State<KrishiSahayakScreen>
    with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final VoiceService _voiceService = VoiceService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSpeaking = false;
  bool _isRecording = false;

  late AnimationController _pulseController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _initWelcomeMessage();
  }

  @override
  void dispose() {
    _voiceService.stopSpeaking();
    _voiceService.stopListening();
    _pulseController.dispose();
    _waveController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTime() {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _getWeatherConditionDescription(int code) {
    if (code == 0) return 'साफ आसमान';
    if (code >= 1 && code <= 3) return 'हल्के बादल';
    if (code == 45 || code == 48) return 'कोहरा';
    if (code >= 51 && code <= 55) return 'हल्की बूंदाबांदी';
    if (code >= 61 && code <= 65) return 'बारिश';
    if (code >= 80 && code <= 82) return 'तेज बौछारें';
    if (code == 95) return 'गरज-चमक';
    if (code == 96 || code == 99) return 'ओलावृष्टि';
    return 'सामान्य मौसम';
  }

  void _initWelcomeMessage() {
    final crop = widget.farm?.currentCrop ?? 'सोयाबीन';
    final village = widget.locationName ?? widget.farm?.village ?? 'आपका क्षेत्र';
    final currentTemp = widget.weather?.current.temperature;
    final tempStr = currentTemp != null ? ' (वर्तमान तापमान ${currentTemp.toStringAsFixed(1)}°C)' : '';
    _messages.add(
      ChatMessage(
        text:
            'राम-राम किसान भाई! मैं आपका किसान मौसम कृषि सहायक हूँ। आपके क्षेत्र ($village)$tempStr और फसल ($crop) के मौसम व सुरक्षा पर कोई भी सवाल बोलकर या लिखकर पूछें।\n\n'
            'मैं भारतीय कृषि अनुसंधान परिषद (ICAR) एवं मौसम विज्ञान विभाग (IMD) के वैज्ञानिक मानकों पर आधारित सलाह देता हूँ।',
        isUser: false,
        tips: [
          'अभी का तापमान कितना है?',
          'क्या आज पानी दूं?',
          'बारिश कब होगी?',
          'पाले से कैसे बचाएं?',
          '30-दिवसीय मौसमी रुझान'
        ],
        kvkContact: '1800-180-1551',
        timestamp: _formatTime(),
        category: 'स्वागत',
      ),
    );
  }

  void _speakText(String text) {
    _voiceService.stopSpeaking();
    setState(() {
      _isSpeaking = true;
      _waveController.repeat();
    });
    _voiceService.speak(
      text,
      lang: 'hi-IN',
      onStart: () {
        if (mounted) {
          setState(() {
            _isSpeaking = true;
            _waveController.repeat();
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _waveController.stop();
            _waveController.reset();
          });
        }
      },
    );
  }

  void _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    _textController.clear();
    setState(() {
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
      weatherCondition: widget.weather != null ? _getWeatherConditionDescription(widget.weather!.current.weatherCode) : null,
      crop: widget.farm?.currentCrop,
      cropStage: widget.farm?.cropStage,
    );

    if (!mounted) return;

    if (res != null) {
      final reply = res['reply_text'] ?? 'उत्तर प्राप्त नहीं हो सका।';
      final tips = (res['actionable_tips'] as List?)?.cast<String>();
      final kvk = res['kvk_contact'] ?? '1800-180-1551';

      setState(() {
        _messages.add(ChatMessage(
          text: reply,
          isUser: false,
          tips: tips,
          kvkContact: kvk,
          timestamp: _formatTime(),
        ));
        _isLoading = false;
      });

      // Play real speech audio for the farmer
      _speakText(reply);
    } else {
      setState(() {
        _messages.add(ChatMessage(
          text:
              'किसान भाई, मौसम सेवा से संपर्क नहीं हो पाया। कृपया इंटरनेट जांचें अथवा KVK टोल-फ्री 1800-180-1551 पर कॉल करें।',
          isUser: false,
          timestamp: _formatTime(),
        ));
        _isLoading = false;
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await _voiceService.stopListening();
      setState(() {
        _isRecording = false;
        _pulseController.stop();
        _pulseController.reset();
      });
      return;
    }

    // Stop active speech if speaking
    _voiceService.stopSpeaking();
    if (_isSpeaking) {
      setState(() {
        _isSpeaking = false;
        _waveController.stop();
        _waveController.reset();
      });
    }

    setState(() {
      _isRecording = true;
      _pulseController.repeat(reverse: true);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.mic, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('सुन रहा हूँ... अपनी भाषा में बोलिए (Listening...)'),
          ],
        ),
        backgroundColor: const Color(0xFFBF360C),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final started = await _voiceService.startListening(
      lang: 'hi-IN',
      onListeningStarted: () {
        if (mounted) {
          setState(() {
            _isRecording = true;
            _pulseController.repeat(reverse: true);
          });
        }
      },
      onResult: (words) {
        if (!mounted) return;
        final recognized = words.trim();
        if (recognized.isNotEmpty) {
          setState(() {
            _textController.text = recognized;
            _isRecording = false;
            _pulseController.stop();
            _pulseController.reset();
          });
          _sendMessage(recognized);
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _pulseController.stop();
          _pulseController.reset();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('माइक: $err (पुनः प्रयास करें या लिखकर पूछें)'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onListeningStopped: () {
        if (mounted && _isRecording) {
          setState(() {
            _isRecording = false;
            _pulseController.stop();
            _pulseController.reset();
          });
        }
      },
    );

    if (!started && mounted) {
      setState(() {
        _isRecording = false;
        _pulseController.stop();
        _pulseController.reset();
      });
    }
  }

  void _stopSpeaking() {
    _voiceService.stopSpeaking();
    setState(() {
      _isSpeaking = false;
      _waveController.stop();
      _waveController.reset();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('बोलना रोक दिया गया (Audio Stopped)'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _showApiKeyDialog() async {
    final currentKey = await StorageService.getGeminiApiKey();
    if (!mounted) return;
    final controller = TextEditingController(text: currentKey ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.key, color: Color(0xFF1B5E20)),
            SizedBox(width: 8),
            Text('Google Gemini API Key', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'अपनी Google Gemini AI कुंजी यहाँ दर्ज करें। यह कुंजी सीधे Gemini 2.0 Flash मॉडल को सक्रिय करती है।',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'AIzaSy...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.vpn_key_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => controller.clear(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ℹ️ कुंजी खाली रखने पर अंतर्निर्मित ICAR वैज्ञानिक सलाहकार स्वतः कार्य करता है।',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('रद्द करें'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await StorageService.saveGeminiApiKey(controller.text.trim());
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    controller.text.trim().isEmpty
                        ? '✅ अंतर्निर्मित ICAR AI सलाहकार सक्रिय'
                        : '✅ Gemini API Key सुरक्षित कर ली गई!',
                  ),
                  backgroundColor: const Color(0xFF1B5E20),
                ),
              );
            },
            child: const Text('सुरक्षित करें'),
          ),
        ],
      ),
    );
  }

  void _callKvk() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.call, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'किसान कॉल सेंटर (KVK) टोल-फ्री 1800-180-1551 पर कॉल किया जा रहा है...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1B5E20),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final village = widget.farm?.village ?? 'उमरेड';
    final crop = widget.farm?.currentCrop ?? 'सोयाबीन';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F4),
      body: Stack(
        children: [
          // Ambient blurred glowing background spheres for Glassmorphism
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF81C784).withValues(alpha: 0.22),
              ),
            ),
          ),
          Positioned(
            top: 240,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFA5D6A7).withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFC8E6C9).withValues(alpha: 0.25),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 1. Modern Glass App Bar
                _buildGlassAppBar(village, crop),

                // 2. TTS Active Voice Bar (if speaking)
                if (_isSpeaking) _buildSpeakingVisualizer(),

                // 3. ICAR Standard & KVK Banner (Required by widget test!)
                _buildIcarBanner(),

                // 4. Message Stream Area
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageItem(_messages[index]);
                    },
                  ),
                ),

                // 5. Typing / AI Thinking Indicator
                if (_isLoading) _buildThinkingIndicator(),

                // 6. Quick Action Suggestion Chips
                _buildQuickChipsCarousel(),

                // 7. Frosted Bottom Input & Push-To-Talk Mic Pill
                _buildBottomInputBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassAppBar(String village, String crop) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Back Button (Required by widget test!)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Color(0xFF1B5E20),
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Avatar with glowing pulse
                Stack(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.psychology, color: Colors.white, size: 24),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),

                // Title & Subtitle (Title text required by widget test!)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'किसान मौसम कृषि सहायक',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B5E20),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '📍 ${widget.locationName ?? widget.farm?.village ?? village} • $crop',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'AI ऑनलाइन',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF388E3C),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Gemini API Key Dialog Button
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.vpn_key_outlined,
                      color: Color(0xFF1B5E20),
                      size: 20,
                    ),
                  ),
                  tooltip: 'Gemini API Key',
                  onPressed: _showApiKeyDialog,
                ),

                // KVK Helpline Call Button (Required by widget test!)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF43A047), Color(0xFF1B5E20)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1B5E20).withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.phone_in_talk,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  tooltip: 'KVK कॉल करें',
                  onPressed: _callKvk,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeakingVisualizer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF8E1),
            const Color(0xFFFFECB3).withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Animated Waveform Bars
          AnimatedBuilder(
            animation: _waveController,
            builder: (context, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final height = 6.0 +
                      14.0 *
                          (0.5 +
                              0.5 *
                                  ((_waveController.value * 2 * 3.14 + index * 0.8) %
                                      3.14));
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 3.5,
                    height: height.clamp(5.0, 22.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65100),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(width: 10),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'कृषि सहायक बोल रहे हैं (Audio Playing)...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFFE65100),
                  ),
                ),
                Text(
                  'हिंदी आवाज सुन रहे हैं',
                  style: TextStyle(fontSize: 10, color: Color(0xFF795548)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          InkWell(
            onTap: _stopSpeaking,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFC62828),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stop, size: 15, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'रोकें (Stop)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcarBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA5D6A7), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.verified, size: 16, color: Color(0xFF1B5E20)),
          ),
          const SizedBox(width: 8),

          // Exact string required by widget test 7!
          const Expanded(
            child: Text(
              'ICAR मानक: रासायनिक मात्रा KVK (1800-180-1551) से जांचें।',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E7D32),
              ),
            ),
          ),

          InkWell(
            onTap: _callKvk,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'KVK',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC8E6C9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF1B5E20)),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'कृषि वैज्ञानिक सलाह तैयार कर रहे हैं...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1B5E20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChipsCarousel() {
    final chips = [
      'क्या आज पानी दूं? 💧',
      'पाले से कैसे बचाएं? ❄️',
      'लू व तेज गर्मी से बचाव ☀️',
      'भारी बारिश में जलभराव 🌧️',
      'कीट सुरक्षा जैविक उपाय 🌿',
      '30 दिन का मौसमी रुझान 🌾',
      'काली मिट्टी में सिंचाई 🪵',
      'फसल बीमा PMFBY दावा 🛡️',
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: chips.length,
        itemBuilder: (context, index) {
          final label = chips[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _sendMessage(label),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF81C784).withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1B5E20).withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Push-to-Talk Mic with pulsing radar animation
          GestureDetector(
            onTap: _toggleRecording,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isRecording
                          ? [Colors.red.shade600, Colors.red.shade900]
                          : [const Color(0xFFE65100), const Color(0xFFBF360C)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? Colors.red : const Color(0xFFE65100))
                            .withValues(
                                alpha: _isRecording
                                    ? (0.4 + 0.3 * _pulseController.value)
                                    : 0.35),
                        blurRadius: _isRecording ? 18 : 10,
                        spreadRadius: _isRecording ? (2 + 3 * _pulseController.value) : 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 26,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),

          // Modern Glass Input Box
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: _isRecording
                      ? Colors.red.shade400
                      : const Color(0xFFA5D6A7),
                  width: 1.2,
                ),
              ),
              child: TextField(
                controller: _textController,
                style: const TextStyle(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: _isRecording
                      ? 'सुन रहे हैं... (Listening...)'
                      : 'बोलकर या लिखकर पूछें...',
                  hintStyle: TextStyle(
                    color: _isRecording ? Colors.red.shade700 : Colors.grey.shade600,
                    fontWeight: _isRecording ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13.5,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  border: InputBorder.none,
                ),
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _sendMessage(_textController.text),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B5E20).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.send,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage msg) {
    if (msg.isUser) {
      return _buildUserBubble(msg);
    } else {
      return _buildAssistantBubble(msg);
    }
  }

  Widget _buildUserBubble(ChatMessage msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 8, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1B5E20).withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              msg.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              msg.timestamp,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(ChatMessage msg) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8, right: 32),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(22),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(22),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(22),
              ),
              border: Border.all(
                color: const Color(0xFFA5D6A7).withValues(alpha: 0.8),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Assistant Header with Avatar & Listen Pill
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.eco,
                        size: 18,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'कृषि सहायक (Agri Scientist)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    const Spacer(),

                    // Replay / Listen button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _speakText(msg.text),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF81C784)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.volume_up, size: 16, color: Color(0xFF1B5E20)),
                              SizedBox(width: 4),
                              Text(
                                'सुनें',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1B5E20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Main Explanation Text
                Text(
                  msg.text,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: Color(0xFF212121),
                    height: 1.42,
                    letterSpacing: 0.1,
                  ),
                ),

                // Actionable Tips Checklist Card
                if (msg.tips != null && msg.tips!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9).withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFC8E6C9),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.task_alt, size: 16, color: Color(0xFF1B5E20)),
                            SizedBox(width: 6),
                            Text(
                              'महत्वपूर्ण कार्य (Action Points):',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...msg.tips!.map((tip) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.check_circle_outline,
                                      size: 14,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      tip,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF1B5E20),
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ],

                // Footer with KVK Helpline & Timestamp
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (msg.kvkContact != null)
                      Expanded(
                        child: InkWell(
                          onTap: _callKvk,
                          child: Text(
                            '📞 KVK: ${msg.kvkContact}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    Text(
                      msg.timestamp,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
