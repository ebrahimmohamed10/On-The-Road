import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../services/auth_service.dart';
import '../services/egyptian_phone_number.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  int _selectedRoleIndex = 0; // 0 = Passenger, 1 = Driver
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final name = _nameController.text.trim();
    final phone = normalizeEgyptianPhoneNumber(_phoneController.text);
    if (name.isEmpty) {
      _showError(
        AppStrings.tr(
          context,
          ar: 'أدخل الاسم الكامل.',
          en: 'Enter your full name.',
        ),
      );
      return;
    }
    if (phone == null) {
      _showError(
        AppStrings.tr(
          context,
          ar: 'أدخل رقم هاتف مصري صحيحًا مثل 01111915092.',
          en: 'Enter a valid Egyptian mobile number, such as 01111915092.',
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final role = _selectedRoleIndex == 1 ? 'driver' : 'passenger';
      await ref
          .read(authServiceProvider)
          .requestPhoneOtp(
            phone: phone,
            createUser: true,
            fullName: name,
            role: role,
          );
      if (!mounted) return;
      context.go(
        '/auth/otp',
        extra: {
          'phone': phone,
          'registration': true,
          'name': name,
          'role': role,
        },
      );
    } catch (error) {
      final diagnostic = error.toString().replaceAll(phone, '[phone]');
      debugPrint('Phone OTP request failed: $diagnostic');
      if (mounted) {
        final message = AppStrings.tr(
          context,
          ar: 'تعذر إرسال رمز التحقق. تحقق من الرقم وإعدادات Supabase ثم حاول مجددًا.',
          en: 'Could not send the verification code. Check the phone number and Supabase setup, then try again.',
        );
        _showError(kDebugMode ? '$message\n$diagnostic' : message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.go('/auth/login'),
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
                AppStrings.createYourAccount(context),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.selectRoleSubtitle(context),
                style: theme.textTheme.bodyMedium,
              ),

              const SizedBox(height: 28),

              // محدد نوع الحساب: راكب (Passenger) / سائق (Driver)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedRoleIndex = 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedRoleIndex == 0
                                ? const Color(0xFFF59E0B)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 18,
                                color: _selectedRoleIndex == 0
                                    ? Colors.white
                                    : theme.textTheme.bodyMedium?.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppStrings.passenger(context),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _selectedRoleIndex == 0
                                      ? Colors.white
                                      : theme.textTheme.bodyMedium?.color,
                                  fontFamily:
                                      theme.textTheme.bodyMedium?.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedRoleIndex = 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedRoleIndex == 1
                                ? const Color(0xFFF59E0B)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.directions_car_rounded,
                                size: 18,
                                color: _selectedRoleIndex == 1
                                    ? Colors.white
                                    : theme.textTheme.bodyMedium?.color,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppStrings.driver(context),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _selectedRoleIndex == 1
                                      ? Colors.white
                                      : theme.textTheme.bodyMedium?.color,
                                  fontFamily:
                                      theme.textTheme.bodyMedium?.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // حقل الاسم بالكامل
              Text(
                AppStrings.fullName(context),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: AppStrings.tr(
                    context,
                    ar: 'أحمد محمد',
                    en: 'Ahmed Mohamed',
                  ),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),

              const SizedBox(height: 24),

              // حقل رقم الهاتف
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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: const BorderRadiusDirectional.horizontal(
                          start: Radius.circular(14),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text('🇪🇬', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
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
                      height: 30,
                      color: theme.dividerColor.withValues(alpha: 0.2),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          hintText: AppStrings.phoneHint(context),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
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

              const SizedBox(height: 36),

              // زر متابعة
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

              const SizedBox(height: 32),

              // لديك حساب بالفعل؟ تسجيل الدخول
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text(
                      AppStrings.alreadyHaveAccount(context),
                      style: theme.textTheme.bodyMedium,
                    ),
                    GestureDetector(
                      onTap: () => context.go('/auth/login'),
                      child: Text(
                        AppStrings.loginButton(context),
                        style: TextStyle(
                          color: const Color(0xFFF59E0B),
                          fontWeight: FontWeight.bold,
                          fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
