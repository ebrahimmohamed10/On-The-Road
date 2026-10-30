import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../services/auth_service.dart';
import '../services/egyptian_phone_number.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = normalizeEgyptianPhoneNumber(_phoneController.text);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.tr(
              context,
              ar: 'أدخل رقم هاتف مصري صحيحًا مثل 01111915092.',
              en: 'Enter a valid Egyptian mobile number, such as 01111915092.',
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      await ref
          .read(authServiceProvider)
          .requestPhoneOtp(phone: phone, createUser: false);
      if (!mounted) return;
      context.go('/auth/otp', extra: {'phone': phone, 'registration': false});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.tr(
              context,
              ar: 'تعذر إرسال رمز التحقق. تحقق من الرقم وإعدادات Supabase ثم حاول مجددًا.',
              en: 'Could not send the verification code. Check the phone number and Supabase setup, then try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/welcome');
            }
          },
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                // شعار التطبيق الحقيقي
                Center(
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // العنوان الرئيسي والترحيب
                Text(
                  AppStrings.welcomeBack(context),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.loginSubtitle(context),
                  style: theme.textTheme.bodyMedium,
                ),

                const SizedBox(height: 36),

                // حقل رقم الهاتف مع بادئة الدولة (+20)
                Text(
                  AppStrings.phoneNumber(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),

                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // علم مصر ومفتاح +20
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            const Text('🇪🇬', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Text(
                              '+20',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: theme.dividerColor.withValues(alpha: 0.2),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return AppStrings.tr(
                                context,
                                ar: 'يرجى إدخال رقم الهاتف',
                                en: 'Please enter phone number',
                              );
                            }
                            if (normalizeEgyptianPhoneNumber(value) == null) {
                              return AppStrings.tr(
                                context,
                                ar: 'رقم الهاتف غير صحيح',
                                en: 'Invalid phone number',
                              );
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: AppStrings.phoneHint(context),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // زر تسجيل الدخول
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(AppStrings.loginButton(context)),
                ),

                const SizedBox(height: 32),

                // رابط إنشاء حساب جديد
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppStrings.dontHaveAccount(context),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => context.go('/auth/register'),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          AppStrings.createAccount(context),
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
