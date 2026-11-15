import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

enum EgyptianIdOcrFailure {
  notConfigured,
  signInRequired,
  googlePermissionDenied,
  providerUnavailable,
}

class EgyptianIdOcrException implements Exception {
  const EgyptianIdOcrException(this.failure);

  final EgyptianIdOcrFailure failure;
}

class EgyptianIdOcrResult {
  const EgyptianIdOcrResult({required this.rawText, required this.nationalId});

  final String rawText;
  final String? nationalId;
}

class EgyptianIdOcr {
  static Future<EgyptianIdOcrResult> readFront(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    late final FunctionResponse response;
    try {
      response = await Supabase.instance.client.functions.invoke(
        'ocr-egyptian-id',
        body: {'imageBase64': base64Encode(bytes), 'contentType': 'image/jpeg'},
      );
    } on FunctionException catch (error) {
      if (error.status == 503) {
        throw const EgyptianIdOcrException(EgyptianIdOcrFailure.notConfigured);
      }
      if (error.status == 401 || error.status == 403) {
        throw const EgyptianIdOcrException(EgyptianIdOcrFailure.signInRequired);
      }
      final details = error.details;
      if (error.status == 502 &&
          details is Map &&
          details['providerCode'] == 'PERMISSION_DENIED') {
        throw const EgyptianIdOcrException(
          EgyptianIdOcrFailure.googlePermissionDenied,
        );
      }
      throw const EgyptianIdOcrException(
        EgyptianIdOcrFailure.providerUnavailable,
      );
    } catch (_) {
      throw const EgyptianIdOcrException(
        EgyptianIdOcrFailure.providerUnavailable,
      );
    }
    if (response.status < 200 || response.status >= 300) {
      throw StateError('ID OCR service returned ${response.status}.');
    }
    final data = response.data;
    if (data is! Map || data['text'] is! String) {
      throw const FormatException('ID OCR service returned invalid data.');
    }
    final rawText = data['text'] as String;
    final normalized = normalizeDigits(rawText);
    final nationalId = _extractNationalId(normalized);
    return EgyptianIdOcrResult(rawText: rawText.trim(), nationalId: nationalId);
  }

  /// Finds the Egyptian national ID even when OCR inserts spaces or hyphens
  /// between digits. Rejects candidates whose embedded birth date is invalid.
  static String? _extractNationalId(String text) {
    final candidates = RegExp(
      // OCR may insert punctuation, spaces, or line-wrapping noise
      // inside the printed ID. Keep runs short so separate numbers cannot
      // normally be joined into a false 14-digit candidate.
      r'(?<![0-9])([23](?:[^0-9]{0,4}[0-9]){13})(?![0-9])',
    ).allMatches(text);

    for (final match in candidates) {
      final candidate = match.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
      if (_hasValidEmbeddedBirthDate(candidate)) return candidate;
    }
    return null;
  }

  static bool _hasValidEmbeddedBirthDate(String id) {
    if (id.length != 14 || (id[0] != '2' && id[0] != '3')) return false;
    final century = id[0] == '2' ? 1900 : 2000;
    final year = century + int.parse(id.substring(1, 3));
    final month = int.parse(id.substring(3, 5));
    final day = int.parse(id.substring(5, 7));
    final date = DateTime.tryParse(
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    return date != null &&
        date.year == year &&
        date.month == month &&
        date.day == day &&
        !date.isAfter(DateTime.now());
  }

  static String normalizeDigits(String value) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    return value.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
      final digit = match.group(0)!;
      final index = arabicIndic.indexOf(digit);
      return (index >= 0 ? index : easternArabicIndic.indexOf(digit))
          .toString();
    });
  }

  static String? governorateFromNationalId(String id) {
    if (id.length != 14) return null;
    const governorates = {
      '01': 'القاهرة',
      '02': 'الإسكندرية',
      '03': 'بورسعيد',
      '04': 'السويس',
      '11': 'دمياط',
      '12': 'الدقهلية',
      '13': 'الشرقية',
      '14': 'القليوبية',
      '15': 'كفر الشيخ',
      '16': 'الغربية',
      '17': 'المنوفية',
      '18': 'البحيرة',
      '19': 'الإسماعيلية',
      '21': 'الجيزة',
      '22': 'بني سويف',
      '23': 'الفيوم',
      '24': 'المنيا',
      '25': 'أسيوط',
      '26': 'سوهاج',
      '27': 'قنا',
      '28': 'أسوان',
      '29': 'الأقصر',
      '31': 'البحر الأحمر',
      '32': 'الوادي الجديد',
      '33': 'مطروح',
      '34': 'شمال سيناء',
      '35': 'جنوب سيناء',
    };
    return governorates[id.substring(7, 9)];
  }

  static String? genderFromNationalId(String id) {
    if (id.length != 14) return null;
    final serialDigit = int.tryParse(id[12]);
    if (serialDigit == null) return null;
    return serialDigit.isOdd ? 'male' : 'female';
  }
}
