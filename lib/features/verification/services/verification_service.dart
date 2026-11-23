import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationService {
  VerificationService(this._client);

  final SupabaseClient _client;

  Future<String> _upload(String userId, String kind, XFile file) async {
    final bytes = await file.readAsBytes();
    final path = '$userId/${DateTime.now().microsecondsSinceEpoch}_$kind.jpg';

    try {
      await _client.storage
          .from('identity-documents')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      return path;
    } on StorageException catch (e) {
      throw StateError('خطأ أثناء رفع $kind: ${e.message}');
    } catch (e) {
      throw StateError('تعذر رفع $kind: $e');
    }
  }

  Future<void> submit({
    required String role,
    required String nationalId,
    required DateTime dateOfBirth,
    required String gender,
    required String city,
    required XFile idFront,
    required XFile idBack,
    required XFile faceFront,
    required XFile faceRight,
    required XFile faceLeft,
    required DateTime poseChallengeCompletedAt,
    XFile? licenseFront,
    XFile? licenseBack,
    XFile? vehicleFront,
    XFile? vehicleRight,
    XFile? vehicleLeft,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('يجب تسجيل الدخول أولًا لتقديم طلب التحقق.');
    }

    if (role != 'passenger' && role != 'driver') {
      throw ArgumentError.value(role, 'role', 'نوع الحساب غير مدعوم.');
    }

    if (role == 'driver' && (licenseFront == null || licenseBack == null)) {
      throw ArgumentError('يجب تصوير وجهي رخصة القيادة.');
    }
    if (role == 'driver' &&
        (vehicleFront == null || vehicleRight == null || vehicleLeft == null)) {
      throw ArgumentError(
        'يجب تصوير السيارة من الأمام والجانب الأيمن والجانب الأيسر.',
      );
    }

    final idFrontPath = await _upload(user.id, 'national-id-front', idFront);
    final idBackPath = await _upload(user.id, 'national-id-back', idBack);
    final faceFrontPath = await _upload(user.id, 'face-scan-front', faceFront);
    final faceRightPath = await _upload(user.id, 'face-scan-right', faceRight);
    final faceLeftPath = await _upload(user.id, 'face-scan-left', faceLeft);

    final licenseFrontPath = licenseFront == null
        ? null
        : await _upload(user.id, 'license-front', licenseFront);

    final licenseBackPath = licenseBack == null
        ? null
        : await _upload(user.id, 'license-back', licenseBack);
    final vehicleFrontPath = vehicleFront == null
        ? null
        : await _upload(user.id, 'vehicle-exterior-front', vehicleFront);
    final vehicleRightPath = vehicleRight == null
        ? null
        : await _upload(user.id, 'vehicle-exterior-right', vehicleRight);
    final vehicleLeftPath = vehicleLeft == null
        ? null
        : await _upload(user.id, 'vehicle-exterior-left', vehicleLeft);

    final payload = {
      'user_id': user.id,
      'user_role': role,
      'national_id': nationalId,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'gender': gender,
      'city': city,
      'id_front_path': idFrontPath,
      'id_back_path': idBackPath,
      // Keep legacy selfie_path populated with the frontal image.
      'selfie_path': faceFrontPath,
      'face_front_path': faceFrontPath,
      'face_right_path': faceRightPath,
      'face_left_path': faceLeftPath,
      'client_pose_challenge_completed_at': poseChallengeCompletedAt
          .toUtc()
          .toIso8601String(),
      'license_front_path': licenseFrontPath,
      'license_back_path': licenseBackPath,
      'vehicle_front_path': vehicleFrontPath,
      'vehicle_right_path': vehicleRightPath,
      'vehicle_left_path': vehicleLeftPath,
    };

    try {
      await _client.from('verification_requests').insert(payload);
    } on PostgrestException catch (e) {
      throw StateError('خطأ في قاعدة البيانات: ${e.message}');
    }
  }
}

final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(Supabase.instance.client);
});
