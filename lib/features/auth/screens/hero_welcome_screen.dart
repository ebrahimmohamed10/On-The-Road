import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class HeroWelcomeScreen extends ConsumerWidget {
  const HeroWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. صورة الخلفية (المسار والغروب بين الجبال)
          Image.asset(
            'assets/images/welcome_bg.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),

          // 2. تدرج الظلال السينمائي المتطابق مع Figma
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0A0F1D).withValues(alpha: 0.90),
                  const Color(0xFF0A0F1D).withValues(alpha: 0.35),
                  Colors.transparent,
                  const Color(0xFF0A0F1D).withValues(alpha: 0.70),
                  const Color(0xFF0A0F1D).withValues(alpha: 0.96),
                ],
                stops: const [0.0, 0.22, 0.45, 0.70, 1.0],
              ),
            ),
          ),

          // 3. المحتوى
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                children: [
                  // شريط علوي خفيف لزر اللغات والثيم
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      LanguageThemeActions(),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // الشعار الرسمي + ON THE ROAD + رحلتك أسهل معانا
                  Center(
                    child: Column(
                      children: [
                        SizedBox(
                          width: 82,
                          height: 82,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'ON THE ROAD',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            letterSpacing: 2.5,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppStrings.welcomeHeaderSub(context),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // خط التمييز الأفقي الصغير كما في Figma
                        Container(
                          width: 50,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // النصوص السفلية (كل رحلة، تبدأ من هنا)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.heroTagline(context),
                          style: theme.textTheme.displayLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.22,
                            fontSize: 34,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.8),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          AppStrings.heroSubtitle(context),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // زر "ابدأ الآن ➔" البرتقالي المطابق تماماً لـ Figma
                  InkWell(
                    onTap: () => context.go('/auth/register'),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      height: 56,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFA000),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFA000).withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          const Spacer(),
                          Text(
                            AppStrings.getStarted(context),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF0F172A),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // الرابط السفلي: لديك حساب بالفعل؟ سجل الدخول
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppStrings.alreadyHaveAccount(context),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => context.go('/auth/login'),
                          child: Text(
                            AppStrings.loginButton(context),
                            style: const TextStyle(
                              color: Color(0xFFFFA000),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
