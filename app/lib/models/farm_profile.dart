class FarmProfile {
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final String village;
  final String district;
  final String state;
  final String terrain;
  final String soilType;
  final String irrigationType;
  final double landSizeAcres;
  final String currentCrop;
  final String cropStage;
  final String sowingDate;

  FarmProfile({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.village,
    required this.district,
    required this.state,
    required this.terrain,
    required this.soilType,
    required this.irrigationType,
    required this.landSizeAcres,
    required this.currentCrop,
    required this.cropStage,
    required this.sowingDate,
  });

  factory FarmProfile.fromJson(Map<String, dynamic> json) {
    return FarmProfile(
      id: json['id'] ?? 1,
      name: json['name'] ?? 'खेत 1',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 21.1458,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 79.0882,
      village: json['village'] ?? 'उमरेड (Umred)',
      district: json['district'] ?? 'नागपुर (Nagpur)',
      state: json['state'] ?? 'महाराष्ट्र (Maharashtra)',
      terrain: json['terrain'] ?? 'plain',
      soilType: json['soil_type'] ?? 'black',
      irrigationType: json['irrigation_type'] ?? 'tube-well',
      landSizeAcres: (json['land_size_acres'] as num?)?.toDouble() ?? 3.0,
      currentCrop: json['current_crop'] ?? 'सोयाबीन (Soybean)',
      cropStage: json['crop_stage'] ?? 'flowering',
      sowingDate: json['sowing_date'] ?? '2026-07-01',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'village': village,
    'district': district,
    'state': state,
    'terrain': terrain,
    'soil_type': soilType,
    'irrigation_type': irrigationType,
    'land_size_acres': landSizeAcres,
    'current_crop': currentCrop,
    'crop_stage': cropStage,
    'sowing_date': sowingDate,
  };
}
