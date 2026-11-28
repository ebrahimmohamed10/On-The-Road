import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

class VerificationService {
  VerificationService(this._client);

  final SupabaseClient _client;

  Future<String> _upload(
    String userId,
    String kind,
    XFile file, {
    String bucket = 'identity-documents',
  }) async {
    final bytes = await file.readAsBytes();
    return _uploadBytes(userId, kind, bytes, bucket);
  }

  Future<String> _uploadBytes(
    String userId,
    String kind,
    Uint8List bytes,
    String bucket,
  ) async {
    final path = '$userId/${DateTime.now().microsecondsSinceEpoch}_$kind.jpg';
    try {
      await _client.storage
          .from(bucket)
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

  Future<String> _resolveIdentityImage({
    required String userId,
    required String kind,
    required XFile? file,
    required String? existingPath,
  }) async {
    if (file != null) return _upload(userId, kind, file);
    if (existingPath != null && existingPath.isNotEmpty) {
      // Reuse the same Storage object for unchanged documents. The database
      // records only changed images as new review versions.
      return existingPath;
    }
    throw ArgumentError('الصورة المطلوبة غير موجودة: $kind');
  }

  Future<void> _submitVehicle({
    required String userId,
    required String make,
    required String model,
    required String color,
    required String plate,
    required int seats,
    required XFile licenseFront,
    required XFile licenseBack,
  }) async {
    final vehicle = await _client
        .from('vehicles')
        .insert({
          'owner_id': userId,
          'make': make,
          'model': model,
          'color': color,
          'plate': plate,
          'seats': seats,
        })
        .select('id')
        .single();
    final vehicleId = vehicle['id'] as String;
    final frontPath = await _upload(
      userId,
      'vehicle-license-front',
      licenseFront,
      bucket: 'vehicle-documents',
    );
    final backPath = await _upload(
      userId,
      'vehicle-license-back',
      licenseBack,
      bucket: 'vehicle-documents',
    );
    await _client.from('vehicle_documents').insert([
      {
        'user_id': userId,
        'vehicle_id': vehicleId,
        'document_type': 'vehicle_license_front',
        'storage_path': frontPath,
      },
      {
        'user_id': userId,
        'vehicle_id': vehicleId,
        'document_type': 'vehicle_license_back',
        'storage_path': backPath,
      },
    ]);
    await _client.rpc(
      'submit_vehicle_for_review',
      params: {'p_vehicle_id': vehicleId},
    );
  }

  Future<void> submit({
    required String role,
    required String nationalId,
    required DateTime dateOfBirth,
    required String gender,
    required String city,
    XFile? idFront,
    XFile? idBack,
    XFile? faceFront,
    XFile? faceRight,
    XFile? faceLeft,
    DateTime? poseChallengeCompletedAt,
    required Map<String, String> existingDocumentPaths,
    XFile? licenseFront,
    XFile? licenseBack,
    XFile? vehicleFront,
    XFile? vehicleRight,
    XFile? vehicleLeft,
    XFile? vehicleRear,
    XFile? vehicleLicenseFront,
    XFile? vehicleLicenseBack,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleColor,
    String? vehiclePlate,
    int? vehicleSeats,
    bool resubmittingExistingProfile = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('يجب تسجيل الدخول أولًا لتقديم طلب التحقق.');
    }
    if (role != 'passenger' && role != 'driver') {
      throw ArgumentError.value(role, 'role', 'نوع الحساب غير مدعوم.');
    }
    if (role == 'driver' &&
        ((licenseFront == null &&
                existingDocumentPaths['driver_license_front'] == null) ||
            (licenseBack == null &&
                existingDocumentPaths['driver_license_back'] == null) ||
            (vehicleFront == null &&
                existingDocumentPaths['vehicle_exterior_front'] == null) ||
            (vehicleRight == null &&
                existingDocumentPaths['vehicle_exterior_right'] == null) ||
            (vehicleLeft == null &&
                existingDocumentPaths['vehicle_exterior_left'] == null) ||
            (vehicleRear == null &&
                existingDocumentPaths['vehicle_exterior_rear'] == null))) {
      throw ArgumentError('صور رخصة القيادة أو السيارة غير مكتملة.');
    }
    if (role == 'driver' &&
        !resubmittingExistingProfile &&
        (vehicleLicenseFront == null ||
            vehicleLicenseBack == null ||
            vehicleMake == null ||
            vehicleModel == null ||
            vehicleColor == null ||
            vehiclePlate == null ||
            vehicleSeats == null)) {
      throw ArgumentError('أكمل رخصة السيارة وبياناتها.');
    }

    final idFrontPath = await _resolveIdentityImage(
      userId: user.id,
      kind: 'national-id-front',
      file: idFront,
      existingPath: existingDocumentPaths['national_id_front'],
    );
    final idBackPath = await _resolveIdentityImage(
      userId: user.id,
      kind: 'national-id-back',
      file: idBack,
      existingPath: existingDocumentPaths['national_id_back'],
    );
    final faceFrontPath = await _resolveIdentityImage(
      userId: user.id,
      kind: 'face-scan-front',
      file: faceFront,
      existingPath: existingDocumentPaths['face_scan_front'],
    );
    final faceRightPath = await _resolveIdentityImage(
      userId: user.id,
      kind: 'face-scan-right',
      file: faceRight,
      existingPath: existingDocumentPaths['face_scan_right'],
    );
    final faceLeftPath = await _resolveIdentityImage(
      userId: user.id,
      kind: 'face-scan-left',
      file: faceLeft,
      existingPath: existingDocumentPaths['face_scan_left'],
    );

    final licenseFrontPath = role == 'driver'
        ? await _resolveIdentityImage(
            userId: user.id,
            kind: 'driver-license-front',
            file: licenseFront,
            existingPath: existingDocumentPaths['driver_license_front'],
          )
        : null;
    final licenseBackPath = role == 'driver'
        ? await _resolveIdentityImage(
            userId: user.id,
            kind: 'driver-license-back',
            file: licenseBack,
            existingPath: existingDocumentPaths['driver_license_back'],
          )
        : null;
    final vehicleFrontPath = role == 'driver'
        ? await _resolveIdentityImage(
            userId: user.id,
            kind: 'vehicle-exterior-front',
            file: vehicleFront,
            existingPath: existingDocumentPaths['vehicle_exterior_front'],
          )
        : null;
    final vehicleRightPath = role == 'driver'
        ? await _resolveIdentityImage(
            userId: user.id,
            kind: 'vehicle-exterior-right',
            file: vehicleRight,
            existingPath: existingDocumentPaths['vehicle_exterior_right'],
          )
        : null;
    final vehicleLeftPath = role == 'driver'
        ? await _resolveIdentityImage(
            userId: user.id,
            kind: 'vehicle-exterior-left',
            file: vehicleLeft,
            existingPath: existingDocumentPaths['vehicle_exterior_left'],
          )
        : null;
    final vehicleRearPath = role == 'driver'
        ? await _resolveIdentityImage(
            userId: user.id,
            kind: 'vehicle-exterior-rear',
            file: vehicleRear,
            existingPath: existingDocumentPaths['vehicle_exterior_rear'],
          )
        : null;

    if (role == 'driver' && !resubmittingExistingProfile) {
      await _submitVehicle(
        userId: user.id,
        make: vehicleMake!.trim(),
        model: vehicleModel!.trim(),
        color: vehicleColor!.trim(),
        plate: vehiclePlate!.trim(),
        seats: vehicleSeats!,
        licenseFront: vehicleLicenseFront!,
        licenseBack: vehicleLicenseBack!,
      );
    }

    final payload = {
      'user_id': user.id,
      'user_role': role,
      'national_id': nationalId,
      'date_of_birth': dateOfBirth.toIso8601String().split('T').first,
      'gender': gender,
      'city': city,
      'id_front_path': idFrontPath,
      'id_back_path': idBackPath,
      'selfie_path': faceFrontPath,
      'face_front_path': faceFrontPath,
      'face_right_path': faceRightPath,
      'face_left_path': faceLeftPath,
      'client_pose_challenge_completed_at': poseChallengeCompletedAt
          ?.toUtc()
          .toIso8601String(),
      'license_front_path': licenseFrontPath,
      'license_back_path': licenseBackPath,
      'vehicle_front_path': vehicleFrontPath,
      'vehicle_right_path': vehicleRightPath,
      'vehicle_left_path': vehicleLeftPath,
      'vehicle_rear_path': vehicleRearPath,
    };
    try {
      await _client.from('verification_requests').insert(payload);
    } on PostgrestException catch (e) {
      throw StateError('خطأ في قاعدة البيانات: ${e.message}');
    }
    await cleanupSupersededDocuments();
  }

  /// Removes retired document objects only after the DB has marked them as
  /// superseded. Accepted replacements are retired by the review RPC and are
  /// cleaned up the next time the user's app opens this flow/profile.
  Future<void> cleanupSupersededDocuments() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _removeSupersededRows(
      table: 'verification_documents',
      userId: user.id,
      bucketForType: (type) => 'identity-documents',
    );
    await _removeSupersededRows(
      table: 'vehicle_documents',
      userId: user.id,
      bucketForType: (_) => 'vehicle-documents',
    );
  }

  Future<void> _removeSupersededRows({
    required String table,
    required String userId,
    required String Function(String type) bucketForType,
  }) async {
    try {
      final rows = await _client
          .from(table)
          .select('id,document_type,storage_path')
          .eq('user_id', userId)
          .not('superseded_at', 'is', null)
          .isFilter('storage_deleted_at', null);
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final type = row['document_type'] as String?;
        final path = row['storage_path'] as String?;
        if (type == null || path == null || path.isEmpty) continue;
        grouped.putIfAbsent(bucketForType(type), () => []).add(row);
      }
      for (final entry in grouped.entries) {
        for (var offset = 0; offset < entry.value.length; offset += 1000) {
          final batch = entry.value.skip(offset).take(1000).toList();
          try {
            await _client.storage
                .from(entry.key)
                .remove(
                  batch.map((row) => row['storage_path'] as String).toList(),
                );
            await _client
                .from(table)
                .update({
                  'storage_deleted_at': DateTime.now()
                      .toUtc()
                      .toIso8601String(),
                })
                .eq('user_id', userId)
                .inFilter('id', batch.map((row) => row['id']).toList());
          } catch (_) {
            // A failed Storage delete remains eligible for cleanup next time.
          }
        }
      }
    } catch (_) {
      // Cleanup is best-effort and must never block verification submission.
    }
  }
}

final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(Supabase.instance.client);
});
