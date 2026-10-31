import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

class EgyptianIdOcrResult {
  const EgyptianIdOcrResult({required this.rawText, required this.nationalId});

  final String rawText;
  final String? nationalId;
}

class EgyptianIdOcr {
  static Future<EgyptianIdOcrResult> readFront(String imagePath) async {
    final rawText = await TesseractOcr.extractText(
      imagePath,
      config: OCRConfig(
        language: 'ara+eng',
        engine: OCREngine.tesseract,
        options: const {'preserve_interword_spaces': '1'},
      ),
    );
    final normalized = _normalizeDigits(rawText);
    final idMatch = RegExp(r'(?<!\d)\d{14}(?!\d)').firstMatch(normalized);
    return EgyptianIdOcrResult(
      rawText: rawText.trim(),
      nationalId: idMatch?.group(0),
    );
  }

  static String _normalizeDigits(String value) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';
    return value.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (match) {
      final digit = match.group(0)!;
      final index = arabicIndic.indexOf(digit);
      return (index >= 0 ? index : easternArabicIndic.indexOf(digit))
          .toString();
    });
  }
}
