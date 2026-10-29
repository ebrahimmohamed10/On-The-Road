import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class PersonalDetailsScreen extends ConsumerStatefulWidget {
  const PersonalDetailsScreen({super.key});

  @override
  ConsumerState<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends ConsumerState<PersonalDetailsScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  String _selectedGender = 'male';

  @override
  void dispose() {
    _idController.dispose();
    _dobController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _onSaveAndContinue() {
    context.push('/verification/identity');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.personalDetails(context),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.personalDetailsSub(context),
                style: theme.textTheme.bodyMedium,
              ),

              const SizedBox(height: 32),

              // حقل الرقم القومي
              Text(
                AppStrings.nationalId(context),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _idController,
                keyboardType: TextInputType.number,
                maxLength: 14,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  hintText: '2980101XXXXXXXXX',
                  prefixIcon: Icon(Icons.badge_outlined),
                  counterText: '',
                ),
              ),

              const SizedBox(height: 20),

              // حقل تاريخ الميلاد
              Text(
                AppStrings.dateOfBirth(context),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dobController,
                readOnly: true,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(2000),
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _dobController.text = '${picked.day}/${picked.month}/${picked.year}';
                    });
                  }
                },
                decoration: InputDecoration(
                  hintText: AppStrings.tr(context, ar: 'يوم / شهر / سنة', en: 'DD / MM / YYYY'),
                  prefixIcon: const Icon(Icons.calendar_today_rounded),
                ),
              ),

              const SizedBox(height: 20),

              // تحديد النوع (ذكر / أنثى)
              Text(
                AppStrings.gender(context),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _selectedGender == 'male'
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                            : Colors.transparent,
                        side: BorderSide(
                          color: _selectedGender == 'male'
                              ? const Color(0xFFF59E0B)
                              : theme.dividerColor.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      onPressed: () => setState(() => _selectedGender = 'male'),
                      child: Text(
                        AppStrings.male(context),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _selectedGender == 'male'
                              ? const Color(0xFFF59E0B)
                              : theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _selectedGender == 'female'
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                            : Colors.transparent,
                        side: BorderSide(
                          color: _selectedGender == 'female'
                              ? const Color(0xFFF59E0B)
                              : theme.dividerColor.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      onPressed: () => setState(() => _selectedGender = 'female'),
                      child: Text(
                        AppStrings.female(context),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _selectedGender == 'female'
                              ? const Color(0xFFF59E0B)
                              : theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // حقل المحافظة / المدينة
              Text(
                AppStrings.city(context),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cityController,
                decoration: InputDecoration(
                  hintText: AppStrings.tr(context, ar: 'القاهرة، الجيزة، الإسكندرية...', en: 'Cairo, Giza, Alexandria...'),
                  prefixIcon: const Icon(Icons.location_city_rounded),
                ),
              ),

              const SizedBox(height: 36),

              // زر حفظ ومتابعة
              ElevatedButton(
                onPressed: _onSaveAndContinue,
                child: Text(AppStrings.saveAndContinue(context)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

