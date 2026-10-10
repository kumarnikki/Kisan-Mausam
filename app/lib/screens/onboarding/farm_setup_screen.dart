import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/farm_profile.dart';
import '../../services/storage_service.dart';

class FarmSetupScreen extends StatefulWidget {
  final VoidCallback onFarmCreated;
  final VoidCallback? onBack;

  const FarmSetupScreen({
    super.key,
    required this.onFarmCreated,
    this.onBack,
  });

  @override
  State<FarmSetupScreen> createState() => _FarmSetupScreenState();
}

class _FarmSetupScreenState extends State<FarmSetupScreen> {
  final _nameController = TextEditingController(text: 'बड़ा खेत 1');
  final _villageController = TextEditingController(text: 'उमरेड');
  final _districtController = TextEditingController(text: 'नागपुर');
  final _stateController = TextEditingController(text: 'महाराष्ट्र');
  final _acresController = TextEditingController(text: '4.5');
  final _cropController = TextEditingController(text: 'सोयाबीन');

  String _terrain = 'plain';
  String _soilType = 'black';
  String _irrigationType = 'tube-well';
  String _cropStage = 'flowering';
  String _lang = 'hi';

  @override
  void initState() {
    super.initState();
    StorageService.getLanguage().then((l) {
      if (mounted) {
        setState(() {
          _lang = l;
          if (_lang == 'en') {
            _nameController.text = 'Farm 1';
            _villageController.text = 'Umred';
            _districtController.text = 'Nagpur';
            _stateController.text = 'Maharashtra';
            _cropController.text = 'Soybean';
          } else {
            _nameController.text = 'बड़ा खेत 1';
            _villageController.text = 'उमरेड';
            _districtController.text = 'नागपुर';
            _stateController.text = 'महाराष्ट्र';
            _cropController.text = 'सोयाबीन';
          }
        });
      }
    });
  }

  void _saveFarm() async {
    final farm = FarmProfile(
      id: 1,
      name: _nameController.text.trim().isEmpty
          ? (_lang == 'en' ? 'My Farm' : 'मेरा खेत')
          : _nameController.text.trim(),
      latitude: 21.1458,
      longitude: 79.0882,
      village: _villageController.text.trim(),
      district: _districtController.text.trim(),
      state: _stateController.text.trim(),
      terrain: _terrain,
      soilType: _soilType,
      irrigationType: _irrigationType,
      landSizeAcres: double.tryParse(_acresController.text) ?? 3.0,
      currentCrop: _cropController.text.trim(),
      cropStage: _cropStage,
      sowingDate: '2026-07-01',
    );

    await StorageService.saveFarms([farm]);
    await StorageService.setActiveFarmId(1);
    await StorageService.setOnboardingComplete(true);
    widget.onFarmCreated();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: _lang == 'hi' ? 'वापस जाएं' : 'Back',
                onPressed: widget.onBack,
              )
            : null,
        title: Text(AppStrings.get('farm_setup_title', _lang)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.get('farm_setup_subtitle', _lang),
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),
              // Farm Name & Location
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppStrings.get('farm_name', _lang),
                  prefixIcon: const Icon(Icons.agriculture),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _villageController,
                      decoration: InputDecoration(
                        labelText: AppStrings.get('village', _lang),
                        prefixIcon: const Icon(Icons.home_work_outlined),
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
                        prefixIcon: const Icon(Icons.location_city),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Terrain Picker (Big Icons)
              Text(
                AppStrings.get('terrain_title', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 28),
              // Soil Picker (Big Icons)
              Text(
                AppStrings.get('soil_title', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 28),
              // Irrigation Picker
              Text(
                AppStrings.get('irrigation_title', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 28),
              // Land Size & Crop
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _acresController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: AppStrings.get('land_size', _lang),
                        prefixIcon: const Icon(Icons.square_foot),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _cropController,
                      decoration: InputDecoration(
                        labelText: AppStrings.get('current_crop', _lang),
                        prefixIcon: const Icon(Icons.eco),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Crop Stage Picker
              Text(
                AppStrings.get('crop_stage', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 36),
              ElevatedButton(
                onPressed: _saveFarm,
                child: Text(AppStrings.get('finish_setup', _lang)),
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
