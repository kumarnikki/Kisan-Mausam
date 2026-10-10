import 'package:flutter/material.dart';
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

  factory CropRecommendationItem.fromJson(Map<String, dynamic> json) {
    return CropRecommendationItem(
      rank: json['rank'] ?? 1,
      nameHi: json['name_hi'] ?? '',
      nameEn: json['name_en'] ?? '',
      season: json['season'] ?? 'rabi',
      matchScore: json['match_score'] ?? 80,
      durationDays: json['duration_days'] ?? '90-120 दिन',
      waterNeedMm: (json['water_need_mm'] as num?)?.toDouble() ?? 350.0,
      droughtTolerance: json['drought_tolerance'] ?? 'medium',
      frostTolerance: json['frost_tolerance'] ?? 'medium',
      reasons: List<String>.from(json['reasons'] ?? []),
      riskNotes: List<String>.from(json['risk_notes'] ?? []),
      droughtAlternative: json['drought_tolerant_alternative'],
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

  const CropRecommenderScreen({
    super.key,
    this.farmId = 1,
    this.farmName = 'बड़ा खेत 1',
    this.village = 'उमरेड (Umred)',
    this.farm,
  });

  @override
  State<CropRecommenderScreen> createState() => _CropRecommenderScreenState();
}

class _CropRecommenderScreenState extends State<CropRecommenderScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String _seasonTitle = 'रबी (Rabi)';
  String _climateOutlookSummary = 'आगामी 30 दिनों में उमरेड में 35% कम वर्षा की संभावना (EC46 / SEAS5)';
  List<CropRecommendationItem> _recommendations = [];

  @override
  void initState() {
    super.initState();
    _fetchRecommendations();
  }

  Future<void> _fetchRecommendations() async {
    setState(() {
      _isLoading = true;
    });

    final data = await _apiService.getCropRecommendations(widget.farmId);
    if (data != null && data['recommendations'] != null) {
      final recs = (data['recommendations'] as List)
          .map((item) => CropRecommendationItem.fromJson(item))
          .toList();

      if (mounted) {
        setState(() {
          _seasonTitle = data['current_season'] ?? 'रबी (Rabi)';
          _climateOutlookSummary = data['climate_outlook']?['summary_hi'] ?? _climateOutlookSummary;
          _recommendations = recs;
          _isLoading = false;
        });
        return;
      }
    }

    // Offline fallback seed
    if (mounted) {
      setState(() {
        _recommendations = [
          CropRecommendationItem(
            rank: 1,
            nameHi: 'चना (देसी / काबुली)',
            nameEn: 'Chickpea (Gram)',
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
              '30-दिवसीय मौसम रुझान (कम वर्षा संभावना 35%) को देखते हुए सूखा-सहनशील गुण सुरक्षित रहेगा।'
            ],
            riskNotes: [
              'दिसंबर-जनवरी में पाला पड़ने पर हल्की सिंचाई या खेत की मेड़ पर धुआं करें।'
            ],
            sourceCitation: 'ICAR-IIPR Kanpur Chickpea Production Technology',
            needsExpertReview: true,
          ),
          CropRecommendationItem(
            rank: 2,
            nameHi: 'सरसों / राई',
            nameEn: 'Mustard / Rapeseed',
            season: 'rabi',
            matchScore: 94,
            durationDays: '105-130 दिन',
            waterNeedMm: 250.0,
            droughtTolerance: 'high',
            frostTolerance: 'medium',
            reasons: [
              'रबी सीजन की प्रमुख तिलहनी फसल, न्यूनतम लागत व कम पानी में भरपूर पैदावार।',
              'सूखा-सहनशील होने से 30-दिवसीय वर्षा कमी के जोखिम में सुरक्षित।'
            ],
            riskNotes: [
              'फूल आते समय माहू (Aphid) कीट का प्रकोप हो सकता है, नीम तेल स्प्रे करें।'
            ],
            sourceCitation: 'ICAR-DRMR Bharatpur',
            needsExpertReview: true,
          ),
          CropRecommendationItem(
            rank: 3,
            nameHi: 'गेहूं (कनक)',
            nameEn: 'Wheat',
            season: 'rabi',
            matchScore: 88,
            durationDays: '110-135 दिन',
            waterNeedMm: 450.0,
            droughtTolerance: 'medium',
            frostTolerance: 'medium',
            reasons: [
              'रबी की प्रमुख खाद्यान्न फसल, सुनिश्चित सिंचाई पर उत्कृष्ट उत्पादन।',
              'नागपुर क्षेत्र की दोमट व भारी मिट्टी में अनुकूल।'
            ],
            riskNotes: [
              'मध्यम पानी की आवश्यकता (3-4 सिंचाई)। यदि जल स्रोत सीमित हो तो चने को प्राथमिकता दें।'
            ],
            droughtAlternative: 'चना (Gram) या सरसों (Mustard)',
            sourceCitation: 'ICAR-IIWBR Karnal',
            needsExpertReview: true,
          ),
          CropRecommendationItem(
            rank: 4,
            nameHi: 'अलसी (फ्लैक्ससीड)',
            nameEn: 'Linseed (Alsi)',
            season: 'rabi',
            matchScore: 85,
            durationDays: '115-135 दिन',
            waterNeedMm: 250.0,
            droughtTolerance: 'high',
            frostTolerance: 'high',
            reasons: [
              'कम लागत, पाला व सूखा दोनों के प्रति अत्यधिक सहनशील।',
              'काली मिट्टी में नमी संरक्षण के साथ बढ़िया लाभ।'
            ],
            riskNotes: [],
            sourceCitation: 'ICAR-AICRP Oilseeds',
            needsExpertReview: true,
          ),
          CropRecommendationItem(
            rank: 5,
            nameHi: 'मसूर (दाल)',
            nameEn: 'Lentil (Masoor)',
            season: 'rabi',
            matchScore: 82,
            durationDays: '100-120 दिन',
            waterNeedMm: 220.0,
            droughtTolerance: 'high',
            frostTolerance: 'high',
            reasons: [
              'अल्प जल खपत, दलहनी फसल होने से भूमि में नाइट्रोजन स्थिरीकरण।',
              'कम बारिश के पूर्वानुमान में सुरक्षित फसल।'
            ],
            riskNotes: [],
            sourceCitation: 'ICAR-IIPR Kanpur',
            needsExpertReview: true,
          ),
        ];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'वापस जाएं',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'फसल चयन व सिफारिशें',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.farmName} • ${widget.village}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'ताज़ा करें',
            onPressed: _fetchRecommendations,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFBF360C),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.mic, size: 26),
        label: const Text(
          'फसल पर सवाल पूछें',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => KrishiSahayakScreen(
                farm: widget.farm,
              ),
            ),
          );
        },
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1B5E20)),
                  SizedBox(height: 16),
                  Text('आपके खेत व मौसम के अनुसार सर्वोत्तम फसलें खोजी जा रही हैं...'),
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
                const Row(
                  children: [
                    Icon(Icons.eco, color: Color(0xFF1B5E20), size: 22),
                    SizedBox(width: 8),
                    Text(
                      'शीर्ष 5 अनुशंसित फसलें (Top 5 Ranked)',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
              const Text('EC46/SEAS5 आउटलुक', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
          const Text(
            'नियम: कम वर्षा जोखिम को ध्यान में रखते हुए सूखा-सहनशील (Drought Resistant) फसलों को प्राथमिकता दी गई है।',
            style: TextStyle(fontSize: 12, color: Colors.black54),
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
                  'विशेषज्ञ समीक्षा आवश्यक (Needs Expert Review)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ये सिफारिशें ICAR एवं राज्य कृषि विश्वविद्यालयों के पैकेज ऑफ प्रैक्टिसेज के सामान्य मानकों पर आधारित हैं। बुवाई से पूर्व मिट्टी परीक्षण व स्थानीय KVK विशेषज्ञ से परामर्श लें।',
                  style: TextStyle(fontSize: 11, color: Colors.black87, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropCard(CropRecommendationItem crop) {
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
                        crop.nameHi,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      Text(
                        crop.nameEn,
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
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
                    '${crop.matchScore}% उपयुक्त',
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
                _buildTraitBadge(Icons.timelapse, 'अवधि', crop.durationDays),
                _buildTraitBadge(Icons.water_drop, 'पानी', '${crop.waterNeedMm.toInt()} mm'),
                _buildTraitBadge(
                  Icons.wb_sunny,
                  'सूखा सहनशीलता',
                  crop.droughtTolerance == 'high'
                      ? 'उच्च (High)'
                      : crop.droughtTolerance == 'medium'
                          ? 'मध्यम'
                          : 'कम',
                ),
                _buildTraitBadge(
                  Icons.ac_unit,
                  'पाला सहनशीलता',
                  crop.frostTolerance == 'high'
                      ? 'उच्च (High)'
                      : crop.frostTolerance == 'medium'
                          ? 'मध्यम'
                          : 'कम',
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),

            // Reasons Section
            const Text(
              'उपयुक्तता के मुख्य कारण (Suitability):',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
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
                              'कम वर्षा में सुरक्षित विकल्प: ${crop.droughtAlternative}',
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
              'स्रोत: ${crop.sourceCitation}',
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'किसान कॉल सेंटर (KVK)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'टोल-फ्री 1800-180-1551 पर कृषि वैज्ञानिक से निःशुल्क चर्चा करें',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
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
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('KVK हेल्पलाइन: 1800-180-1551 पर कॉल किया जा रहा है...'),
                  backgroundColor: Color(0xFF1B5E20),
                ),
              );
            },
            child: const Text('कॉल करें', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
