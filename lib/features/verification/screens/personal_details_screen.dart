import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import 'in_app_camera_screen.dart';
import '../services/egyptian_id_ocr.dart';

class PersonalDetailsScreen extends ConsumerStatefulWidget {
  const PersonalDetailsScreen({super.key, required this.role});

  final String role;

  @override
  ConsumerState<PersonalDetailsScreen> createState() =>
      _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends ConsumerState<PersonalDetailsScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  String _selectedGender = 'male';
  XFile? _idFrontPhoto;
  String? _recognizedText;
  String? _ocrNationalId;
  bool _readingId = false;

  Future<void> _scanIdFront() async {
    final photo = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(
        builder: (_) => InAppCameraScreen(title: AppStrings.idFront(context)),
      ),
    );
    if (photo == null || !mounted) return;
    setState(() {
      _idFrontPhoto = photo;
      _readingId = true;
      _recognizedText = null;
    });
    try {
      final result = await EgyptianIdOcr.readFront(photo.path);
      if (!mounted) return;
      setState(() {
        _recognizedText = result.rawText;
        _ocrNationalId = result.nationalId;
        if (result.nationalId != null) {
          _idController.text = result.nationalId!;
        }
        final birthDate = _birthDateFromNationalId(result.nationalId);
        if (birthDate != null) {
          _dobController.text =
              '${birthDate.day}/${birthDate.month}/${birthDate.year}';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _recognizedText =
              'تعذرت قراءة البطاقة. راجع البيانات يدويًا أو أعد التصوير.',
        );
      }
    } finally {
      if (mounted) setState(() => _readingId = false);
    }
  }

  DateTime? _birthDateFromNationalId(String? id) {
    if (id == null || id.length != 14) return null;
    final century = id[0] == '2'
        ? 1900
        : id[0] == '3'
        ? 2000
        : null;
    if (century == null) return null;
    final year = century + int.parse(id.substring(1, 3));
    final month = int.parse(id.substring(3, 5));
    final day = int.parse(id.substring(5, 7));
    final date = DateTime.tryParse(
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    return date != null &&
            date.year == year &&
            date.month == month &&
            date.day == day
        ? date
        : null;
  }

  @override
  void dispose() {
    _idController.dispose();
    _dobController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _onSaveAndContinue() {
    final nationalId = _idController.text.trim();
    final dateParts = _dobController.text.split('/');
    if (!RegExp(r'^\d{14}$').hasMatch(nationalId) || dateParts.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'أدخل الرقم القومي المكوّن من 14 رقمًا وتاريخ الميلاد.',
          ),
        ),
      );
      return;
    }
    final dateOfBirth = DateTime.tryParse(
      '${dateParts[2]}-${dateParts[1].padLeft(2, '0')}-${dateParts[0].padLeft(2, '0')}',
    );
    if (_ocrNationalId != null && _ocrNationalId != nationalId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'الرقم المدخل لا يطابق الرقم المقروء من البطاقة. راجعه أو أعد التصوير.',
          ),
        ),
      );
      return;
    }
    if (dateOfBirth == null || !dateOfBirth.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تاريخ الميلاد غير صحيح.')));
      return;
    }
    if (_idFrontPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('صوّر الوجه الأمامي للبطاقة بالكاميرا أولًا.'),
        ),
      );
      return;
    }
    context.push(
      '/verification/identity',
      extra: {
        'role': widget.role,
        'nationalId': nationalId,
        'dateOfBirth': dateOfBirth.toIso8601String(),
        'idFrontPath': _idFrontPhoto!.path,
      },
    );
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
              OutlinedButton.icon(
                onPressed: _readingId ? null : _scanIdFront,
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  _idFrontPhoto == null
                      ? 'صوّر البطاقة لقراءة بياناتها'
                      : 'إعادة تصوير البطاقة',
                ),
              ),
              if (_readingId) const LinearProgressIndicator(),
              if (_recognizedText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'النص المقروء من البطاقة:\n$_recognizedText',
                    textDirection: TextDirection.rtl,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 16),
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
                      _dobController.text =
                          '${picked.day}/${picked.month}/${picked.year}';
                    });
                  }
                },
                decoration: InputDecoration(
                  hintText: AppStrings.tr(
                    context,
                    ar: 'يوم / شهر / سنة',
                    en: 'DD / MM / YYYY',
                  ),
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
                      onPressed: () =>
                          setState(() => _selectedGender = 'female'),
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
                  hintText: AppStrings.tr(
                    context,
                    ar: 'القاهرة، الجيزة، الإسكندرية...',
                    en: 'Cairo, Giza, Alexandria...',
                  ),
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
