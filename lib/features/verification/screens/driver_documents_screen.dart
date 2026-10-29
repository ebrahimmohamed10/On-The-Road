import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class DriverDocumentsScreen extends ConsumerStatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  ConsumerState<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends ConsumerState<DriverDocumentsScreen> {
  bool _uploadedFront = false;
  bool _uploadedBack = false;
  bool _uploadedLicense = false;
  bool _isLoading = false;

  void _submit() {
    setState(() => _isLoading = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _isLoading = false);
      context.go('/verification/submitted');
    });
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
                isUploaded ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                color: isUploaded ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
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
                        ? AppStrings.tr(context, ar: 'تم الإرفاق بنجاح', en: 'Uploaded successfully')
                        : AppStrings.tapToUpload(context),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isUploaded ? const Color(0xFF10B981) : theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isUploaded ? Icons.done_all_rounded : Icons.add_circle_outline_rounded,
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
                AppStrings.driverDocs(context),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.driverDocsSub(context),
                style: theme.textTheme.bodyMedium,
              ),

              const SizedBox(height: 32),

              _buildUploadCard(
                title: AppStrings.idFront(context),
                isUploaded: _uploadedFront,
                onTap: () => setState(() => _uploadedFront = !_uploadedFront),
              ),

              const SizedBox(height: 16),

              _buildUploadCard(
                title: AppStrings.idBack(context),
                isUploaded: _uploadedBack,
                onTap: () => setState(() => _uploadedBack = !_uploadedBack),
              ),

              const SizedBox(height: 16),

              _buildUploadCard(
                title: AppStrings.drivingLicense(context),
                isUploaded: _uploadedLicense,
                onTap: () => setState(() => _uploadedLicense = !_uploadedLicense),
              ),

              const SizedBox(height: 48),

              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(AppStrings.submitDocs(context)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

