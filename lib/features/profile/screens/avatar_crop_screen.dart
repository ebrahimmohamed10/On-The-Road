import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final CropController _controller = CropController();
  bool _cropping = false;
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStrings.tr(
            context,
            ar: 'تعديل صورة البروفايل',
            en: 'Edit profile photo',
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Text(
                AppStrings.tr(
                  context,
                  ar: 'حرّك الصورة وكبّرها أو صغّرها داخل الدائرة',
                  en: 'Move and zoom the photo inside the circle',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Crop(
                  image: widget.imageBytes,
                  controller: _controller,
                  withCircleUi: true,
                  interactive: true,
                  fixCropRect: true,
                  radius: 180,
                  onStatusChanged: (status) {
                    if (status == CropStatus.ready && mounted) {
                      setState(() => _ready = true);
                    }
                  },
                  onCropped: (result) {
                    if (!mounted) return;
                    switch (result) {
                      case CropSuccess(:final croppedImage):
                        Navigator.of(context).pop(croppedImage);
                        return;
                      case CropFailure():
                        setState(() => _cropping = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppStrings.tr(
                                context,
                                ar: 'تعذر تعديل الصورة. اختَر صورة أخرى.',
                                en: 'Could not crop this photo. Choose another one.',
                              ),
                            ),
                          ),
                        );
                    }
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: !_ready || _cropping
                      ? null
                      : () {
                          setState(() => _cropping = true);
                          _controller.cropCircle();
                        },
                  icon: _cropping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    AppStrings.tr(
                      context,
                      ar: 'استخدام الصورة',
                      en: 'Use photo',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
