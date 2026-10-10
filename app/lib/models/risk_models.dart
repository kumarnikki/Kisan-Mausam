class DetectedRisk {
  final String alertType;
  final String titleHi;
  final String titleEn;
  final String severity; // red, orange, yellow, info
  final double probability;
  final String confidence; // High, Medium, Low-Medium
  final String expectedValue;
  final String? expectedDate;
  final String actionHi;
  final String actionEn;
  final String? accuracyStatementHi;

  DetectedRisk({
    required this.alertType,
    required this.titleHi,
    required this.titleEn,
    required this.severity,
    required this.probability,
    required this.confidence,
    required this.expectedValue,
    this.expectedDate,
    required this.actionHi,
    required this.actionEn,
    this.accuracyStatementHi,
  });

  factory DetectedRisk.fromJson(Map<String, dynamic> json) {
    return DetectedRisk(
      alertType: json['alert_type'] ?? '',
      titleHi: json['title_hi'] ?? '',
      titleEn: json['title_en'] ?? '',
      severity: json['severity'] ?? 'yellow',
      probability: (json['probability'] as num?)?.toDouble() ?? 50.0,
      confidence: json['confidence'] ?? 'Medium',
      expectedValue: json['expected_value'] ?? '',
      expectedDate: json['expected_date'],
      actionHi: json['action_hi'] ?? '',
      actionEn: json['action_en'] ?? '',
      accuracyStatementHi: json['accuracy_compliant_statement_hi'],
    );
  }
}

class RiskHorizon {
  final String horizonName;
  final String horizonNameHi;
  final String confidence;
  final String confidenceHi;
  final String source;
  final String updatedAt;
  final List<DetectedRisk> risks;

  RiskHorizon({
    required this.horizonName,
    required this.horizonNameHi,
    required this.confidence,
    required this.confidenceHi,
    required this.source,
    required this.updatedAt,
    required this.risks,
  });

  factory RiskHorizon.fromJson(Map<String, dynamic> json) {
    final list = (json['risks_detected'] as List?) ?? [];
    return RiskHorizon(
      horizonName: json['horizon_name'] ?? '',
      horizonNameHi: json['horizon_name_hi'] ?? json['horizon_name'] ?? '',
      confidence: json['confidence'] ?? 'Medium',
      confidenceHi: json['confidence_hi'] ?? json['confidence'] ?? '',
      source: json['source'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      risks: list.map((e) => DetectedRisk.fromJson(e)).toList(),
    );
  }
}

class EnsoSummary {
  final String phase;
  final String phaseHi;
  final String status;
  final String statusHi;
  final double oniValue;
  final String source;
  final String updatedAt;
  final Map<String, dynamic> probabilities;
  final String explanationHi;
  final String officialLink;

  EnsoSummary({
    required this.phase,
    required this.phaseHi,
    required this.status,
    required this.statusHi,
    required this.oniValue,
    required this.source,
    required this.updatedAt,
    required this.probabilities,
    required this.explanationHi,
    required this.officialLink,
  });

  factory EnsoSummary.fromJson(Map<String, dynamic> json) {
    return EnsoSummary(
      phase: json['phase'] ?? 'Neutral',
      phaseHi: json['phase_hi'] ?? 'तटस्थ (Neutral)',
      status: json['status'] ?? '',
      statusHi: json['status_hi'] ?? '',
      oniValue: (json['oni_value'] as num?)?.toDouble() ?? 0.0,
      source: json['source'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      probabilities: json['probabilities'] as Map<String, dynamic>? ?? {},
      explanationHi: json['monsoon_impact_explanation_hi'] ?? '',
      officialLink: json['official_imd_link'] ?? 'https://imdpune.gov.in',
    );
  }
}

class FarmRiskData {
  final int farmId;
  final String farmName;
  final String village;
  final String crop;
  final String cropStage;
  final RiskHorizon horizon1;
  final RiskHorizon horizon2;
  final RiskHorizon horizon3;
  final EnsoSummary enso;

  FarmRiskData({
    required this.farmId,
    required this.farmName,
    required this.village,
    required this.crop,
    required this.cropStage,
    required this.horizon1,
    required this.horizon2,
    required this.horizon3,
    required this.enso,
  });

  factory FarmRiskData.fromJson(Map<String, dynamic> json) {
    return FarmRiskData(
      farmId: json['farm_id'] ?? 1,
      farmName: json['farm_name'] ?? 'खेत',
      village: json['village'] ?? '',
      crop: json['crop'] ?? '',
      cropStage: json['crop_stage'] ?? '',
      horizon1: RiskHorizon.fromJson(json['horizon_1_3d'] ?? {}),
      horizon2: RiskHorizon.fromJson(json['horizon_4_10d'] ?? {}),
      horizon3: RiskHorizon.fromJson(json['horizon_10_46d_seasonal'] ?? {}),
      enso: EnsoSummary.fromJson(json['enso_summary'] ?? {}),
    );
  }
}
