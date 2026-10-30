import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../services/auth_service.dart';
import '../services/egyptian_phone_number.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final bool registration;
  final String? name;
  final String? role;

  const OtpScreen({
    super.key,
    required this.phone,
    this.registration = false,
    this.name,
    this.role,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (_isLoading) return;
    final code = normalizeNumeralDigits(_controllers.map((c) => c.text).join());
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authServiceProvider)
          .verifyPhoneOtp(
            phone: widget.phone,
            token: code,
            registration: widget.registration,
          );
      if (!mounted) return;
      context.go('/passenger/home');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.tr(
                context,
                ar: 'تعذر التحقق من الرمز. تأكد من صحته وصلاحيته واتصالك، ثم حاول مجددًا.',
                en: 'Could not verify the code. Check that it is correct and unexpired, then try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authServiceProvider)
          .requestPhoneOtp(
            phone: widget.phone,
            createUser: widget.registration,
            fullName: widget.name,
            role: widget.role,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.tr(
              context,
              ar: 'تم إرسال رمز تحقق جديد.',
              en: 'A new verification code was sent.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.tr(
                context,
                ar: 'تعذر إعادة إرسال الرمز. تحقق من إعدادات Supabase وحاول مجددًا.',
                en: 'Could not resend the code. Check Supabase setup and try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.enterOtp(context),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.otpSentTo(context, widget.phone),
                style: theme.textTheme.bodyMedium,
              ),

              const SizedBox(height: 40),

              // 6 مربعات لإدخال كود التحقق — مطابقة للـ Figma
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return SizedBox(
                      width: 48,
                      height: 56,
                      child: TextFormField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.dividerColor.withValues(alpha: 0.2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFF59E0B),
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          if (val.isNotEmpty && index < 5) {
                            _focusNodes[index + 1].requestFocus();
                          } else if (val.isEmpty && index > 0) {
                            _focusNodes[index - 1].requestFocus();
                          }
                          if (index == 5 && val.isNotEmpty) {
                            _verifyOtp();
                          }
                        },
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 40),

              // زر تأكيد كحلي غامق (Dark Navy) كما في تصميم الـ Figma
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isLoading ? null : _verifyOtp,
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        AppStrings.verifyBtn(context),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),

              const SizedBox(height: 24),

              // إعادة إرسال الرمز
              Center(
                child: TextButton(
                  onPressed: _isLoading ? null : _resendCode,
                  child: Text(
                    AppStrings.resendCode(context),
                    style: TextStyle(
                      color: const Color(0xFFF59E0B),
                      fontWeight: FontWeight.bold,
                      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
