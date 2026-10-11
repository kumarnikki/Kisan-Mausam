import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/farm_profile.dart';
import '../../services/alert_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';

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
  final _customCropController = TextEditingController();

  String _selectedCropKey = 'Wheat';
  bool _isOtherCrop = false;
  String _terrain = 'plain';
  String _soilType = 'loamy';
  String _irrigationType = 'tube-well';
  String _cropStage = 'vegetative';
  String _lang = 'hi';
  double _lat = 21.1458;
  double _lon = 79.0882;
  bool _detectingGps = false;
  bool _touchedValidation = false;

  static const List<Map<String, String>> _popularCrops = [
    {'key': 'Wheat', 'hi': 'गेहूं', 'en': 'Wheat'},
    {'key': 'Paddy', 'hi': 'धान', 'en': 'Paddy'},
    {'key': 'Chickpea', 'hi': 'चना', 'en': 'Chickpea'},
    {'key': 'Mustard', 'hi': 'सरसों', 'en': 'Mustard'},
    {'key': 'Maize', 'hi': 'मक्का', 'en': 'Maize'},
    {'key': 'Sugarcane', 'hi': 'गन्ना', 'en': 'Sugarcane'},
    {'key': 'Cotton', 'hi': 'कपास', 'en': 'Cotton'},
    {'key': 'Potato', 'hi': 'आलू', 'en': 'Potato'},
    {'key': 'Soybean', 'hi': 'सोयाबीन', 'en': 'Soybean'},
    {'key': 'Vegetables', 'hi': 'सब्जियां', 'en': 'Vegetables'},
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  bool _isPlaceholderLocation(String val) {
    final lower = val.trim().toLowerCase();
    return lower.isEmpty ||
        lower == 'villae' ||
        lower == 'village' ||
        lower == 'district' ||
        lower == 'my village' ||
        lower == 'मेरा गांव';
  }

  Future<void> _loadExistingProfile() async {
    final l = await StorageService.getLanguage();
    final savedUserName = await StorageService.getUserName();
    var savedPhone = await StorageService.getUserPhone();
    if (savedPhone == null || savedPhone.isEmpty) {
      savedPhone = await AlertService.detectSimPhoneNumber();
      if (savedPhone != null && savedPhone.isNotEmpty) {
        await StorageService.saveUserPhone(savedPhone);
      }
    }
    final profileConfigured = await StorageService.isProfileConfigured();
    final farms = await StorageService.getFarms();

    if (!mounted) return;
    setState(() {
      _lang = l;
      if (savedPhone != null && savedPhone.isNotEmpty) {
        _phoneController.text = savedPhone;
      }
      if (savedUserName != null &&
          savedUserName.isNotEmpty &&
          !savedUserName.startsWith('किसान (+91') &&
          !savedUserName.startsWith('Farmer (+91')) {
        _farmerNameController.text = savedUserName;
      }

      if (profileConfigured && farms.isNotEmpty) {
        final f = farms.first;
        _nameController.text = f.name;
        _villageController.text = _isPlaceholderLocation(f.village) ? '' : f.village;
        _districtController.text = _isPlaceholderLocation(f.district) ? '' : f.district;
        _stateController.text = f.state;
        _acresController.text = f.landSizeAcres.toString();
        _terrain = f.terrain;
        _soilType = f.soilType;
        _irrigationType = f.irrigationType;
        _cropStage = f.cropStage;
        _lat = f.latitude;
        _lon = f.longitude;

        final existingCrop = f.currentCrop.trim();
        final matched = _popularCrops.where((c) =>
            existingCrop.toLowerCase().contains(c['en']!.toLowerCase()) ||
            existingCrop.contains(c['hi']!));
        if (matched.isNotEmpty) {
          _selectedCropKey = matched.first['key']!;
          _isOtherCrop = false;
        } else if (existingCrop.isNotEmpty) {
          _selectedCropKey = '__other__';
          _isOtherCrop = true;
          _customCropController.text = existingCrop;
        }
      } else {
        _nameController.text = '';
        _villageController.text = '';
        _districtController.text = '';
        _stateController.text = '';
        _acresController.text = '2.5';
        _selectedCropKey = 'Wheat';
        _isOtherCrop = false;
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
    _customCropController.dispose();
    super.dispose();
  }

  String _resolvedCropText() {
    final isEn = _lang == 'en';
    if (_isOtherCrop) {
      return _customCropController.text.trim();
    }
    final match = _popularCrops.firstWhere(
      (c) => c['key'] == _selectedCropKey,
      orElse: () => _popularCrops.first,
    );
    return isEn ? match['en']! : match['hi']!;
  }

  bool get _isCropValid => _resolvedCropText().isNotEmpty;

  bool get _isAcresValid {
    final val = double.tryParse(_acresController.text.trim());
    return val != null && val > 0 && val <= 10000;
  }

  bool get _isLocationValid {
    final v = _villageController.text.trim();
    final d = _districtController.text.trim();
    if (v.isEmpty && d.isEmpty) return true;
    return !_isPlaceholderLocation(v) && (d.isEmpty || !_isPlaceholderLocation(d));
  }

  bool get _isFormValid => _isCropValid && _isAcresValid && _isLocationValid;

  Future<void> _detectGps() async {
    setState(() => _detectingGps = true);
    final res = await LocationService.getCurrentLocation(lang: _lang);
    if (!mounted) return;
    setState(() => _detectingGps = false);
    if (res != null) {
      final parts = res.displayName.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final detectedVillage = parts.isNotEmpty ? parts.first : '';
      final detectedDistrict = parts.length > 1 ? parts[1] : detectedVillage;
      setState(() {
        _lat = res.latitude;
        _lon = res.longitude;
        if (!_isPlaceholderLocation(detectedVillage)) {
          _villageController.text = detectedVillage;
        }
        if (!_isPlaceholderLocation(detectedDistrict)) {
          _districtController.text = detectedDistrict;
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _lang == 'en'
                ? 'Could not detect GPS location. Enter your village or district below.'
                : 'GPS स्थान नहीं मिल सका। कृपया नीचे अपना गाँव या जिला लिखें।',
          ),
        ),
      );
    }
  }

  Future<void> _saveFarm() async {
    setState(() => _touchedValidation = true);
    if (!_isFormValid) return;

    final isEn = _lang == 'en';
    final farmerName = _farmerNameController.text.trim();
    if (farmerName.isNotEmpty) {
      await StorageService.saveUserName(farmerName);
    }
    final rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (rawPhone.length >= 10) {
      final ten = rawPhone.substring(rawPhone.length - 10);
      await StorageService.saveUserPhone(ten);
    }

    final cropText = _resolvedCropText().isEmpty
        ? (isEn ? 'Wheat' : 'गेहूं')
        : _resolvedCropText();

    final rawVillage = _villageController.text.trim();
    final rawDistrict = _districtController.text.trim();

    final cleanVillage = _isPlaceholderLocation(rawVillage)
        ? (rawDistrict.isNotEmpty && !_isPlaceholderLocation(rawDistrict)
            ? rawDistrict
            : (isEn ? 'Nagpur' : 'नागपुर'))
        : rawVillage;

    final cleanDistrict = _isPlaceholderLocation(rawDistrict)
        ? cleanVillage
        : rawDistrict;

    final farm = FarmProfile(
      id: 1,
      name: _nameController.text.trim().isEmpty
          ? (farmerName.isNotEmpty
              ? (isEn ? "$farmerName's Farm" : '$farmerName का खेत')
              : (isEn ? 'My Farm' : 'मेरा खेत'))
          : _nameController.text.trim(),
      latitude: _lat,
      longitude: _lon,
      village: cleanVillage,
      district: cleanDistrict,
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
    final textPrimary = AppTheme.textPrimary(context);

    final cropOptions = <ChoiceChipOption<String>>[
      ..._popularCrops.map(
        (c) => ChoiceChipOption(value: c['key']!, label: isEn ? c['en']! : c['hi']!),
      ),
      ChoiceChipOption(
        value: '__other__',
        label: AppStrings.get('crop_other', _lang),
      ),
    ];

    final stageOptions = <ChoiceChipOption<String>>[
      ChoiceChipOption(value: 'sowing', label: AppStrings.get('stage_sowing', _lang)),
      ChoiceChipOption(value: 'vegetative', label: AppStrings.get('stage_vegetative', _lang)),
      ChoiceChipOption(value: 'flowering', label: AppStrings.get('stage_flowering', _lang)),
      ChoiceChipOption(value: 'grain_fill', label: AppStrings.get('stage_grain_fill', _lang)),
      ChoiceChipOption(value: 'harvest', label: AppStrings.get('stage_harvest', _lang)),
    ];

    final terrainOptions = <ChoiceChipOption<String>>[
      ChoiceChipOption(value: 'plain', label: AppStrings.get('terrain_plain', _lang)),
      ChoiceChipOption(value: 'hilly', label: AppStrings.get('terrain_hilly', _lang)),
      ChoiceChipOption(value: 'plateau', label: AppStrings.get('terrain_plateau', _lang)),
      ChoiceChipOption(value: 'coastal', label: AppStrings.get('terrain_coastal', _lang)),
      ChoiceChipOption(value: 'barren-dry', label: AppStrings.get('terrain_barren', _lang)),
    ];

    final soilOptions = <ChoiceChipOption<String>>[
      ChoiceChipOption(value: 'alluvial', label: AppStrings.get('soil_alluvial', _lang)),
      ChoiceChipOption(value: 'black', label: AppStrings.get('soil_black', _lang)),
      ChoiceChipOption(value: 'red', label: AppStrings.get('soil_red', _lang)),
      ChoiceChipOption(value: 'sandy', label: AppStrings.get('soil_sandy', _lang)),
      ChoiceChipOption(value: 'loamy', label: AppStrings.get('soil_loamy', _lang)),
    ];

    final irrigationOptions = <ChoiceChipOption<String>>[
      ChoiceChipOption(value: 'rain-fed', label: AppStrings.get('irrigation_rainfed', _lang)),
      ChoiceChipOption(value: 'tube-well', label: AppStrings.get('irrigation_tubewell', _lang)),
      ChoiceChipOption(value: 'canal', label: AppStrings.get('irrigation_canal', _lang)),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        quiet: true,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header (with onboarding step indicator if not editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    if (widget.onBack != null)
                      IconAction(
                        icon: Icons.arrow_back_rounded,
                        semanticLabel: isEn ? 'Back' : 'वापस जाएं',
                        onPressed: widget.onBack!,
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!widget.isEditing)
                            Text(
                              isEn ? 'Step 4 of 4' : 'चरण 4 / 4',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryActionColor(context),
                              ),
                            ),
                          Text(
                            widget.isEditing
                                ? (isEn ? 'Edit Profile & Farm' : 'प्रोफाइल व खेत संपादित करें')
                                : AppStrings.get('farm_setup_title', _lang),
                            style: AppTheme.titleStyle.copyWith(color: textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Scrollable Single-Column Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.screenPadding,
                    8,
                    AppTheme.screenPadding,
                    AppTheme.s24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section 1: Farm
                      SectionHeader(title: AppStrings.get('profile_section_farm', _lang)),
                      AppSurface(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _farmerNameController,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: AppStrings.get('farmer_name_label', _lang),
                                hintText: isEn ? 'Enter your name' : 'अपना नाम लिखें',
                                prefixIcon: const Icon(Icons.person_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              maxLength: 10,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: isEn
                                    ? 'Mobile Number (for Weather & SOS SMS)'
                                    : 'मोबाइल नंबर (मौसम व SOS SMS अलर्ट हेतु)',
                                hintText: isEn ? '10-digit mobile number' : '10 अंकों का मोबाइल नंबर',
                                prefixText: '+91 ',
                                counterText: '',
                                prefixIcon: const Icon(Icons.phone_android_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: AppStrings.get('farm_name', _lang),
                                hintText: isEn ? 'e.g. Home Field' : 'जैसे: मुख्य खेत',
                                prefixIcon: const Icon(Icons.agriculture_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SecondaryButton(
                              label: _detectingGps
                                  ? (isEn ? 'Detecting GPS...' : 'GPS खोजा जा रहा है...')
                                  : AppStrings.get('use_current_gps', _lang),
                              icon: Icons.my_location_rounded,
                              onPressed: _detectingGps ? null : _detectGps,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _villageController,
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: AppStrings.get('village', _lang),
                                hintText: isEn ? 'e.g. Rampur' : 'जैसे: रामपुर',
                                prefixIcon: const Icon(Icons.holiday_village_rounded),
                                errorText: _touchedValidation && !_isLocationValid
                                    ? (isEn ? 'Enter a valid village name' : 'सही गाँव का नाम लिखें')
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _districtController,
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: AppStrings.get('district', _lang),
                                hintText: isEn ? 'e.g. Karnal' : 'जैसे: करनाल',
                                prefixIcon: const Icon(Icons.location_city_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.s24),

                      // Section 2: Crop & Land Size
                      SectionHeader(title: AppStrings.get('profile_section_crop', _lang)),
                      AppSurface(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              AppStrings.get('current_crop', _lang),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ChoiceChipGroup<String>(
                              selectedValue: _isOtherCrop ? '__other__' : _selectedCropKey,
                              options: cropOptions,
                              onSelected: (val) {
                                setState(() {
                                  if (val == '__other__') {
                                    _isOtherCrop = true;
                                    _selectedCropKey = '__other__';
                                  } else {
                                    _isOtherCrop = false;
                                    _selectedCropKey = val;
                                  }
                                });
                              },
                            ),
                            AnimatedSize(
                              duration: AppTheme.motionDuration(
                                context,
                                const Duration(milliseconds: 220),
                              ),
                              curve: Curves.easeOutCubic,
                              child: _isOtherCrop
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: TextField(
                                        controller: _customCropController,
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                          labelText: AppStrings.get('crop_other', _lang),
                                          hintText: AppStrings.get('crop_other_hint', _lang),
                                          prefixIcon: const Icon(Icons.eco_rounded),
                                          errorText: !_isCropValid
                                              ? (isEn
                                                  ? 'Please enter crop name'
                                                  : 'कृपया फसल का नाम लिखें')
                                              : null,
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _acresController,
                              onChanged: (_) => setState(() {}),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: AppStrings.get('land_size', _lang),
                                hintText: '2.5',
                                suffixText: AppStrings.get('acres_suffix', _lang),
                                prefixIcon: const Icon(Icons.square_foot_rounded),
                                errorText: !_isAcresValid
                                    ? (isEn
                                        ? 'Enter valid land size in acres'
                                        : 'एकड़ में सही भूमि क्षेत्र दर्ज करें')
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppStrings.get('crop_stage', _lang),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ChoiceChipGroup<String>(
                              selectedValue: _cropStage,
                              options: stageOptions,
                              onSelected: (v) => setState(() => _cropStage = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.s24),

                      // Section 3: Field Details (Terrain, Soil, Irrigation as text-only ChoiceChipGroups)
                      SectionHeader(title: AppStrings.get('profile_section_field', _lang)),
                      AppSurface(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              AppStrings.get('terrain_title', _lang),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ChoiceChipGroup<String>(
                              selectedValue: _terrain,
                              options: terrainOptions,
                              onSelected: (v) => setState(() => _terrain = v),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              AppStrings.get('soil_title', _lang),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ChoiceChipGroup<String>(
                              selectedValue: _soilType,
                              options: soilOptions,
                              onSelected: (v) => setState(() => _soilType = v),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              AppStrings.get('irrigation_title', _lang),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ChoiceChipGroup<String>(
                              selectedValue: _irrigationType,
                              options: irrigationOptions,
                              onSelected: (v) => setState(() => _irrigationType = v),
                            ),
                          ],
                        ),
                      ),
                      if (!_isFormValid) ...[
                        const SizedBox(height: 12),
                        Text(
                          isEn
                              ? 'Please complete crop and land size to save.'
                              : 'सहेजने के लिए कृपया फसल और भूमि क्षेत्र पूरा करें।',
                          style: AppTheme.labelStyle.copyWith(color: AppTheme.danger),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Sticky bottom Save bar (respects safe area and keyboard)
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.screenPadding,
                  10,
                  AppTheme.screenPadding,
                  12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceFill(context),
                  border: Border(top: BorderSide(color: AppTheme.borderColor(context))),
                ),
                child: PrimaryButton(
                  label: widget.isEditing
                      ? AppStrings.get('save_profile_btn', _lang)
                      : AppStrings.get('finish_setup', _lang),
                  icon: Icons.check_rounded,
                  onPressed: _isFormValid ? _saveFarm : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
