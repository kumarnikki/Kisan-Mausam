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
      village: json['village'] ?? 'उमरेड',
      district: json['district'] ?? 'नागपुर',
      state: json['state'] ?? 'महाराष्ट्र',
      terrain: json['terrain'] ?? 'plain',
      soilType: json['soil_type'] ?? 'black',
      irrigationType: json['irrigation_type'] ?? 'tube-well',
      landSizeAcres: (json['land_size_acres'] as num?)?.toDouble() ?? 3.0,
      currentCrop: json['current_crop'] ?? 'गेहूं',
      cropStage: json['crop_stage'] ?? 'vegetative',
      sowingDate: json['sowing_date'] ?? '2026-10-01',
    );
  }

  String getName(String lang) {
    if (lang == 'en') {
      if (name == 'बड़ा खेत 1' || name == 'बड़ा खेत' || name == 'मेरा खेत' || name == 'खेत 1') {
        return 'My Farm';
      }
      return name.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
    } else {
      if (name == 'Main Farm' || name == 'My Farm') {
        return 'मेरा खेत';
      }
      return name.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
    }
  }

  String getVillage(String lang) {
    if (lang == 'en') {
      if (village.contains('Umred') || village.contains('उमरेड')) return 'Umred';
      final clean = village.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').replaceAll(RegExp(r'[()]'), '').trim();
      return clean.isEmpty ? village : clean;
    } else {
      if (village.contains('Umred') || village.contains('उमरेड')) return 'उमरेड';
      return village.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
    }
  }

  String getDistrict(String lang) {
    if (lang == 'en') {
      if (district.contains('Nagpur') || district.contains('नागपुर')) return 'Nagpur';
      final clean = district.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').replaceAll(RegExp(r'[()]'), '').trim();
      return clean.isEmpty ? district : clean;
    } else {
      if (district.contains('Nagpur') || district.contains('नागपुर')) return 'नागपुर';
      return district.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
    }
  }

  String getState(String lang) {
    if (lang == 'en') {
      if (state.contains('Maharashtra') || state.contains('महाराष्ट्र')) return 'Maharashtra';
      final clean = state.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').replaceAll(RegExp(r'[()]'), '').trim();
      return clean.isEmpty ? state : clean;
    } else {
      if (state.contains('Maharashtra') || state.contains('महाराष्ट्र')) return 'महाराष्ट्र';
      return state.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
    }
  }

  String getCurrentCrop(String lang) {
    if (lang == 'en') {
      if (currentCrop.contains('Wheat') || currentCrop.contains('गेहूं')) return 'Wheat';
      if (currentCrop.contains('Paddy') || currentCrop.contains('Rice') || currentCrop.contains('धान')) return 'Paddy';
      if (currentCrop.contains('Chickpea') || currentCrop.contains('Gram') || currentCrop.contains('चना')) return 'Chickpea';
      if (currentCrop.contains('Mustard') || currentCrop.contains('सरसों')) return 'Mustard';
      if (currentCrop.contains('Maize') || currentCrop.contains('मक्का')) return 'Maize';
      if (currentCrop.contains('Sugarcane') || currentCrop.contains('गन्ना')) return 'Sugarcane';
      if (currentCrop.contains('Cotton') || currentCrop.contains('कपास')) return 'Cotton';
      if (currentCrop.contains('Potato') || currentCrop.contains('आलू')) return 'Potato';
      if (currentCrop.contains('Soybean') || currentCrop.contains('सोयाबीन')) return 'Soybean';
      if (currentCrop.contains('Vegetables') || currentCrop.contains('सब्जियां')) return 'Vegetables';
      final clean = currentCrop.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').replaceAll(RegExp(r'[()]'), '').trim();
      return clean.isEmpty ? currentCrop : clean;
    } else {
      if (currentCrop.contains('Wheat') || currentCrop.contains('गेहूं')) return 'गेहूं';
      if (currentCrop.contains('Paddy') || currentCrop.contains('Rice') || currentCrop.contains('धान')) return 'धान';
      if (currentCrop.contains('Chickpea') || currentCrop.contains('Gram') || currentCrop.contains('चना')) return 'चना';
      if (currentCrop.contains('Mustard') || currentCrop.contains('सरसों')) return 'सरसों';
      if (currentCrop.contains('Maize') || currentCrop.contains('मक्का')) return 'मक्का';
      if (currentCrop.contains('Sugarcane') || currentCrop.contains('गन्ना')) return 'गन्ना';
      if (currentCrop.contains('Cotton') || currentCrop.contains('कपास')) return 'कपास';
      if (currentCrop.contains('Potato') || currentCrop.contains('आलू')) return 'आलू';
      if (currentCrop.contains('Soybean') || currentCrop.contains('सोयाबीन')) return 'सोयाबीन';
      if (currentCrop.contains('Vegetables') || currentCrop.contains('सब्जियां')) return 'सब्जियां';
      return currentCrop.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
    }
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
