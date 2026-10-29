import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class IdentityVerificationScreen extends ConsumerStatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  ConsumerState<IdentityVerificationScreen> createState() => _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState extends ConsumerState<IdentityVerificationScreen> {
  bool _photoTaken = false;
  bool _isLoading = false;

  void _onCapture() {
    setState(() => _photoTaken = true);
  }

  void _onContinue() {
    setState(() => _isLoading = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _isLoading = false);
      context.push('/verification/driver-docs');
    });
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  AppStrings.verifyIdentity(context),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  AppStrings.selfieInstruction(context),
                  style: theme.textTheme.bodyMedium,
                ),
              ),

              const Spacer(),

              // إطار كاميرا السيلفي — مطابق لتصميم الـ Figma
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 250,
                    height: 310,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _photoTaken
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_photoTaken
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.15),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _photoTaken
                              ? Icons.check_circle_rounded
                              : Icons.face_retouching_natural_rounded,
                          size: 110,
                          color: _photoTaken
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _photoTaken
                              ? AppStrings.tr(context, ar: 'تم التقاط الصورة بنجاح', en: 'Selfie captured')
                              : AppStrings.tr(context, ar: 'ضع وجهك هنا', en: 'Fit face here'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _photoTaken
                                ? const Color(0xFF10B981)
                                : theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // زوايا التأطير (Corner Guides)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFF59E0B), width: 3),
                          left: BorderSide(color: Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFF59E0B), width: 3),
                          right: BorderSide(color: Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFF59E0B), width: 3),
                          left: BorderSide(color: Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFF59E0B), width: 3),
                          right: BorderSide(color: Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // أزرار التحكم
              if (!_photoTaken)
                ElevatedButton.icon(
                  onPressed: _onCapture,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(AppStrings.takePhoto(context)),
                )
              else
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _isLoading ? null : _onContinue,
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(AppStrings.continueBtn(context)),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() => _photoTaken = false),
                      child: Text(
                        AppStrings.retake(context),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

