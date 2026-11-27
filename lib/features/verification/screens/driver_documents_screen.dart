import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import 'in_app_camera_screen.dart';
import '../services/verification_service.dart';
import '../services/egyptian_id_ocr.dart';

class DriverDocumentsScreen extends ConsumerStatefulWidget {
  const DriverDocumentsScreen({
    super.key,
    required this.role,
    required this.nationalId,
    required this.dateOfBirth,
    required this.gender,
    required this.city,
    required this.faceFrontPath,
    required this.faceRightPath,
    required this.faceLeftPath,
    required this.poseChallengeCompletedAt,
    required this.idFrontPath,
    this.documentPaths = const {},
  });
  final String role;
  final String nationalId;
  final String dateOfBirth;
  final String gender;
  final String city;
  final String? faceFrontPath;
  final String? faceRightPath;
  final String? faceLeftPath;
  final DateTime? poseChallengeCompletedAt;
  final String? idFrontPath;
  final Map<String, String> documentPaths;

  @override
  ConsumerState<DriverDocumentsScreen> createState() =>
      _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends ConsumerState<DriverDocumentsScreen> {
  XFile? _idFront;
  XFile? _idBack;
  XFile? _licenseFront;
  XFile? _licenseBack;
  XFile? _vehicleFront;
  XFile? _vehicleRight;
  XFile? _vehicleLeft;
  XFile? _vehicleRear;
  XFile? _vehicleLicenseFront;
  XFile? _vehicleLicenseBack;
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController();
  final _seatsController = TextEditingController(text: '4');
  final Map<String, String> _savedPaths = {};
  final Map<String, String> _signedUrls = {};
  bool _reuseIdentity = false;
  bool _hasSavedFace = false;
  bool _isLoading = false;
  bool _ocrLoading = false;
  EgyptianIdOcrResult? _ocrResult;
  String? _ocrError;

  @override
  void initState() {
    super.initState();
    final idFrontPath = widget.idFrontPath;
    final docs = widget.documentPaths;
    final resolvedIdFront = idFrontPath ?? docs['national_id_front'];
    _savedPaths.addAll(docs);
    if (resolvedIdFront != null && File(resolvedIdFront).existsSync()) {
      _idFront = XFile(resolvedIdFront);
    }
    final idBackPath = docs['national_id_back'];
    if (idBackPath != null && File(idBackPath).existsSync())
      _idBack = XFile(idBackPath);
    final licenseFrontPath = docs['driver_license_front'];
    if (licenseFrontPath != null && File(licenseFrontPath).existsSync()) {
      _licenseFront = XFile(licenseFrontPath);
    }
    final licenseBackPath = docs['driver_license_back'];
    if (licenseBackPath != null && File(licenseBackPath).existsSync()) {
      _licenseBack = XFile(licenseBackPath);
    }
    if (widget.poseChallengeCompletedAt != null &&
        widget.faceFrontPath != null &&
        File(widget.faceFrontPath!).existsSync()) {
      _savedPaths['face_scan_front'] = widget.faceFrontPath!;
      _savedPaths['face_scan_right'] = widget.faceRightPath!;
      _savedPaths['face_scan_left'] = widget.faceLeftPath!;
    } else {
      if (widget.faceFrontPath != null)
        _savedPaths['face_scan_front'] = widget.faceFrontPath!;
      if (widget.faceRightPath != null)
        _savedPaths['face_scan_right'] = widget.faceRightPath!;
      if (widget.faceLeftPath != null)
        _savedPaths['face_scan_left'] = widget.faceLeftPath!;
    }
    _hasSavedFace =
        _savedPaths['face_scan_front'] != null &&
        _savedPaths['face_scan_right'] != null &&
        _savedPaths['face_scan_left'] != null;
    _reuseIdentity =
        (resolvedIdFront != null || docs['national_id_front'] != null) &&
        docs['national_id_back'] != null &&
        _hasSavedFace &&
        _idFront == null &&
        _idBack == null;
    _loadSavedPreviews();
  }

  Future<void> _loadSavedPreviews() async {
    for (final entry in _savedPaths.entries) {
      if (File(entry.value).existsSync()) continue;
      final bucket = entry.key.startsWith('vehicle_license_')
          ? 'vehicle-documents'
          : 'identity-documents';
      try {
        final url = await Supabase.instance.client.storage
            .from(bucket)
            .createSignedUrl(entry.value, 3600);
        if (mounted) setState(() => _signedUrls[entry.key] = url);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _plateController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  Future<void> _capture(
    void Function(XFile) save,
    String title, {
    bool readId = false,
  }) async {
    if (!mounted) return;

    // Directly open the in-app camera (no gallery picker allowed)
    final image = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => InAppCameraScreen(title: title)),
    );

    if (image == null || !mounted) return;
    final selectedImage = image;
    setState(() {
      save(selectedImage);
      if (readId) {
        _ocrLoading = true;
        _ocrResult = null;
        _ocrError = null;
      }
    });
    if (readId) {
      try {
        final result = await EgyptianIdOcr.readFront(selectedImage.path);
        if (mounted) setState(() => _ocrResult = result);
      } catch (error) {
        if (mounted) setState(() => _ocrError = error.toString());
      } finally {
        if (mounted) setState(() => _ocrLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if ((_idFront == null &&
            _savedPaths['national_id_front'] == null &&
            widget.idFrontPath == null) ||
        (_idBack == null && _savedPaths['national_id_back'] == null) ||
        (!_hasSavedFace &&
            (widget.faceFrontPath == null ||
                widget.faceRightPath == null ||
                widget.faceLeftPath == null ||
                widget.poseChallengeCompletedAt == null)) ||
        (widget.role == 'driver' &&
            (_licenseFront == null ||
                (_licenseBack == null &&
                    _savedPaths['driver_license_back'] == null) ||
                (_vehicleFront == null &&
                    _savedPaths['vehicle_exterior_front'] == null) ||
                (_vehicleRight == null &&
                    _savedPaths['vehicle_exterior_right'] == null) ||
                (_vehicleLeft == null &&
                    _savedPaths['vehicle_exterior_left'] == null) ||
                (_vehicleRear == null &&
                    _savedPaths['vehicle_exterior_rear'] == null) ||
                _vehicleLicenseFront == null ||
                _vehicleLicenseBack == null ||
                _makeController.text.trim().isEmpty ||
                _modelController.text.trim().isEmpty ||
                _colorController.text.trim().isEmpty ||
                _plateController.text.trim().isEmpty ||
                int.tryParse(_seatsController.text) == null))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.role == 'driver'
                ? AppStrings.tr(
                    context,
                    ar: 'صوّر البطاقة ورخصة القيادة، والسيارة من الأمام والجانبين والخلف بالكاميرا.',
                    en: 'Capture the ID, driving license, and vehicle front, both sides, and rear.',
                  )
                : AppStrings.tr(
                    context,
                    ar: 'يرجى تصوير وجهي بطاقة الرقم القومي بالكاميرا.',
                    en: 'Please capture both sides of your national ID using the camera.',
                  ),
          ),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref
          .read(verificationServiceProvider)
          .submit(
            role: widget.role,
            nationalId: widget.nationalId,
            dateOfBirth: DateTime.parse(widget.dateOfBirth),
            gender: widget.gender,
            city: widget.city,
            idFront: _idFront,
            idBack: _idBack,
            faceFront:
                widget.poseChallengeCompletedAt != null &&
                    widget.faceFrontPath != null &&
                    File(widget.faceFrontPath!).existsSync()
                ? XFile(widget.faceFrontPath!)
                : null,
            faceRight:
                widget.poseChallengeCompletedAt != null &&
                    widget.faceRightPath != null &&
                    File(widget.faceRightPath!).existsSync()
                ? XFile(widget.faceRightPath!)
                : null,
            faceLeft:
                widget.poseChallengeCompletedAt != null &&
                    widget.faceLeftPath != null &&
                    File(widget.faceLeftPath!).existsSync()
                ? XFile(widget.faceLeftPath!)
                : null,
            poseChallengeCompletedAt: widget.poseChallengeCompletedAt,
            existingDocumentPaths: {
              ..._savedPaths,
              if (widget.idFrontPath != null)
                'national_id_front': widget.idFrontPath!,
            },
            licenseFront: _licenseFront,
            licenseBack: _licenseBack,
            vehicleFront: _vehicleFront,
            vehicleRight: _vehicleRight,
            vehicleLeft: _vehicleLeft,
            vehicleRear: _vehicleRear,
            vehicleLicenseFront: _vehicleLicenseFront,
            vehicleLicenseBack: _vehicleLicenseBack,
            vehicleMake: _makeController.text.trim(),
            vehicleModel: _modelController.text.trim(),
            vehicleColor: _colorController.text.trim(),
            vehiclePlate: _plateController.text.trim(),
            vehicleSeats: int.tryParse(_seatsController.text),
          );
      if (mounted) context.go('/verification/submitted');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.tr(
                context,
                ar: 'تعذر رفع المستندات: $error',
                en: 'Could not upload documents: $error',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildUploadCard({
    required String title,
    required XFile? file,
    required VoidCallback onTap,
    String? savedKey,
  }) {
    final theme = Theme.of(context);
    final remoteUrl = savedKey == null ? null : _signedUrls[savedKey];
    final isUploaded =
        file != null ||
        remoteUrl != null ||
        (savedKey != null && _savedPaths.containsKey(savedKey));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUploaded
                ? const Color(0xFF10B981)
                : theme.dividerColor.withValues(alpha: 0.15),
            width: isUploaded ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            if (isUploaded)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: file != null
                      ? Image.file(File(file.path), fit: BoxFit.cover)
                      : remoteUrl != null
                      ? Image.network(remoteUrl, fit: BoxFit.cover)
                      : const Icon(
                          Icons.check_circle,
                          color: Color(0xFF10B981),
                        ),
                ),
              )
            else
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  color: Color(0xFFF59E0B),
                  size: 28,
                ),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isUploaded
                        ? (savedKey != null &&
                                  _savedPaths.containsKey(savedKey) &&
                                  file == null
                              ? AppStrings.tr(
                                  context,
                                  ar: 'محفوظة من التحقق السابق',
                                  en: 'Reused from previous verification',
                                )
                              : AppStrings.tr(
                                  context,
                                  ar: 'تم التقاط الصورة بنجاح (انقر للإعادة)',
                                  en: 'Photo captured (tap to retake)',
                                ))
                        : AppStrings.tr(
                            context,
                            ar: 'انقر لفتح الكاميرا والتقاط الصورة',
                            en: 'Tap to open camera and take photo',
                          ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isUploaded
                          ? const Color(0xFF10B981)
                          : theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isUploaded
                  ? Icons.check_circle_rounded
                  : Icons.camera_alt_rounded,
              color: isUploaded ? const Color(0xFF10B981) : theme.hintColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehicleTextField(
    TextEditingController controller,
    String label, {
    bool numeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/passenger/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope<Object?>(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _handleBack,
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
                  widget.role == 'driver'
                      ? AppStrings.driverDocs(context)
                      : AppStrings.tr(
                          context,
                          ar: 'وثائق الهوية',
                          en: 'Identity documents',
                        ),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.role == 'driver'
                      ? AppStrings.driverDocsSub(context)
                      : AppStrings.tr(
                          context,
                          ar: 'التقط صورًا مباشرة وواضحة لوجهي بطاقة الرقم القومي.',
                          en: 'Capture clear live photos of both sides of your national ID.',
                        ),
                  style: theme.textTheme.bodyMedium,
                ),

                const SizedBox(height: 32),

                if (_reuseIdentity) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      AppStrings.tr(
                        context,
                        ar: 'تم استخدام البطاقة وصور الوجه المحفوظة من التحقق السابق. لن تحتاج لإعادة تصويرها.',
                        en: 'Your saved ID and face verification are reused. No need to capture them again.',
                      ),
                    ),
                  ),
                ] else ...[
                  _buildUploadCard(
                    title: AppStrings.idFront(context),
                    file: _idFront,
                    onTap: () => _capture(
                      (image) {
                        _idFront = image;
                        _savedPaths.remove('national_id_front');
                      },
                      AppStrings.idFront(context),
                      readId: true,
                    ),
                    savedKey: 'national_id_front',
                  ),
                ],

                if (_ocrLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.tr(
                      context,
                      ar: 'جارٍ قراءة بيانات البطاقة…',
                      en: 'Reading ID details…',
                    ),
                  ),
                ],
                if (_ocrResult != null) ...[
                  const SizedBox(height: 12),
                  _buildOcrResult(context),
                ],
                if (_ocrError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    AppStrings.tr(
                      context,
                      ar: 'تعذرت قراءة البطاقة تلقائيًا. تأكد من وضوح الصورة.',
                      en: 'Could not read ID automatically. Ensure photo is clear.',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                if (!_reuseIdentity)
                  _buildUploadCard(
                    title: AppStrings.idBack(context),
                    file: _idBack,
                    onTap: () => _capture((image) {
                      _idBack = image;
                      _savedPaths.remove('national_id_back');
                    }, AppStrings.idBack(context)),
                    savedKey: 'national_id_back',
                  ),

                const SizedBox(height: 16),

                if (widget.role == 'driver') ...[
                  _buildUploadCard(
                    title: AppStrings.tr(
                      context,
                      ar: 'الوجه الأمامي للرخصة',
                      en: 'License front',
                    ),
                    file: _licenseFront,
                    onTap: () => _capture((image) {
                      _licenseFront = image;
                      _savedPaths.remove('driver_license_front');
                    }, AppStrings.drivingLicense(context)),
                    savedKey: 'driver_license_front',
                  ),
                  const SizedBox(height: 16),
                  _buildUploadCard(
                    title: AppStrings.tr(
                      context,
                      ar: 'الوجه الخلفي للرخصة',
                      en: 'License back',
                    ),
                    file: _licenseBack,
                    onTap: () => _capture((image) {
                      _licenseBack = image;
                      _savedPaths.remove('driver_license_back');
                    }, AppStrings.drivingLicense(context)),
                    savedKey: 'driver_license_back',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.tr(
                      context,
                      ar: 'رخصة السيارة',
                      en: 'Vehicle registration',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildUploadCard(
                    title: AppStrings.tr(
                      context,
                      ar: 'الوجه الأمامي لرخصة السيارة',
                      en: 'Vehicle license front',
                    ),
                    file: _vehicleLicenseFront,
                    onTap: () => _capture(
                      (image) => _vehicleLicenseFront = image,
                      AppStrings.tr(
                        context,
                        ar: 'رخصة السيارة - أمامي',
                        en: 'Vehicle license front',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildUploadCard(
                    title: AppStrings.tr(
                      context,
                      ar: 'الوجه الخلفي لرخصة السيارة',
                      en: 'Vehicle license back',
                    ),
                    file: _vehicleLicenseBack,
                    onTap: () => _capture(
                      (image) => _vehicleLicenseBack = image,
                      AppStrings.tr(
                        context,
                        ar: 'رخصة السيارة - خلفي',
                        en: 'Vehicle license back',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    AppStrings.tr(
                      context,
                      ar: 'بيانات السيارة',
                      en: 'Vehicle details',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _vehicleTextField(
                    _makeController,
                    AppStrings.tr(context, ar: 'الماركة', en: 'Make'),
                  ),
                  _vehicleTextField(
                    _modelController,
                    AppStrings.tr(context, ar: 'الموديل', en: 'Model'),
                  ),
                  _vehicleTextField(
                    _colorController,
                    AppStrings.tr(context, ar: 'اللون', en: 'Color'),
                  ),
                  _vehicleTextField(
                    _plateController,
                    AppStrings.tr(
                      context,
                      ar: 'رقم اللوحة',
                      en: 'Plate number',
                    ),
                  ),
                  _vehicleTextField(
                    _seatsController,
                    AppStrings.tr(context, ar: 'عدد المقاعد', en: 'Seats'),
                    numeric: true,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.tr(
                      context,
                      ar: 'صور السيارة (4 جوانب)',
                      en: 'Vehicle photos (4 sides)',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildUploadCard(
                    title: AppStrings.tr(
                      context,
                      ar: 'صورة السيارة من الأمام',
                      en: 'Vehicle front',
                    ),
                    file: _vehicleFront,
                    savedKey: 'vehicle_exterior_front',
                    onTap: () => _capture(
                      (image) {
                        _vehicleFront = image;
                        _savedPaths.remove('vehicle_exterior_front');
                      },
                      AppStrings.tr(
                        context,
                        ar: 'صورة السيارة من الأمام',
                        en: 'Vehicle front',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildUploadCard(
                    title: AppStrings.tr(
                      context,
                      ar: 'الجانب الأيمن للسيارة',
                      en: 'Vehicle right side',
                    ),
                    file: _vehicleRight,
                    savedKey: 'vehicle_exterior_right',
                    onTap: () => _capture(
                      (image) {
                        _vehicleRight = image;
                        _savedPaths.remove('vehicle_exterior_right');
                      },
                      AppStrings.tr(
                        context,
                        ar: 'الجانب الأيمن للسيارة',
                        en: 'Vehicle right side',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildUploadCard(
                    title: AppStrings.tr(
                      context,
                      ar: 'الجانب الأيسر للسيارة',
                      en: 'Vehicle left side',
                    ),
                    file: _vehicleLeft,
                    savedKey: 'vehicle_exterior_left',
                    onTap: () => _capture(
                      (image) {
                        _vehicleLeft = image;
                        _savedPaths.remove('vehicle_exterior_left');
                      },
                      AppStrings.tr(
                        context,
                        ar: 'الجانب الأيسر للسيارة',
                        en: 'Vehicle left side',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildUploadCard(
                    title: AppStrings.tr(
                      context,
                      ar: 'الجانب الخلفي للسيارة',
                      en: 'Vehicle rear',
                    ),
                    file: _vehicleRear,
                    savedKey: 'vehicle_exterior_rear',
                    onTap: () => _capture(
                      (image) {
                        _vehicleRear = image;
                        _savedPaths.remove('vehicle_exterior_rear');
                      },
                      AppStrings.tr(
                        context,
                        ar: 'الجانب الخلفي للسيارة',
                        en: 'Vehicle rear',
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 48),

                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(AppStrings.submitDocs(context)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOcrResult(BuildContext context) {
    final result = _ocrResult!;
    final matches = result.nationalId == widget.nationalId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: matches ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                matches
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                color: matches
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.nationalId == null
                      ? AppStrings.tr(
                          context,
                          ar: 'لم أتعرف على رقم قومي كامل؛ أعد تصوير البطاقة بوضوح بالكاميرا.',
                          en: 'No complete national ID number found. Retake the card clearly with the camera.',
                        )
                      : AppStrings.tr(
                          context,
                          ar: matches
                              ? 'تم استخراج الرقم القومي ومطابقته بنجاح: ${result.nationalId}'
                              : 'الرقم المقروء (${result.nationalId}) يختلف عن الرقم المدخل (${widget.nationalId}).',
                          en: matches
                              ? 'National ID verified: ${result.nationalId}'
                              : 'Detected ID (${result.nationalId}) differs from entered ID (${widget.nationalId}).',
                        ),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: result.nationalId != null && !matches
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
