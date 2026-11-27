import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/locale_provider.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/notification_bell_button.dart';
import 'avatar_crop_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _imagePicker = ImagePicker();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverAvatarPick());
  }

  Future<void> _recoverAvatarPick() async {
    try {
      final lost = await _imagePicker.retrieveLostData();
      if (!mounted || lost.isEmpty) return;
      final file = lost.files?.firstOrNull;
      if (file == null) return;
      await _cropAndUploadAvatar(file);
    } catch (_) {
      // Recovery is best-effort; the profile remains usable if no image was lost.
    }
  }

  Future<void> _loadProfile() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile = await client
          .from('profiles')
          .select(
            'id,name,role,avatar_path,avatar_url,rating_avg,rating_count,trips_count,verification_status',
          )
          .eq('id', user.id)
          .single();
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.tr(
                context,
                ar: 'تعذر تحميل بيانات الملف الشخصي.',
                en: 'Could not load your profile.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeAvatar() async {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    if (_uploadingAvatar) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(isArabic ? 'اختيار من الجهاز' : 'Choose from device'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(isArabic ? 'التقاط بالكاميرا' : 'Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    XFile? image;
    try {
      image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'تعذر فتح الصور أو الكاميرا. تحقق من الأذونات.'
                  : 'Could not open photos or camera. Check permissions.',
            ),
          ),
        );
      }
      return;
    }
    if (image == null || !mounted) return;

    await _cropAndUploadAvatar(image, isArabic: isArabic);
  }

  Future<void> _cropAndUploadAvatar(XFile image, {bool? isArabic}) async {
    isArabic ??= Localizations.localeOf(context).languageCode == 'ar';
    try {
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => AvatarCropScreen(imageBytes: bytes)),
      );
      if (cropped != null && mounted) {
        await _uploadAvatarBytes(cropped, isArabic: isArabic);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic
                  ? 'تعذر فتح محرر الصورة.'
                  : 'Could not open the photo editor.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _uploadAvatarBytes(
    Uint8List bytes, {
    required bool isArabic,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    setState(() => _uploadingAvatar = true);
    String? uploadedPath;
    try {
      if (bytes.length > 5 * 1024 * 1024) {
        throw StateError('avatar_too_large');
      }
      final path =
          '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      uploadedPath = path;
      await client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/png'),
          );
      final publicUrl = client.storage.from('avatars').getPublicUrl(path);
      final oldPath = _profile?['avatar_path'] as String?;
      await client
          .from('profiles')
          .update({'avatar_path': path, 'avatar_url': publicUrl})
          .eq('id', user.id);
      if (oldPath != null && oldPath != path) {
        try {
          await client.storage.from('avatars').remove([oldPath]);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _profile = {
            ...?_profile,
            'avatar_path': path,
            'avatar_url': publicUrl,
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isArabic ? 'تم تحديث الصورة.' : 'Profile photo updated.',
            ),
          ),
        );
      }
    } catch (error) {
      if (uploadedPath != null) {
        try {
          await client.storage.from('avatars').remove([uploadedPath]);
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError && error.message == 'avatar_too_large'
                  ? (isArabic
                        ? 'حجم الصورة أكبر من الحد المسموح (5 ميجابايت).'
                        : 'The photo exceeds the 5 MB limit.')
                  : (isArabic
                        ? 'تعذر تحديث الصورة. حاول مرة أخرى.'
                        : 'Could not update the photo. Try again.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _showHelpSupportSheet(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.headset_mic_rounded,
                      color: Color(0xFFF59E0B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArabic
                            ? 'مركز الدعم والمساعدة'
                            : 'Help & Support Center',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        isArabic
                            ? 'فريق أون ذا رود في خدمتك على مدار الساعة'
                            : 'On The Road team is at your service 24/7',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).hintColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.phone_in_talk_rounded,
                    color: Color(0xFF10B981),
                  ),
                ),
                title: Text(
                  isArabic ? 'خدمة العملاء الهاتفية' : 'Customer Care Hotline',
                ),
                subtitle: const Text('19842 (24/7)'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isArabic
                            ? 'جاري الاتصال بخدمة العملاء 19842...'
                            : 'Calling hotline 19842...',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Color(0xFF25D366),
                  ),
                ),
                title: Text(
                  isArabic ? 'واتساب الدعم الفني' : 'WhatsApp Support',
                ),
                subtitle: const Text('+20 100 000 0000'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isArabic
                            ? 'تم فتح محادثة الدعم عبر واتساب'
                            : 'Opening WhatsApp support...',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.email_outlined,
                    color: Color(0xFF0F172A),
                  ),
                ),
                title: Text(isArabic ? 'البريد الإلكتروني' : 'Support Email'),
                subtitle: const Text('support@ontheroad.eg'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isArabic
                            ? 'يمكنك مراسلتنا على: support@ontheroad.eg'
                            : 'Email us at: support@ontheroad.eg',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestAccountDeletion(BuildContext context) async {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isArabic ? 'طلب حذف الحساب' : 'Request account deletion'),
        content: Text(
          isArabic ? 'سيُرسل طلبك للمراجعة. لن يُحذف الحساب فورًا.' : 'Your request will be submitted for review. Your account will not be deleted immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isArabic ? 'رجوع' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isArabic ? 'إرسال الطلب' : 'Submit request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await Supabase.instance.client.rpc('request_account_deletion');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تم إرسال طلب حذف الحساب للمراجعة.'
                : 'Your account deletion request was submitted for review.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تعذر إرسال الطلب. حاول مرة أخرى.'
                : 'Could not submit the request. Please try again.',
          ),
        ),
      );
    }
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
      ),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (iconColor ?? const Color(0xFFF59E0B)).withValues(
                alpha: 0.1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor ?? const Color(0xFFF59E0B),
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          trailing:
              trailing ??
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.hintColor.withValues(alpha: 0.5),
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = ref.watch(localeProvider).languageCode == 'ar';
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final profile = _profile;
    final user = Supabase.instance.client.auth.currentUser;
    final name = (profile?['name'] as String?)?.trim() ?? '';
    final phone = user?.phone ?? '';
    final role = profile?['role'] == 'driver' ? 'driver' : 'passenger';
    final isVerified = profile?['verification_status'] == 'approved';
    final ratingCount = (profile?['rating_count'] as num?)?.toInt() ?? 0;
    final rating =
        (profile?['rating_avg'] as num?)?.toStringAsFixed(1) ?? '0.0';
    final avatarPath = profile?['avatar_path'] as String?;
    final String? avatarUrl;
    if (avatarPath == null || avatarPath.isEmpty) {
      avatarUrl = profile?['avatar_url'] as String?;
    } else {
      avatarUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(avatarPath);
    }
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1))
        .join();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.profile(context)),
        automaticallyImplyLeading: false,
        actions: const [NotificationBellButton(), SizedBox(width: 8)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
          ? Center(
              child: Text(
                AppStrings.tr(
                  context,
                  ar: 'تعذر العثور على ملف الحساب.',
                  en: 'Account profile was not found.',
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  // بطاقة بيانات المستخدم المصممة حسب Figma
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _uploadingAvatar ? null : _changeAvatar,
                          child: CircleAvatar(
                            radius: 46,
                            backgroundColor: const Color(0xFF0F172A),
                            backgroundImage:
                                avatarUrl == null || avatarUrl.isEmpty
                                ? null
                                : NetworkImage(avatarUrl),
                            child: _uploadingAvatar
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : avatarUrl == null || avatarUrl.isEmpty
                                ? Text(
                                    initials.isEmpty ? '?' : initials,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        if (isVerified)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.verified_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        PositionedDirectional(
                          bottom: 0,
                          start: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name.isEmpty ? AppStrings.profile(context) : name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    phone.isEmpty
                        ? AppStrings.tr(
                            context,
                            ar: 'لا يوجد رقم مرتبط',
                            en: 'No phone linked',
                          )
                        : phone,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (role == 'driver' && ratingCount > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFF59E0B),
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$rating ($ratingCount ${AppStrings.tr(context, ar: "تقييم", en: "ratings")})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 32),

                  // خيارات الإعدادات
                  if (role == 'driver') ...[
                    _buildTile(
                      icon: Icons.dashboard_customize_rounded,
                      title: AppStrings.driverDashboard(context),
                      iconColor: const Color(0xFFF59E0B),
                      onTap: () => context.go('/driver/home'),
                    ),
                    _buildTile(
                      icon: Icons.directions_car_filled_outlined,
                      title: AppStrings.vehicleInfo(context),
                      onTap: () => context.push(
                        '/verification/personal-details',
                        extra: {'role': 'driver', 'driverOnboarding': true},
                      ),
                    ),
                  ] else ...[
                    _buildTile(
                      icon: Icons.drive_eta_rounded,
                      title: AppStrings.tr(
                        context,
                        ar: 'انضم ككابتن وسائق معتمد',
                        en: 'Become an approved driver',
                      ),
                      iconColor: const Color(0xFF10B981),
                      onTap: () => context.push(
                        '/verification/personal-details',
                        extra: {'role': 'driver', 'driverOnboarding': true},
                      ),
                    ),
                  ],

                  _buildTile(
                    icon: Icons.person_outline_rounded,
                    title: AppStrings.personalDetails(context),
                    onTap: () => context.push(
                      '/verification/personal-details',
                      extra: {'role': role, 'editProfile': true},
                    ),
                  ),

                  // زر تبديل اللغة
                  _buildTile(
                    icon: Icons.language_rounded,
                    title: AppStrings.language(context),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isArabic ? 'العربية (AR)' : 'English (EN)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF59E0B),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    onTap: () {
                      ref.read(localeProvider.notifier).toggleLocale();
                    },
                  ),

                  // زر تبديل الثيم الداكن والفاتح
                  _buildTile(
                    icon: isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    title: AppStrings.darkMode(context),
                    trailing: Switch.adaptive(
                      value: isDark,
                      activeThumbColor: const Color(0xFFF59E0B),
                      onChanged: (_) {
                        ref.read(themeModeProvider.notifier).toggleTheme();
                      },
                    ),
                  ),

                  _buildTile(
                    icon: Icons.headset_mic_outlined,
                    title: AppStrings.helpSupport(context),
                    onTap: () => _showHelpSupportSheet(context),
                  ),

                  _buildTile(
                    icon: Icons.delete_outline_rounded,
                    title: AppStrings.tr(
                      context,
                      ar: 'طلب حذف الحساب',
                      en: 'Request account deletion',
                    ),
                    iconColor: const Color(0xFFEF4444),
                    textColor: const Color(0xFFEF4444),
                    onTap: () => _requestAccountDeletion(context),
                  ),

                  _buildTile(
                    icon: Icons.logout_rounded,
                    title: AppStrings.logout(context),
                    iconColor: const Color(0xFFEF4444),
                    textColor: const Color(0xFFEF4444),
                    trailing: const SizedBox.shrink(),
                    onTap: () async {
                      try {
                        await Supabase.instance.client.auth.signOut();
                        if (context.mounted) context.go('/welcome');
                      } on AuthException catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      }
                    },
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}
