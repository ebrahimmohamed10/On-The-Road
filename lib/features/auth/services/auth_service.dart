import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(Supabase.instance.client);
});

class AccountDestination {
  const AccountDestination(this.location, {this.extra});

  final String location;
  final Object? extra;
}

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

  /// Completes phone authentication and, for signup, saves the requested app
  /// role on the profile. This does not grant the driver capability.
  Future<AccountDestination> verifyPhoneOtp({
    required String phone,
    required String token,
    required bool registration,
    String? requestedRole,
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
      await setRequestedAccountRole(
        requestedRole == 'driver' ? 'driver' : 'passenger',
      );
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
    }

    return landingDestination();
  }

  /// Call after any provider flow (phone, Google, or another future provider)
  /// when the new account has selected its requested rider/driver experience.
  /// The database stores this on profiles and keeps authorization in user_roles.
  Future<void> setRequestedAccountRole(String role) async {
    if (role != 'passenger' && role != 'driver') {
      throw ArgumentError.value(role, 'role', 'Unsupported account role.');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in before selecting an account role.');
    }

    await _client.rpc('set_requested_account_role', params: {'p_role': role});
  }

  Future<AccountDestination> landingDestination() async {
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
      return const AccountDestination('/passenger/home');
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
      return const AccountDestination('/driver/home');
    }

    final status = driverProfile?['status'] as String?;
    if (status == 'submitted' || status == 'in_review') {
      return const AccountDestination('/verification/submitted');
    }
    if (status == 'rejected') {
      return const AccountDestination('/verification/submitted');
    }

    return const AccountDestination(
      '/verification/personal-details',
      extra: {'role': 'driver', 'driverOnboarding': true},
    );
  }
}
