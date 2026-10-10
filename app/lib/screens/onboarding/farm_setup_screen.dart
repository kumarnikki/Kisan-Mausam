import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/farm_profile.dart';
import '../../services/storage_service.dart';

class FarmSetupScreen extends StatefulWidget {
  final VoidCallback onFarmCreated;
  final VoidCallback? onBack;
  final bool isEditing;

  const FarmSetupScreen({
    super.key,
    required this.onFarmCreated,
    this.onBack,
    this.isEditing = false,
  });

  @override
  State<FarmSetupScreen> createState() => _FarmSetupScreenState();
}

class _FarmSetupScreenState extends State<FarmSetupScreen> {
  final _farmerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _villageController = TextEditingController();
  final _districtController = TextEditingController();
  final _stateController = TextEditingController();
  final _acresController = TextEditingController(text: '2.5');
  final _cropController = TextEditingController();

  String _terrain = 'plain';
  String _soilType = 'loamy';
  String _irrigationType = 'tube-well';
  String _cropStage = 'vegetative';
  String _lang = 'hi';
  double _lat = 21.1458;
  double _lon = 79.0882;

  static const List<Map<String, String>> _popularCrops = [
    {'hi': 'गेहूं', 'en': 'Wheat'},
    {'hi': 'धान', 'en': 'Paddy'},
    {'hi': 'चना', 'en': 'Chickpea'},
    {'hi': 'सरसों', 'en': 'Mustard'},
    {'hi': 'मक्का', 'en': 'Maize'},
    {'hi': 'गन्ना', 'en': 'Sugarcane'},
    {'hi': 'कपास', 'en': 'Cotton'},
    {'hi': 'आलू', 'en': 'Potato'},
    {'hi': 'सोयाबीन', 'en': 'Soybean'},
    {'hi': 'सब्जियां', 'en': 'Vegetables'},
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    final l = await StorageService.getLanguage();
    final savedUserName = await StorageService.getUserName();
    final savedPhone = await StorageService.getUserPhone();
    final profileConfigured = await StorageService.isProfileConfigured();
    final farms = await StorageService.getFarms();

    if (!mounted) return;
    setState(() {
      _lang = l;
      if (savedUserName != null &&
          savedUserName.isNotEmpty &&
          !savedUserName.startsWith('किसान (+91') &&
          !savedUserName.startsWith('Farmer (+91')) {
        _farmerNameController.text = savedUserName;
      }
      if (savedPhone != null && savedPhone.isNotEmpty) {
        _phoneController.text = savedPhone;
      }

      if (profileConfigured && farms.isNotEmpty) {
        final f = farms.first;
        _nameController.text = f.name;
        _villageController.text = f.village;
        _districtController.text = f.district;
        _stateController.text = f.state;
        _acresController.text = f.landSizeAcres.toString();
        _cropController.text = f.currentCrop;
        _terrain = f.terrain;
        _soilType = f.soilType;
        _irrigationType = f.irrigationType;
        _cropStage = f.cropStage;
        _lat = f.latitude;
        _lon = f.longitude;
      } else {
        // Clean defaults for new account setup (not forcing Soybean)
        _nameController.text = _lang == 'en' ? 'My Farm' : 'मेरा खेत';
        _villageController.text = '';
        _districtController.text = '';
        _stateController.text = '';
        _acresController.text = '2.5';
        _cropController.text = _lang == 'en' ? 'Wheat' : 'गेहूं';
      }
    });
  }

  @override
  void dispose() {
    _farmerNameController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _villageController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _acresController.dispose();
    _cropController.dispose();
    super.dispose();
  }

  void _saveFarm() async {
    final isEn = _lang == 'en';
    final farmerName = _farmerNameController.text.trim();
    if (farmerName.isNotEmpty) {
      await StorageService.saveUserName(farmerName);
    }
    final rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (rawPhone.length >= 10) {
      await StorageService.saveUserPhone(rawPhone.substring(rawPhone.length - 10));
    }

    final cropText = _cropController.text.trim().isEmpty
        ? (isEn ? 'Wheat' : 'गेहूं')
        : _cropController.text.trim();

    final villageText = _villageController.text.trim().isEmpty
        ? (isEn ? 'My Village' : 'मेरा गांव')
        : _villageController.text.trim();

    final districtText = _districtController.text.trim().isEmpty
        ? villageText
        : _districtController.text.trim();

    final farm = FarmProfile(
      id: 1,
      name: _nameController.text.trim().isEmpty
          ? (farmerName.isNotEmpty
              ? (isEn ? "$farmerName's Farm" : '$farmerName का खेत')
              : (isEn ? 'My Farm' : 'मेरा खेत'))
          : _nameController.text.trim(),
      latitude: _lat,
      longitude: _lon,
      village: villageText,
      district: districtText,
      state: _stateController.text.trim().isEmpty
          ? (isEn ? 'India' : 'भारत')
          : _stateController.text.trim(),
      terrain: _terrain,
      soilType: _soilType,
      irrigationType: _irrigationType,
      landSizeAcres: double.tryParse(_acresController.text.trim()) ?? 2.5,
      currentCrop: cropText,
      cropStage: _cropStage,
      sowingDate: '2026-10-01',
    );

    await StorageService.saveFarms([farm]);
    await StorageService.setActiveFarmId(1);
    await StorageService.setProfileConfigured(true);
    await StorageService.setOnboardingComplete(true);
    widget.onFarmCreated();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _lang == 'en';
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: _lang == 'hi' ? 'वापस जाएं' : 'Back',
                onPressed: widget.onBack,
              )
            : null,
        title: Text(
          widget.isEditing
              ? (isEn ? 'Edit Farmer & Crop Profile' : 'किसान व फसल प्रोफाइल संपादित करें')
              : AppStrings.get('farm_setup_title', _lang),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isEditing
                    ? (isEn
                        ? 'Update your name, crops, land area, and soil details anytime.'
                        : 'अपना नाम, वर्तमान फसल, भूमि क्षेत्र और मिट्टी का विवरण यहाँ अपडेट करें।')
                    : AppStrings.get('farm_setup_subtitle', _lang),
                style: TextStyle(fontSize: 14.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 20),

              // 1. Farmer Name & Mobile Number
              TextField(
                controller: _farmerNameController,
                decoration: InputDecoration(
                  labelText: isEn ? 'Farmer Name (Your Name)' : 'किसान का नाम (आपका नाम)',
                  hintText: isEn ? 'Enter your full name' : 'अपना नाम लिखें',
                  prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF1B5E20)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: InputDecoration(
                        labelText: isEn ? 'Mobile Number' : 'मोबाइल नंबर',
                        prefixText: '+91 ',
                        counterText: '',
                        prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: AppStrings.get('farm_name', _lang),
                        prefixIcon: const Icon(Icons.agriculture, color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 2. Village & District
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _villageController,
                      decoration: InputDecoration(
                        labelText: AppStrings.get('village', _lang),
                        hintText: isEn ? 'e.g. Rampur' : 'जैसे: रामपुर',
                        prefixIcon: const Icon(Icons.home_work_outlined, color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _districtController,
                      decoration: InputDecoration(
                        labelText: AppStrings.get('district', _lang),
                        hintText: isEn ? 'e.g. Karnal' : 'जैसे: करनाल',
                        prefixIcon: const Icon(Icons.location_city, color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // 3. Current Crop Selection (Quick Chips + Custom Input)
              Text(
                isEn ? 'Select Your Crop(s)' : 'अपनी वर्तमान फसल चुनें',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _popularCrops.map((cropMap) {
                  final label = isEn ? cropMap['en']! : cropMap['hi']!;
                  final isSelected = _cropController.text.trim().toLowerCase() == label.toLowerCase();
                  return ChoiceChip(
                    label: Text(
                      label,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? const Color(0xFF1B5E20) : Colors.black87,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFFE8F5E9),
                    onSelected: (_) => setState(() => _cropController.text = label),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cropController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: AppStrings.get('current_crop', _lang),
                        hintText: isEn ? 'Type or pick crop above' : 'ऊपर से चुनें या फसल लिखें',
                        prefixIcon: const Icon(Icons.eco, color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _acresController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: AppStrings.get('land_size', _lang),
                        hintText: isEn ? 'Acres (e.g. 3.5)' : 'एकड़ (जैसे 3.5)',
                        prefixIcon: const Icon(Icons.square_foot, color: Color(0xFF1B5E20)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 4. Crop Stage Picker
              Text(
                AppStrings.get('crop_stage', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StageChip(
                    label: AppStrings.get('stage_sowing', _lang),
                    isSelected: _cropStage == 'sowing',
                    onTap: () => setState(() => _cropStage = 'sowing'),
                  ),
                  _StageChip(
                    label: AppStrings.get('stage_vegetative', _lang),
                    isSelected: _cropStage == 'vegetative',
                    onTap: () => setState(() => _cropStage = 'vegetative'),
                  ),
                  _StageChip(
                    label: AppStrings.get('stage_flowering', _lang),
                    isSelected: _cropStage == 'flowering',
                    onTap: () => setState(() => _cropStage = 'flowering'),
                  ),
                  _StageChip(
                    label: AppStrings.get('stage_grain_fill', _lang),
                    isSelected: _cropStage == 'grain_fill',
                    onTap: () => setState(() => _cropStage = 'grain_fill'),
                  ),
                  _StageChip(
                    label: AppStrings.get('stage_harvest', _lang),
                    isSelected: _cropStage == 'harvest',
                    onTap: () => setState(() => _cropStage = 'harvest'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 5. Terrain Picker (Big Icons)
              Text(
                AppStrings.get('terrain_title', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _BigIconPicker(
                    icon: Icons.landscape_outlined,
                    label: AppStrings.get('terrain_plain', _lang),
                    isSelected: _terrain == 'plain',
                    onTap: () => setState(() => _terrain = 'plain'),
                  ),
                  _BigIconPicker(
                    icon: Icons.terrain,
                    label: AppStrings.get('terrain_hilly', _lang),
                    isSelected: _terrain == 'hilly',
                    onTap: () => setState(() => _terrain = 'hilly'),
                  ),
                  _BigIconPicker(
                    icon: Icons.filter_hdr,
                    label: AppStrings.get('terrain_plateau', _lang),
                    isSelected: _terrain == 'plateau',
                    onTap: () => setState(() => _terrain = 'plateau'),
                  ),
                  _BigIconPicker(
                    icon: Icons.waves,
                    label: AppStrings.get('terrain_coastal', _lang),
                    isSelected: _terrain == 'coastal',
                    onTap: () => setState(() => _terrain = 'coastal'),
                  ),
                  _BigIconPicker(
                    icon: Icons.wb_sunny_outlined,
                    label: AppStrings.get('terrain_barren', _lang),
                    isSelected: _terrain == 'barren-dry',
                    onTap: () => setState(() => _terrain = 'barren-dry'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 6. Soil Picker (Big Icons)
              Text(
                AppStrings.get('soil_title', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _BigIconPicker(
                    icon: Icons.grass,
                    label: AppStrings.get('soil_alluvial', _lang),
                    isSelected: _soilType == 'alluvial',
                    onTap: () => setState(() => _soilType = 'alluvial'),
                  ),
                  _BigIconPicker(
                    icon: Icons.circle,
                    label: AppStrings.get('soil_black', _lang),
                    isSelected: _soilType == 'black',
                    onTap: () => setState(() => _soilType = 'black'),
                  ),
                  _BigIconPicker(
                    icon: Icons.grain,
                    label: AppStrings.get('soil_red', _lang),
                    isSelected: _soilType == 'red',
                    onTap: () => setState(() => _soilType = 'red'),
                  ),
                  _BigIconPicker(
                    icon: Icons.beach_access,
                    label: AppStrings.get('soil_sandy', _lang),
                    isSelected: _soilType == 'sandy',
                    onTap: () => setState(() => _soilType = 'sandy'),
                  ),
                  _BigIconPicker(
                    icon: Icons.spa,
                    label: AppStrings.get('soil_loamy', _lang),
                    isSelected: _soilType == 'loamy',
                    onTap: () => setState(() => _soilType = 'loamy'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 7. Irrigation Picker
              Text(
                AppStrings.get('irrigation_title', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _BigIconPicker(
                    icon: Icons.cloudy_snowing,
                    label: AppStrings.get('irrigation_rainfed', _lang),
                    isSelected: _irrigationType == 'rain-fed',
                    onTap: () => setState(() => _irrigationType = 'rain-fed'),
                  ),
                  _BigIconPicker(
                    icon: Icons.water_drop,
                    label: AppStrings.get('irrigation_tubewell', _lang),
                    isSelected: _irrigationType == 'tube-well',
                    onTap: () => setState(() => _irrigationType = 'tube-well'),
                  ),
                  _BigIconPicker(
                    icon: Icons.alt_route,
                    label: AppStrings.get('irrigation_canal', _lang),
                    isSelected: _irrigationType == 'canal',
                    onTap: () => setState(() => _irrigationType = 'canal'),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saveFarm,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  widget.isEditing
                      ? (isEn ? 'Save Profile & Crop Changes' : 'प्रोफाइल व फसल विवरण सहेजें')
                      : AppStrings.get('finish_setup', _lang),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigIconPicker extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BigIconPicker({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF1B5E20) : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: isSelected ? const Color(0xFF1B5E20) : Colors.grey.shade700),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF1B5E20) : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StageChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: const Color(0xFFE8F5E9),
      labelStyle: TextStyle(color: isSelected ? const Color(0xFF1B5E20) : Colors.black87),
      onSelected: (_) => onTap(),
    );
  }
}
