import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../services/egyptian_id_ocr.dart';
import 'in_app_camera_screen.dart';

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
  final Map<String, XFile> _editedDocuments = {};
  final Map<String, String> _savedDocumentUrls = {};
  String? _ocrMessage;
  String? _ocrNationalId;
  bool _readingId = false;
  bool _loadingSavedDetails = true;
  bool _hasSavedDetails = false;
  bool _isEditing = true;

  @override
  void initState() {
    super.initState();
    _loadSavedDetails();
  }

  Future<void> _loadSavedDetails() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingSavedDetails = false);
      return;
    }
    try {
      final details = await client
          .from('user_private_details')
          .select('national_id,date_of_birth,city,gender')
          .eq('user_id', user.id)
          .maybeSingle();
      final nationalId = details?['national_id'] as String?;
      final rawDob = details?['date_of_birth'] as String?;
      final hasDetails = nationalId != null && rawDob != null;
      if (hasDetails) {
        final dob = DateTime.tryParse(rawDob);
        _idController.text = nationalId;
        if (dob != null) {
          _dobController.text = '${dob.day}/${dob.month}/${dob.year}';
        }
        final inferredGender = EgyptianIdOcr.genderFromNationalId(nationalId);
        _selectedGender =
            details?['gender'] as String? ?? inferredGender ?? 'male';
        final savedCity = details?['city'] as String?;
        _cityController.text = savedCity == null || savedCity.trim().isEmpty
            ? EgyptianIdOcr.governorateFromNationalId(nationalId) ?? ''
            : savedCity;
        _hasSavedDetails = true;
        _isEditing = false;

        final request = await client
            .from('verification_requests')
            .select('id')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (request != null) {
          final documents = await client
              .from('verification_documents')
              .select('document_type,storage_path')
              .eq('verification_request_id', request['id'])
              .inFilter('document_type', [
                'national_id_front',
                'national_id_back',
                'driver_license_front',
                'driver_license_back',
              ]);
          for (final document in documents) {
            final type = document['document_type'] as String?;
            final path = document['storage_path'] as String?;
            if (type != null && path != null && path.isNotEmpty) {
              _savedDocumentUrls[type] = await client.storage
                  .from('identity-documents')
                  .createSignedUrl(path, 3600);
            }
          }
        }
      }
    } catch (_) {
      // Keep the form usable for a fresh or manually re-entered submission.
    } finally {
      if (mounted) setState(() => _loadingSavedDetails = false);
    }
  }

  Future<void> _scanIdFront() async {
    final useCloudOcr = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          AppStrings.tr(
            context,
            ar: 'قراءة بيانات البطاقة',
            en: 'Read ID card details',
          ),
        ),
        content: Text(
          AppStrings.tr(
            context,
            ar: 'ستُرسل صورة وجه البطاقة إلى Google Cloud Vision لقراءة النص. يمكنك اختيار الإدخال اليدوي بدلًا من ذلك.',
            en: 'The ID front image will be sent to Google Cloud Vision for text recognition. You can choose manual entry instead.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              AppStrings.tr(context, ar: 'إدخال يدوي', en: 'Enter manually'),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.tr(context, ar: 'متابعة', en: 'Continue')),
          ),
        ],
      ),
    );
    if (!mounted || useCloudOcr == null) return;

    final photo = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(
        builder: (_) => InAppCameraScreen(
          title: AppStrings.tr(
            context,
            ar: 'مسح وجه البطاقة الأمامي',
            en: 'Scan ID card front',
          ),
        ),
      ),
    );
    if (photo == null || !mounted) return;
    setState(() {
      _idFrontPhoto = photo;
      _readingId = useCloudOcr;
      _ocrMessage = null;
      _ocrNationalId = null;
    });
    if (!useCloudOcr) {
      setState(() => _ocrMessage = 'manual_entry_without_cloud_ocr');
      return;
    }
    try {
      final result = await EgyptianIdOcr.readFront(photo.path);
      if (!mounted) return;
      setState(() {
        _ocrNationalId = result.nationalId;
        _ocrMessage = result.nationalId == null
            ? 'id_number_not_found'
            : 'id_number_read';
        if (result.nationalId != null) {
          _idController.text = result.nationalId!;
          final gender = EgyptianIdOcr.genderFromNationalId(result.nationalId!);
          if (gender != null) _selectedGender = gender;
          final governorate = EgyptianIdOcr.governorateFromNationalId(
            result.nationalId!,
          );
          if (governorate != null) _cityController.text = governorate;
        }
        final birthDate = _birthDateFromNationalId(result.nationalId);
        if (birthDate != null) {
          _dobController.text =
              '${birthDate.day}/${birthDate.month}/${birthDate.year}';
        }
      });
    } on EgyptianIdOcrException catch (error) {
      if (mounted) {
        setState(
          () => _ocrMessage = switch (error.failure) {
            EgyptianIdOcrFailure.notConfigured => 'ocr_not_configured',
            EgyptianIdOcrFailure.signInRequired => 'ocr_sign_in_required',
            EgyptianIdOcrFailure.googlePermissionDenied =>
              'ocr_google_permission_denied',
            EgyptianIdOcrFailure.providerUnavailable => 'ocr_unavailable',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _ocrMessage = 'ocr_unavailable');
    } finally {
      if (mounted) setState(() => _readingId = false);
    }
  }

  String _ocrFeedback(BuildContext context, String message) {
    switch (message) {
      case 'manual_entry_without_cloud_ocr':
        return AppStrings.tr(
          context,
          ar: 'تم تصوير البطاقة بدون إرسالها إلى Google. أدخل البيانات يدويًا.',
          en: 'The card was captured without sending it to Google. Enter details manually.',
        );
      case 'image_picker_unavailable':
        return AppStrings.tr(
          context,
          ar: 'تعذر فتح الكاميرا أو الصور. تحقق من الأذونات ثم حاول مرة أخرى.',
          en: 'Could not open the camera or photos. Check permissions and try again.',
        );
      case 'id_number_not_found':
        return AppStrings.tr(
          context,
          ar: 'تم تصوير البطاقة، لكن لم نتمكن من استخراج الرقم القومي. أعد التصوير بإضاءة جيدة أو أدخله يدويًا.',
          en: 'The card was captured, but the national ID could not be extracted. Retake it in good lighting or enter it manually.',
        );
      case 'id_number_read':
        return AppStrings.tr(
          context,
          ar: 'استخرجنا الرقم القومي والبيانات المرتبطة به. راجعها قبل المتابعة.',
          en: 'The national ID and its related details were extracted. Review them before continuing.',
        );
      case 'ocr_not_configured':
        return AppStrings.tr(
          context,
          ar: 'خدمة قراءة البطاقة غير مُعدّة. راجع إعداد المفتاح في Supabase.',
          en: 'Card reading is not configured. Check the Supabase secret.',
        );
      case 'ocr_sign_in_required':
        return AppStrings.tr(
          context,
          ar: 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى ثم أعد المحاولة.',
          en: 'Your sign-in session expired. Sign in again and retry.',
        );
      case 'ocr_google_permission_denied':
        return AppStrings.tr(
          context,
          ar: 'Google رفض الطلب. تأكد من ربط مشروع On The Road بحساب التجربة وتفعيل Cloud Vision API.',
          en: 'Google rejected the request. Link the On The Road project to the trial billing account and confirm Cloud Vision API is enabled.',
        );
      default:
        return AppStrings.tr(
          context,
          ar: 'تعذر الاتصال بخدمة قراءة البطاقة. أدخل البيانات يدويًا أو حاول لاحقًا.',
          en: 'Could not reach the card-reading service. Enter the details manually or try again later.',
        );
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
    if (_hasSavedDetails && !_isEditing) {
      setState(() => _isEditing = true);
      return;
    }
    final nationalId = EgyptianIdOcr.normalizeDigits(_idController.text.trim());
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
    final idBirthDate = _birthDateFromNationalId(nationalId);
    if (idBirthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.tr(
              context,
              ar: 'الرقم القومي أو تاريخ الميلاد الموجود داخله غير صحيح. راجع الرقم يدويًا.',
              en: 'The national ID or its embedded birth date is invalid. Check the number manually.',
            ),
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
    if (dateOfBirth.year != idBirthDate.year ||
        dateOfBirth.month != idBirthDate.month ||
        dateOfBirth.day != idBirthDate.day) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.tr(
              context,
              ar: 'تاريخ الميلاد لا يطابق الرقم القومي. راجع البيانات.',
              en: 'The date of birth does not match the national ID. Check both values.',
            ),
          ),
        ),
      );
      return;
    }
    if (_cityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل المحافظة أو المدينة.')),
      );
      return;
    }
    if (_idFrontPhoto == null &&
        !_savedDocumentUrls.containsKey('national_id_front')) {
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
        'idFrontPath': _idFrontPhoto?.path,
        'documentPaths': {
          for (final entry in _editedDocuments.entries)
            entry.key: entry.value.path,
          if (_idFrontPhoto != null) 'national_id_front': _idFrontPhoto!.path,
        },
        'gender': _selectedGender,
        'city': _cityController.text.trim(),
      },
    );
  }

  Widget _documentPreview(String title, Widget image, {VoidCallback? onEdit}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 280,
                      height: 170,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      padding: const EdgeInsets.all(4),
                      child: image,
                    ),
                  ),
                  if (onEdit != null)
                    Material(
                      color: const Color(0xFFF59E0B),
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onEdit,
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _savedDocumentPreview(BuildContext context) {
    const documentTypes = <String, (String, bool)>{
      'national_id_front': ('بطاقة الرقم القومي - الأمام', true),
      'national_id_back': ('بطاقة الرقم القومي - الخلف', true),
      'driver_license_front': ('رخصة القيادة - الأمام', false),
      'driver_license_back': ('رخصة القيادة - الخلف', false),
    };
    final previews = documentTypes.entries
        .where(
          (entry) =>
              (entry.value.$2 || widget.role == 'driver') &&
              _savedDocumentUrls.containsKey(entry.key),
        )
        .map((entry) {
          final edited = _editedDocuments[entry.key];
          final photo =
              entry.key == 'national_id_front' && _idFrontPhoto != null
              ? _idFrontPhoto
              : edited;
          final image = photo != null
              ? Image.file(File(photo.path), fit: BoxFit.contain)
              : Image.network(
                  _savedDocumentUrls[entry.key]!,
                  fit: BoxFit.contain,
                );
          return _documentPreview(
            AppStrings.tr(
              context,
              ar: entry.value.$1,
              en: switch (entry.key) {
                'national_id_front' => 'National ID - front',
                'national_id_back' => 'National ID - back',
                'driver_license_front' => 'Driving license - front',
                _ => 'Driving license - back',
              },
            ),
            image,
            onEdit: _isEditing ? () => _editSavedDocument(entry.key) : null,
          );
        })
        .toList();
    if (previews.isEmpty) return const SizedBox.shrink();
    return Column(children: previews);
  }

  Future<void> _editSavedDocument(String documentType) async {
    if (documentType == 'national_id_front') {
      await _scanIdFront();
      return;
    }
    final title = switch (documentType) {
      'national_id_back' => AppStrings.tr(
        context,
        ar: 'مسح خلف البطاقة',
        en: 'Scan ID card back',
      ),
      'driver_license_front' => AppStrings.tr(
        context,
        ar: 'مسح وجه الرخصة الأمامي',
        en: 'Scan license front',
      ),
      _ => AppStrings.tr(
        context,
        ar: 'مسح وجه الرخصة الخلفي',
        en: 'Scan license back',
      ),
    };
    try {
      final scanned = await Navigator.of(context).push<XFile>(
        MaterialPageRoute(builder: (_) => InAppCameraScreen(title: title)),
      );
      if (scanned != null && mounted) {
        setState(() => _editedDocuments[documentType] = scanned);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.tr(
                context,
                ar: 'تعذر مسح المستند. حاول مرة أخرى.',
                en: 'Could not scan the document. Try again.',
              ),
            ),
          ),
        );
      }
    }
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
      body: _loadingSavedDetails
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
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

                    _savedDocumentPreview(context),
                    if (_idFrontPhoto != null &&
                        !_savedDocumentUrls.containsKey(
                          'national_id_front',
                        )) ...[
                      const SizedBox(height: 12),
                      _documentPreview(
                        AppStrings.idFront(context),
                        Image.file(
                          File(_idFrontPhoto!.path),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                    if (_isEditing &&
                        !_savedDocumentUrls.containsKey(
                          'national_id_front',
                        )) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _readingId ? null : _scanIdFront,
                        icon: const Icon(Icons.photo_camera_back_outlined),
                        label: Text(
                          AppStrings.tr(
                            context,
                            ar: _idFrontPhoto == null
                                ? 'اختر صورة البطاقة أو التقطها'
                                : 'تغيير صورة البطاقة',
                            en: _idFrontPhoto == null
                                ? 'Choose or capture ID front'
                                : 'Change ID photo',
                          ),
                        ),
                      ),
                    ],
                    if (_readingId) const LinearProgressIndicator(),
                    if (_ocrMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _ocrFeedback(context, _ocrMessage!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _ocrMessage == 'id_number_read'
                                ? const Color(0xFF10B981)
                                : _ocrMessage ==
                                      'manual_entry_without_cloud_ocr'
                                ? theme.hintColor
                                : theme.colorScheme.error,
                          ),
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
                      readOnly: !_isEditing,
                      keyboardType: TextInputType.number,
                      maxLength: 14,
                      textDirection: TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: '2980101XXXXXXXXX',
                        prefixIcon: Icon(Icons.badge_outlined),
                        counterText: '',
                      ),
                    ),
                    if (_ocrNationalId != null &&
                        EgyptianIdOcr.normalizeDigits(
                              _idController.text.trim(),
                            ) !=
                            _ocrNationalId)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          AppStrings.tr(
                            context,
                            ar: 'قراءة البطاقة مختلفة عن الرقم الحالي. راجعه من البطاقة ويمكنك تصحيحه يدويًا.',
                            en: 'The detected number differs from the current value. Check the card and correct it manually if needed.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFF59E0B),
                          ),
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
                      onTap: !_isEditing
                          ? null
                          : () async {
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
                                  ? const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.15)
                                  : Colors.transparent,
                              side: BorderSide(
                                color: _selectedGender == 'male'
                                    ? const Color(0xFFF59E0B)
                                    : theme.dividerColor.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                            ),
                            onPressed: !_isEditing
                                ? null
                                : () =>
                                      setState(() => _selectedGender = 'male'),
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
                                  ? const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.15)
                                  : Colors.transparent,
                              side: BorderSide(
                                color: _selectedGender == 'female'
                                    ? const Color(0xFFF59E0B)
                                    : theme.dividerColor.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                            ),
                            onPressed: !_isEditing
                                ? null
                                : () => setState(
                                    () => _selectedGender = 'female',
                                  ),
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
                      readOnly: !_isEditing,
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
                      child: Text(
                        !_hasSavedDetails
                            ? AppStrings.saveAndContinue(context)
                            : _isEditing
                            ? AppStrings.tr(
                                context,
                                ar: 'إرسال للمراجعة',
                                en: 'Submit for review',
                              )
                            : AppStrings.tr(context, ar: 'تعديل', en: 'Edit'),
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
