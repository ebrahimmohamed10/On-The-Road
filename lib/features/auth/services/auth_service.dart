import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Future<void> requestPhoneOtp({
    required String phone,
    required bool createUser,
    String? fullName,
    String? role,
  }) async {
    final metadata = createUser
        ? <String, dynamic>{'name': fullName?.trim(), 'role': role}
        : null;

    await _client.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: createUser,
      data: metadata,
    );
  }

  Future<void> verifyPhoneOtp({
    required String phone,
    required String token,
    required bool registration,
  }) async {
    final response = await _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: phone,
      token: token,
    );

    final user = response.user;
    if (user == null) {
      throw StateError('Supabase verified the code but returned no user.');
    }

    if (registration) {
      // The database trigger creates this row from Auth user metadata. Confirm
      // that the trigger ran before allowing the registration flow to proceed.
      final profile = await _client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      if (profile == null) {
        throw StateError(
          'The profile was not created. Apply the Phase 1 profile migration.',
        );
      }
    }
  }
}
