import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../models/farm_profile.dart';
import '../chat/krishi_sahayak_screen.dart';

class CropRecommendationItem {
  final int rank;
  final String nameHi;
  final String nameEn;
  final String season;
  final int matchScore;
  final String durationDays;
  final double waterNeedMm;
  final String droughtTolerance;
  final String frostTolerance;
  final List<String> reasons;
  final List<String> riskNotes;
  final String? droughtAlternative;
  final String sourceCitation;
  final bool needsExpertReview;

  CropRecommendationItem({
    required this.rank,
    required this.nameHi,
    required this.nameEn,
    required this.season,
    required this.matchScore,
    required this.durationDays,
    required this.waterNeedMm,
    required this.droughtTolerance,
    required this.frostTolerance,
    required this.reasons,
    required this.riskNotes,
    this.droughtAlternative,
    required this.sourceCitation,
    required this.needsExpertReview,
  });

  static List<String> _localizeReasons(dynamic rawReasons, String cropNameEn, String lang) {
    if (lang == 'en') {
      final lower = cropNameEn.toLowerCase();
      if (lower.contains('wheat')) {
        return [
          'Primary food grain crop with excellent output under assured irrigation.',
          'Well adapted to medium and heavy loam soils of region.',
          'Current season is optimal for temperature and vegetative growth.',
          'High yield potential with ICAR package of practices compliance.',
        ];
      } else if (lower.contains('chickpea') || lower.contains('gram')) {
        return [
          'Current season (Rabi sowing) is highly favorable for chickpea.',
          'Black soil moisture retention capacity is optimal for chickpea root system.',
          'Low water requirement: safest choice for rainfed or deficit irrigation plots.',
          'Drought-tolerant traits provide resilience against 30-day deficit rain forecast.',
        ];
      } else if (lower.contains('mustard') || lower.contains('rapeseed')) {
        return [
          'Major oilseed crop for Rabi season; high yield with minimal cost and water.',
          'High drought tolerance makes it resilient against deficit rainfall.',
          'Suitable for plain topography and well-drained soils.',
        ];
      } else if (lower.contains('linseed')) {
        return [
          'Low input cost; highly tolerant to both frost and drought.',
          'Good returns with conserved moisture in black soils.',
        ];
      } else if (lower.contains('lentil')) {
        return [
          'Low water consumption; fixes atmospheric nitrogen in farm soil.',
          'Safe crop under below-average rainfall forecast.',
        ];
      }
      if (rawReasons is List) {
        return rawReasons
            .map((e) => e.toString().replaceAll(RegExp(r'[\u0900-\u097F]+'), '').replaceAll('()', '').trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return ['Recommended based on current climate outlook and soil compatibility.'];
    } else {
      if (rawReasons is List) {
        return rawReasons.map((e) {
          var str = e.toString();
          str = str.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '');
          return str.trim();
        }).toList();
      }
      return [];
    }
  }

  static List<String> _localizeRiskNotes(dynamic rawNotes, String lang) {
    if (rawNotes is! List) return [];
    if (lang == 'en') {
      return rawNotes.map((e) {
        final str = e.toString();
        if (str.contains('पाला') || str.contains('दिसंबर-जनवरी')) {
          return 'In case of frost in Dec-Jan, apply light irrigation or field-edge smoke.';
        } else if (str.contains('माहू') || str.contains('कीट')) {
          return 'Aphid pest risk during flowering; spray neem oil if noticed.';
        } else if (str.contains('सिंचाई') || str.contains('पानी')) {
          return 'Moderate water requirement (3-4 irrigations). If water is scarce, prioritize chickpea.';
        }
        return str.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').trim();
      }).where((s) => s.isNotEmpty).toList();
    } else {
      return rawNotes.map((e) {
        return e.toString().replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
      }).toList();
    }
  }

  factory CropRecommendationItem.fromJson(Map<String, dynamic> json, {String lang = 'hi'}) {
    final rawNameEn = (json['name_en'] as String? ?? '')
        .replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '')
        .replaceAll(RegExp(r'\s*\([\u0900-\u097F\s-]+\)'), '')
        .trim();
    final rawNameHi = (json['name_hi'] as String? ?? '')
        .replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '')
        .replaceAll(RegExp(r'\s*\([\u0900-\u097F\s-]+\)'), '')
        .trim();

    return CropRecommendationItem(
      rank: json['rank'] ?? 1,
      nameHi: rawNameHi.isNotEmpty ? rawNameHi : (json['name_hi'] ?? ''),
      nameEn: rawNameEn.isNotEmpty ? rawNameEn : (json['name_en'] ?? ''),
      season: json['season'] ?? 'rabi',
      matchScore: json['match_score'] ?? 80,
      durationDays: lang == 'en'
          ? (json['duration_days']?.toString() ?? '90-120 days').replaceAll('दिन', 'days')
          : (json['duration_days']?.toString() ?? '90-120 दिन').replaceAll('days', 'दिन'),
      waterNeedMm: (json['water_need_mm'] as num?)?.toDouble() ?? 350.0,
      droughtTolerance: json['drought_tolerance'] ?? 'medium',
      frostTolerance: json['frost_tolerance'] ?? 'medium',
      reasons: _localizeReasons(json['reasons'], rawNameEn, lang),
      riskNotes: _localizeRiskNotes(json['risk_notes'], lang),
      droughtAlternative: lang == 'en'
          ? (json['drought_tolerant_alternative']
              ?.toString()
              .replaceAll('चना', 'Chickpea')
              .replaceAll('सरसों', 'Mustard')
              .replaceAll('(Gram)', '')
              .replaceAll('(Mustard)', '')
              .trim())
          : (json['drought_tolerant_alternative']?.toString().replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim()),
      sourceCitation: json['source_citation'] ?? 'ICAR Guide',
      needsExpertReview: json['needs_expert_review'] ?? true,
    );
  }
}

class CropRecommenderScreen extends StatefulWidget {
  final int farmId;
  final String farmName;
  final String village;
  final FarmProfile? farm;
  final String? lang;

  const CropRecommenderScreen({
    super.key,
    this.farmId = 1,
    this.farmName = 'बड़ा खेत 1',
    this.village = 'उमरेड (Umred)',
    this.farm,
    this.lang,
  });

  @override
  State<CropRecommenderScreen> createState() => _CropRecommenderScreenState();
}

class _CropRecommenderScreenState extends State<CropRecommenderScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  late String _lang;
  late String _seasonTitle;
  late String _climateOutlookSummary;
  List<CropRecommendationItem> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _lang = widget.lang ?? 'hi';
    _seasonTitle = _lang == 'en' ? 'Rabi Season' : 'रबी सीजन';
    _climateOutlookSummary = _lang == 'en'
        ? 'Next 30 days: 35% below normal rainfall probability in region (EC46 / SEAS5)'
        : 'आगामी 30 दिनों में क्षेत्र में 35% कम वर्षा की संभावना (EC46 / SEAS5)';
    _fetchRecommendations();
  }

  @override
  void didUpdateWidget(covariant CropRecommenderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lang != widget.lang) {
      _lang = widget.lang ?? 'hi';
      _seasonTitle = _lang == 'en' ? 'Rabi Season' : 'रबी सीजन';
      _climateOutlookSummary = _lang == 'en'
          ? 'Next 30 days: 35% below normal rainfall probability in region (EC46 / SEAS5)'
          : 'आगामी 30 दिनों में क्षेत्र में 35% कम वर्षा की संभावना (EC46 / SEAS5)';
      _recommendations = _getOfflineRecommendations();
    }
  }

  Future<void> _fetchRecommendations() async {
    setState(() {
      _isLoading = true;
    });

    final data = await _apiService.getCropRecommendations(widget.farmId);
    if (data != null && data['recommendations'] != null) {
      final recs = (data['recommendations'] as List)
          .map((item) => CropRecommendationItem.fromJson(item, lang: _lang))
          .toList();

      if (mounted) {
        setState(() {
          if (_lang == 'en') {
            _seasonTitle = 'Rabi Season';
            _climateOutlookSummary = data['climate_outlook']?['summary_en'] ??
                'Next 30 days: 35% below normal rainfall probability in region (EC46 / SEAS5)';
          } else {
            _seasonTitle = (data['current_season'] as String? ?? 'रबी सीजन')
                .replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '')
                .trim();
            _climateOutlookSummary = (data['climate_outlook']?['summary_hi'] as String? ?? _climateOutlookSummary)
                .replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '')
                .trim();
          }
          _recommendations = recs;
          _isLoading = false;
        });
        return;
      }
    }

    // Offline fallback seed
    if (mounted) {
      setState(() {
        _recommendations = _getOfflineRecommendations();
        _isLoading = false;
      });
    }
  }

  List<CropRecommendationItem> _getOfflineRecommendations() {
    if (_lang == 'en') {
      return [
        CropRecommendationItem(
          rank: 1,
          nameHi: 'चना',
          nameEn: 'Chickpea',
          season: 'rabi',
          matchScore: 98,
          durationDays: '95-115 days',
          waterNeedMm: 280.0,
          droughtTolerance: 'high',
          frostTolerance: 'medium',
          reasons: [
            'Current season (Rabi sowing) is highly favorable for chickpea.',
            'Black soil moisture retention capacity is optimal for chickpea root system.',
            'Low water requirement: safest choice for rainfed or deficit irrigation plots.',
            'Drought-tolerant traits provide resilience against 30-day deficit rain forecast.',
          ],
          riskNotes: [
            'In case of frost in Dec-Jan, apply light irrigation or field-edge smoke.',
          ],
          sourceCitation: 'ICAR-IIPR Kanpur Chickpea Production Technology',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 2,
          nameHi: 'सरसों',
          nameEn: 'Mustard',
          season: 'rabi',
          matchScore: 94,
          durationDays: '105-130 days',
          waterNeedMm: 250.0,
          droughtTolerance: 'high',
          frostTolerance: 'medium',
          reasons: [
            'Major oilseed crop for Rabi season; high yield with minimal cost and water.',
            'High drought tolerance makes it resilient against deficit rainfall.',
          ],
          riskNotes: [
            'Aphid pest risk during flowering; spray neem oil if noticed.',
          ],
          sourceCitation: 'ICAR-DRMR Bharatpur',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 3,
          nameHi: 'गेहूं',
          nameEn: 'Wheat',
          season: 'rabi',
          matchScore: 88,
          durationDays: '110-135 days',
          waterNeedMm: 450.0,
          droughtTolerance: 'medium',
          frostTolerance: 'medium',
          reasons: [
            'Primary food grain crop with excellent output under assured irrigation.',
            'Well adapted to medium and heavy loam soils of Vidarbha region.',
          ],
          riskNotes: [
            'Moderate water requirement (3-4 irrigations). If water is scarce, prioritize chickpea.',
          ],
          droughtAlternative: 'Chickpea or Mustard',
          sourceCitation: 'ICAR-IIWBR Karnal',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 4,
          nameHi: 'अलसी',
          nameEn: 'Linseed',
          season: 'rabi',
          matchScore: 85,
          durationDays: '115-135 days',
          waterNeedMm: 250.0,
          droughtTolerance: 'high',
          frostTolerance: 'high',
          reasons: [
            'Low input cost; highly tolerant to both frost and drought.',
            'Good returns with conserved moisture in black soils.',
          ],
          riskNotes: [],
          sourceCitation: 'ICAR-AICRP Oilseeds',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 5,
          nameHi: 'मसूर',
          nameEn: 'Lentil',
          season: 'rabi',
          matchScore: 82,
          durationDays: '100-120 days',
          waterNeedMm: 220.0,
          droughtTolerance: 'high',
          frostTolerance: 'high',
          reasons: [
            'Low water consumption; fixes atmospheric nitrogen in farm soil.',
            'Safe crop under below-average rainfall forecast.',
          ],
          riskNotes: [],
          sourceCitation: 'ICAR-IIPR Kanpur',
          needsExpertReview: true,
        ),
      ];
    } else {
      return [
        CropRecommendationItem(
          rank: 1,
          nameHi: 'चना',
          nameEn: 'Chickpea',
          season: 'rabi',
          matchScore: 98,
          durationDays: '95-115 दिन',
          waterNeedMm: 280.0,
          droughtTolerance: 'high',
          frostTolerance: 'medium',
          reasons: [
            'वर्तमान समय (रबी बुवाई) इस फसल के लिए पूर्णतः अनुकूल है।',
            'काली कपासी मिट्टी में जल संचय क्षमता चने की जड़ों के लिए सर्वोत्तम है।',
            'कम पानी की आवश्यकता: असिंचित / वर्षा-आधारित खेत के लिए सर्वोत्तम सुरक्षित विकल्प।',
            '30-दिवसीय मौसम रुझान (कम वर्षा संभावना 35%) को देखते हुए सूखा-सहनशील गुण सुरक्षित रहेगा।',
          ],
          riskNotes: [
            'दिसंबर-जनवरी में पाला पड़ने पर हल्की सिंचाई या खेत की मेड़ पर धुआं करें।',
          ],
          sourceCitation: 'ICAR-IIPR Kanpur Chickpea Production Technology',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 2,
          nameHi: 'सरसों',
          nameEn: 'Mustard',
          season: 'rabi',
          matchScore: 94,
          durationDays: '105-130 दिन',
          waterNeedMm: 250.0,
          droughtTolerance: 'high',
          frostTolerance: 'medium',
          reasons: [
            'रबी सीजन की प्रमुख तिलहनी फसल, न्यूनतम लागत व कम पानी में भरपूर पैदावार।',
            'सूखा-सहनशील होने से 30-दिवसीय वर्षा कमी के जोखिम में सुरक्षित।',
          ],
          riskNotes: [
            'फूल आते समय माहू कीट का प्रकोप हो सकता है, नीम तेल स्प्रे करें।',
          ],
          sourceCitation: 'ICAR-DRMR Bharatpur',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 3,
          nameHi: 'गेहूं',
          nameEn: 'Wheat',
          season: 'rabi',
          matchScore: 88,
          durationDays: '110-135 दिन',
          waterNeedMm: 450.0,
          droughtTolerance: 'medium',
          frostTolerance: 'medium',
          reasons: [
            'रबी की प्रमुख खाद्यान्न फसल, सुनिश्चित सिंचाई पर उत्कृष्ट उत्पादन।',
            'नागपुर क्षेत्र की दोमट व भारी मिट्टी में अनुकूल।',
          ],
          riskNotes: [
            'मध्यम पानी की आवश्यकता (3-4 सिंचाई)। यदि जल स्रोत सीमित हो तो चने को प्राथमिकता दें।',
          ],
          droughtAlternative: 'चना या सरसों',
          sourceCitation: 'ICAR-IIWBR Karnal',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 4,
          nameHi: 'अलसी',
          nameEn: 'Linseed',
          season: 'rabi',
          matchScore: 85,
          durationDays: '115-135 दिन',
          waterNeedMm: 250.0,
          droughtTolerance: 'high',
          frostTolerance: 'high',
          reasons: [
            'कम लागत, पाला व सूखा दोनों के प्रति अत्यधिक सहनशील।',
            'काली मिट्टी में नमी संरक्षण के साथ बढ़िया लाभ।',
          ],
          riskNotes: [],
          sourceCitation: 'ICAR-AICRP Oilseeds',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 5,
          nameHi: 'मसूर दाल',
          nameEn: 'Lentil',
          season: 'rabi',
          matchScore: 82,
          durationDays: '100-120 दिन',
          waterNeedMm: 220.0,
          droughtTolerance: 'high',
          frostTolerance: 'high',
          reasons: [
            'अल्प जल खपत, दलहनी फसल होने से भूमि में नाइट्रोजन स्थिरीकरण।',
            'कम बारिश के पूर्वानुमान में सुरक्षित फसल।',
          ],
          riskNotes: [],
          sourceCitation: 'ICAR-IIPR Kanpur',
          needsExpertReview: true,
        ),
      ];
    }
  }

  Future<void> _callKvk() async {
    const phoneNumber = '18001801551';
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _lang == 'en'
                    ? 'KVK Helpline: 1800-180-1551'
                    : 'KVK हेल्पलाइन: 1800-180-1551',
              ),
              backgroundColor: const Color(0xFF1B5E20),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _lang == 'en'
                  ? 'KVK Helpline: 1800-180-1551'
                  : 'KVK हेल्पलाइन: 1800-180-1551',
            ),
            backgroundColor: const Color(0xFF1B5E20),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayFarmName = _lang == 'en'
        ? (widget.farm?.getName('en') ??
            (widget.farmName.contains(RegExp(r'[\u0900-\u097F]'))
                ? 'Main Farm'
                : widget.farmName.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim()))
        : (widget.farm?.getName('hi') ??
            (widget.farmName.toLowerCase().contains('farm')
                ? 'बड़ा खेत'
                : widget.farmName.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim()));
    final displayVillage = _lang == 'en'
        ? (widget.farm?.getVillage('en') ??
            (widget.village.contains('Umred') || widget.village.contains('उमरेड')
                ? 'Umred'
                : widget.village.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').trim()))
        : (widget.farm?.getVillage('hi') ??
            (widget.village.contains('Umred') || widget.village.contains('उमरेड')
                ? 'उमरेड'
                : widget.village.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim()));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: _lang == 'en' ? 'Back' : 'वापस जाएं',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _lang == 'en' ? 'Crop Advisory & Recommendations' : 'फसल चयन व सिफारिशें',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '$displayFarmName • $displayVillage',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: _lang == 'en' ? 'Refresh' : 'ताज़ा करें',
            onPressed: _fetchRecommendations,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFBF360C),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.mic, size: 26),
        label: Text(
          _lang == 'en' ? 'Ask Crop Questions' : 'फसल पर सवाल पूछें',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => KrishiSahayakScreen(
                farm: widget.farm,
                lang: _lang,
              ),
            ),
          );
        },
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF1B5E20)),
                  const SizedBox(height: 16),
                  Text(
                    _lang == 'en'
                        ? 'Finding optimal crops based on soil and weather...'
                        : 'आपके खेत व मौसम के अनुसार सर्वोत्तम फसलें खोजी जा रही हैं...',
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // Header Season & Climate Outlook Card
                _buildClimateOutlookCard(),
                const SizedBox(height: 12),

                // Expert Review Mandatory Warning
                _buildExpertReviewNotice(),
                const SizedBox(height: 16),

                // Top 5 Recommendations Section Header
                Row(
                  children: [
                    const Icon(Icons.eco, color: Color(0xFF1B5E20), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _lang == 'en' ? 'Top 5 Recommended Crops' : 'शीर्ष 5 अनुशंसित फसलें',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Crop Recommendation Cards
                ..._recommendations.map((crop) => _buildCropCard(crop)),

                const SizedBox(height: 16),
                // KVK Toll Free Helpline Footer Card
                _buildKvkHelplineCard(),
              ],
            ),
    );
  }

  Widget _buildClimateOutlookCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _seasonTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.wb_sunny_outlined, color: Colors.orange, size: 20),
              const SizedBox(width: 4),
              Text(
                _lang == 'en' ? 'EC46/SEAS5 Outlook' : 'EC46/SEAS5 आउटलुक',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _climateOutlookSummary,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _lang == 'en'
                ? 'Rule: Drought-resistant crops prioritized considering deficit rainfall risk.'
                : 'नियम: कम वर्षा जोखिम को ध्यान में रखते हुए सूखा-सहनशील फसलों को प्राथमिकता दी गई है।',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildExpertReviewNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.assignment_late, color: Colors.amber.shade900, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lang == 'en' ? 'Expert Review Advised' : 'विशेषज्ञ समीक्षा आवश्यक',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _lang == 'en'
                      ? 'These recommendations are based on ICAR Package of Practices standards. Consult local KVK expert and soil testing before sowing.'
                      : 'ये सिफारिशें ICAR एवं राज्य कृषि विश्वविद्यालयों के पैकेज ऑफ प्रैक्टिसेज के सामान्य मानकों पर आधारित हैं। बुवाई से पूर्व मिट्टी परीक्षण व स्थानीय KVK विशेषज्ञ से परामर्श लें।',
                  style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropCard(CropRecommendationItem crop) {
    final title = _lang == 'en' ? crop.nameEn : crop.nameHi;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Rank Badge + Crop Name + Score Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF1B5E20),
                  child: Text(
                    '#${crop.rank}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade400),
                  ),
                  child: Text(
                    _lang == 'en' ? '${crop.matchScore}% Match' : '${crop.matchScore}% उपयुक्त',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Trait Badges Row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildTraitBadge(
                  Icons.timelapse,
                  _lang == 'en' ? 'Duration' : 'अवधि',
                  crop.durationDays,
                ),
                _buildTraitBadge(
                  Icons.water_drop,
                  _lang == 'en' ? 'Water' : 'पानी',
                  '${crop.waterNeedMm.toInt()} mm',
                ),
                _buildTraitBadge(
                  Icons.wb_sunny,
                  _lang == 'en' ? 'Drought' : 'सूखा सहनशीलता',
                  crop.droughtTolerance == 'high'
                      ? (_lang == 'en' ? 'High' : 'उच्च')
                      : crop.droughtTolerance == 'medium'
                          ? (_lang == 'en' ? 'Medium' : 'मध्यम')
                          : (_lang == 'en' ? 'Low' : 'कम'),
                ),
                _buildTraitBadge(
                  Icons.ac_unit,
                  _lang == 'en' ? 'Frost' : 'पाला सहनशीलता',
                  crop.frostTolerance == 'high'
                      ? (_lang == 'en' ? 'High' : 'उच्च')
                      : crop.frostTolerance == 'medium'
                          ? (_lang == 'en' ? 'Medium' : 'मध्यम')
                          : (_lang == 'en' ? 'Low' : 'कम'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),

            // Reasons Section
            Text(
              _lang == 'en' ? 'Suitability Reasons:' : 'उपयुक्तता के मुख्य कारण:',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            ...crop.reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          r,
                          style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                )),

            // Risk Notes or Drought Alternative
            if (crop.riskNotes.isNotEmpty || crop.droughtAlternative != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...crop.riskNotes.map((rn) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber, color: Colors.deepOrange, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                rn,
                                style: const TextStyle(fontSize: 12, color: Colors.brown, height: 1.3),
                              ),
                            ),
                          ],
                        )),
                    if (crop.droughtAlternative != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.alt_route, color: Colors.deepPurple, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _lang == 'en'
                                  ? 'Safe alternative in deficit rain: ${crop.droughtAlternative}'
                                  : 'कम वर्षा में सुरक्षित विकल्प: ${crop.droughtAlternative}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
            // Citation
            Text(
              _lang == 'en' ? 'Source: ${crop.sourceCitation}' : 'स्रोत: ${crop.sourceCitation}',
              style: const TextStyle(fontSize: 10, color: Colors.black45, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTraitBadge(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1B5E20)),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildKvkHelplineCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.support_agent, color: Colors.white, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lang == 'en' ? 'Kisan Call Center (KVK)' : 'किसान कॉल सेंटर (KVK)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _lang == 'en'
                      ? 'Toll-free 1800-180-1551 to discuss with agriculture experts'
                      : 'टोल-फ्री 1800-180-1551 पर कृषि वैज्ञानिक से निःशुल्क चर्चा करें',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1B5E20),
              minimumSize: const Size(80, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: _callKvk,
            child: Text(
              _lang == 'en' ? 'Call Now' : 'कॉल करें',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
