/// Normalizes Egyptian mobile numbers to Supabase's required E.164 format.
/// Accepted input: local 01xxxxxxxxx or international +201xxxxxxxxx.
String? normalizeEgyptianPhoneNumber(String input) {
  final compact = normalizeNumeralDigits(input)
      .replaceAll(RegExp(r'[\s\-\u2010-\u2015]'), '');

  if (RegExp(r'^01[0125][0-9]{8}$').hasMatch(compact)) {
    return '+20${compact.substring(1)}';
  }

  if (RegExp(r'^\+201[0125][0-9]{8}$').hasMatch(compact)) {
    return compact;
  }

  return null;
}

String normalizeNumeralDigits(String input) {
  return input.replaceAllMapped(RegExp(r'[\u0660-\u0669\u06F0-\u06F9]'), (
    match,
  ) {
    final codePoint = match.group(0)!.runes.single;
    final zero = codePoint >= 0x06F0 ? 0x06F0 : 0x0660;
    return String.fromCharCode(0x30 + codePoint - zero);
  });
}
