import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

class AccountDestination {
  const AccountDestination(
    this.location, {
    this.extra,
    this.existingAccount = false,
  });

  final String location;
  final Object? extra;
  final bool existingAccount;
}

String createSignupAttemptId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Future<String?> requestPhoneOtp({
    required String phone,
    required bool createUser,
    String? fullName,
    String? role,
    String? signupAttemptId,
  }) async {
    final attemptId = createUser
        ? signupAttemptId ?? createSignupAttemptId()
        : null;
    final metadata = createUser
        ? <String, dynamic>{
            'name': fullName?.trim(),
            'role': role,
            'signup_attempt_id': attemptId,
          }
        : null;

    await _client.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: createUser,
      data: metadata,
    );
    return attemptId;
  }

  /// Completes phone authentication. New signup roles are copied from Auth
  /// metadata by the database trigger; existing accounts keep their saved role.
  Future<AccountDestination> verifyPhoneOtp({
    required String phone,
    required String token,
    required bool registration,
    String? requestedRole,
    String? signupAttemptId,
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
      final selectedRole = requestedRole == 'driver' ? 'driver' : 'passenger';
      final profile = await _client
          .from('profiles')
          .select('id, role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile == null) {
        throw StateError(
          'The profile was not created. Apply the account-role migration.',
        );
      }

      final storedRole = profile['role'] as String? ?? 'passenger';
      final createdForThisSignup = signupAttemptId != null &&
          await _client.rpc(
                'consume_phone_signup_attempt',
                params: {'p_attempt_id': signupAttemptId},
              ) ==
              true;
      if (!createdForThisSignup || storedRole != selectedRole) {
        // signInWithOtp can authenticate an existing phone number. The role
        // selected on the signup form must never overwrite that account's
        // saved role. Do not reopen signup for a previously created account.
        return landingDestination(existingAccount: true);
      }

      return AccountDestination(
        '/verification/personal-details',
        extra: {
          'role': selectedRole,
          if (selectedRole == 'driver') 'driverOnboarding': true,
        },
      );
    }

    return landingDestination();
  }

  /// Call after a provider flow that does not carry a requested app role.
  /// Phone signup stores the selected role in Auth metadata, and the database
  /// trigger copies it to profiles when the Auth user is first created.
  /// Authorization remains in user_roles and the driver role is granted only
  /// after driver verification is approved.
  Future<void> setRequestedAccountRole(String role) async {
    if (role != 'passenger' && role != 'driver') {
      throw ArgumentError.value(role, 'role', 'Unsupported account role.');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in before selecting an account role.');
    }

    await _client.rpc('set_requested_account_role', params: {'p_role': role});
  }

  Future<AccountDestination> landingDestination({
    bool existingAccount = false,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before resolving the account destination.');
    }

    final profile = await _client
        .from('profiles')
        .select('id, role')
        .eq('id', user.id)
        .maybeSingle();
    if (profile == null) {
      throw StateError('The signed-in account has no profile.');
    }

    if (profile['role'] != 'driver') {
      return AccountDestination(
        '/passenger/home',
        existingAccount: existingAccount,
      );
    }

    final roleRows = await _client
        .from('user_roles')
        .select('role')
        .eq('user_id', user.id);
    final hasDriverCapability = roleRows.any((row) => row['role'] == 'driver');

    final driverProfile = await _client
        .from('driver_profiles')
        .select('status, approved_at')
        .eq('user_id', user.id)
        .maybeSingle();
    final approved =
        hasDriverCapability &&
        driverProfile?['status'] == 'approved' &&
        driverProfile?['approved_at'] != null;
    if (approved) {
      return AccountDestination(
        '/driver/home',
        existingAccount: existingAccount,
      );
    }

    final status = driverProfile?['status'] as String?;
    if (status == 'submitted' || status == 'in_review') {
      return AccountDestination(
        '/verification/submitted',
        existingAccount: existingAccount,
      );
    }
    if (status == 'rejected') {
      return AccountDestination(
        '/verification/submitted',
        existingAccount: existingAccount,
      );
    }

    return AccountDestination(
      '/verification/personal-details',
      extra: {'role': 'driver', 'driverOnboarding': true},
      existingAccount: existingAccount,
    );
  }
}
