import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationService {
  VerificationService(this._client);

  final SupabaseClient _client;

  Future<String> _upload(String userId, String kind, XFile file) async {
    final bytes = await file.readAsBytes();
    final path = '$userId/${DateTime.now().microsecondsSinceEpoch}_$kind.jpg';
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
  }

  Future<void> submit({
    required String role,
    required String nationalId,
    required DateTime dateOfBirth,
    required XFile idFront,
    required XFile idBack,
    required XFile selfie,
    XFile? licenseFront,
    XFile? licenseBack,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before submitting verification.');
    }
    if (role != 'passenger' && role != 'driver') {
      throw ArgumentError.value(role, 'role', 'Unsupported account role.');
    }
    if (role == 'driver' && (licenseFront == null || licenseBack == null)) {
      throw ArgumentError('Both sides of the driving license are required.');
    }

    final idFrontPath = await _upload(user.id, 'national-id-front', idFront);
    final idBackPath = await _upload(user.id, 'national-id-back', idBack);
    final selfiePath = await _upload(user.id, 'selfie', selfie);
    final licenseFrontPath = licenseFront == null
        ? null
        : await _upload(user.id, 'license-front', licenseFront);
    final licenseBackPath = licenseBack == null
        ? null
        : await _upload(user.id, 'license-back', licenseBack);

    await _client.from('verification_requests').insert({
      'user_id': user.id,
      'user_role': role,
      'national_id': nationalId,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'id_front_path': idFrontPath,
      'id_back_path': idBackPath,
      'selfie_path': selfiePath,
      'license_front_path': licenseFrontPath,
      'license_back_path': licenseBackPath,
    });
  }
}

final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(Supabase.instance.client);
});
