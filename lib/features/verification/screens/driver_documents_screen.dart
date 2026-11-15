import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    if (resolvedIdFront != null) _idFront = XFile(resolvedIdFront);
    if (docs['national_id_back'] case final path?) _idBack = XFile(path);
    if (docs['driver_license_front'] case final path?) {
      _licenseFront = XFile(path);
    }
    if (docs['driver_license_back'] case final path?) {
      _licenseBack = XFile(path);
    }
  }

  Future<void> _capture(
    void Function(XFile) save,
    String title, {
    bool readId = false,
  }) async {
    if (!mounted) return;
    final image = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(builder: (_) => InAppCameraScreen(title: title)),
    );
    if (image == null || !mounted) return;
    try {
      if (image.path.isEmpty) throw StateError('scanner returned no image');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر فتح الصورة أو تعديلها. تحقق من الأذونات ثم حاول مجددًا.\n$error',
            ),
          ),
        );
      }
      return;
    }
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
    if (_idFront == null ||
        _idBack == null ||
        widget.faceFrontPath == null ||
        widget.faceRightPath == null ||
        widget.faceLeftPath == null ||
        widget.poseChallengeCompletedAt == null ||
        (widget.role == 'driver' &&
            (_licenseFront == null ||
                _licenseBack == null ||
                _vehicleFront == null ||
                _vehicleRight == null ||
                _vehicleLeft == null))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'التقط صور البطاقة وزوايا الوجه الثلاثة، وصور وجهي الرخصة وجوانب السيارة الثلاثة للسائق.',
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
            idFront: _idFront!,
            idBack: _idBack!,
            faceFront: XFile(widget.faceFrontPath!),
            faceRight: XFile(widget.faceRightPath!),
            faceLeft: XFile(widget.faceLeftPath!),
            poseChallengeCompletedAt: widget.poseChallengeCompletedAt!,
            licenseFront: _licenseFront,
            licenseBack: _licenseBack,
            vehicleFront: _vehicleFront,
            vehicleRight: _vehicleRight,
            vehicleLeft: _vehicleLeft,
          );
      if (mounted) context.go('/verification/submitted');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر رفع المستندات. حاول مرة أخرى.\n$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildUploadCard({
    required String title,
    required bool isUploaded,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

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
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isUploaded
                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isUploaded
                    ? Icons.check_circle_rounded
                    : Icons.upload_file_rounded,
                color: isUploaded
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
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
                        ? AppStrings.tr(
                            context,
                            ar: 'تم الإرفاق بنجاح',
                            en: 'Uploaded successfully',
                          )
                        : AppStrings.tapToUpload(context),
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
                  ? Icons.done_all_rounded
                  : Icons.add_circle_outline_rounded,
              color: isUploaded ? const Color(0xFF10B981) : theme.hintColor,
            ),
          ],
        ),
      ),
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
                        ar: 'ارفع صورًا واضحة لوجهي بطاقة الرقم القومي.',
                        en: 'Capture clear images of both sides of your national ID.',
                      ),
                style: theme.textTheme.bodyMedium,
              ),

              const SizedBox(height: 32),

              _buildUploadCard(
                title: AppStrings.idFront(context),
                isUploaded: _idFront != null,
                onTap: () => _capture(
                  (image) => _idFront = image,
                  AppStrings.idFront(context),
                  readId: true,
                ),
              ),

              if (_ocrLoading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  AppStrings.tr(
                    context,
                    ar: 'جارٍ قراءة البطاقة على الجهاز…',
                    en: 'Reading the ID on this device…',
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
                    ar: 'تعذرت قراءة البطاقة. أعد التصوير بإضاءة جيدة.',
                    en: 'Could not read the ID. Retake it in good lighting.',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],

              const SizedBox(height: 16),

              _buildUploadCard(
                title: AppStrings.idBack(context),
                isUploaded: _idBack != null,
                onTap: () => _capture(
                  (image) => _idBack = image,
                  AppStrings.idBack(context),
                ),
              ),

              const SizedBox(height: 16),

              if (widget.role == 'driver') ...[
                _buildUploadCard(
                  title: AppStrings.tr(
                    context,
                    ar: 'الوجه الأمامي للرخصة',
                    en: 'License front',
                  ),
                  isUploaded: _licenseFront != null,
                  onTap: () => _capture(
                    (image) => _licenseFront = image,
                    AppStrings.drivingLicense(context),
                  ),
                ),
                const SizedBox(height: 16),
                _buildUploadCard(
                  title: AppStrings.tr(
                    context,
                    ar: 'الوجه الخلفي للرخصة',
                    en: 'License back',
                  ),
                  isUploaded: _licenseBack != null,
                  onTap: () => _capture(
                    (image) => _licenseBack = image,
                    AppStrings.drivingLicense(context),
                  ),
                ),
                const SizedBox(height: 16),
                _buildUploadCard(
                  title: AppStrings.tr(
                    context,
                    ar: 'صورة السيارة من الأمام',
                    en: 'Vehicle front',
                  ),
                  isUploaded: _vehicleFront != null,
                  onTap: () => _capture(
                    (image) => _vehicleFront = image,
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
                  isUploaded: _vehicleRight != null,
                  onTap: () => _capture(
                    (image) => _vehicleRight = image,
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
                  isUploaded: _vehicleLeft != null,
                  onTap: () => _capture(
                    (image) => _vehicleLeft = image,
                    AppStrings.tr(
                      context,
                      ar: 'الجانب الأيسر للسيارة',
                      en: 'Vehicle left side',
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 48),

              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(AppStrings.submitDocs(context)),
              ),
              const SizedBox(height: 20),
            ],
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.nationalId == null
                ? AppStrings.tr(
                    context,
                    ar: 'لم أتعرف على رقم قومي كامل؛ أعد تصوير البطاقة بوضوح.',
                    en: 'No complete national ID number found. Retake the card clearly.',
                  )
                : AppStrings.tr(
                    context,
                    ar: matches
                        ? 'تم استخراج الرقم القومي ومطابقته مع الرقم المدخل.'
                        : 'الرقم المقروء لا يطابق الرقم المدخل؛ راجع الرقم أو أعد التصوير.',
                    en: matches
                        ? 'National ID extracted and matches the entered number.'
                        : 'The detected number does not match. Check the entered number or retake the card.',
                  ),
            style: TextStyle(
              color: result.nationalId != null && !matches
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          if (result.rawText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              AppStrings.tr(
                context,
                ar: 'النص المقروء (راجعه بنفسك):',
                en: 'Recognized text (please review):',
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              result.rawText,
              textDirection: TextDirection.rtl,
              maxLines: 8,
            ),
          ],
        ],
      ),
    );
  }
}
