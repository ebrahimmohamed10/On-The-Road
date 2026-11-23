import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_strings.dart';

/// Camera capture screen with document scanning support, standard camera fallback,
/// and gallery selection option.
class InAppCameraScreen extends StatefulWidget {
  const InAppCameraScreen({
    super.key,
    required this.title,
    this.front = false,
    this.allowGallery = true,
  });

  final String title;
  final bool front;
  final bool allowGallery;

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen> {
  static const _documentScanner = MethodChannel(
    'com.ontheroad/document_scanner',
  );
  CameraController? _controller;
  String? _error;
  bool _takingPicture = false;
  bool _initializing = true;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _initializing = true;
      _error = null;
    });

    // On Android, try GMS Document Scanner first for back-facing document scans
    if (Platform.isAndroid && !widget.front) {
      try {
        final path = await _documentScanner.invokeMethod<String>(
          'captureDocument',
        );
        if (path != null && mounted) {
          Navigator.of(context).pop<XFile>(XFile(path));
          return;
        }
      } catch (_) {
        // Gracefully fall back to standard camera if GMS scanner is not available
      }
    }

    await _initializeStandardCamera();
  }

  Future<void> _initializeStandardCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera available on this device.');
      }
      final direction = widget.front
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == direction,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
        _error = null;
      });
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.description ?? error.code;
          _initializing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _initializing = false;
        });
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        _takingPicture ||
        !controller.value.isInitialized) {
      return;
    }
    setState(() => _takingPicture = true);
    try {
      final file = await controller.takePicture();
      if (mounted) Navigator.of(context).pop<XFile>(file);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked != null && mounted) {
        Navigator.of(context).pop<XFile>(picked);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.tr(
                context,
                ar: 'تعذر اختيار الصورة من المعرض: $error',
                en: 'Could not pick image from gallery: $error',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.allowGallery)
            IconButton(
              icon: const Icon(Icons.photo_library_outlined),
              tooltip: AppStrings.tr(context, ar: 'المعرض', en: 'Gallery'),
              onPressed: _pickFromGallery,
            ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.camera_alt_outlined,
                        size: 64,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppStrings.tr(
                          context,
                          ar: 'تعذر فتح الكاميرا مباشرةً على هذا الجهاز.',
                          en: 'Could not open camera directly on this device.',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (widget.allowGallery)
                        ElevatedButton.icon(
                          onPressed: _pickFromGallery,
                          icon: const Icon(Icons.photo_library_rounded),
                          label: Text(
                            AppStrings.tr(
                              context,
                              ar: 'اختيار من المعرض أو الملفات',
                              en: 'Choose from Gallery / Files',
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _initialize,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(
                          AppStrings.tr(context, ar: 'إعادة المحاولة', en: 'Retry'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : _initializing || controller == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),

                  // Overlay guide for documents
                  Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.88,
                      height: MediaQuery.of(context).size.width * 0.88 * 0.63,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFF59E0B),
                          width: 2.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),

                  // Bottom Controls
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.8),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (widget.allowGallery)
                            IconButton(
                              onPressed: _pickFromGallery,
                              iconSize: 36,
                              color: Colors.white,
                              icon: const Icon(Icons.photo_library_rounded),
                              tooltip: AppStrings.tr(
                                context,
                                ar: 'المعرض',
                                en: 'Gallery',
                              ),
                            )
                          else
                            const SizedBox(width: 48),
                          FloatingActionButton.large(
                            heroTag: 'inAppCameraShutter',
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            onPressed: _takingPicture ? null : _capture,
                            child: _takingPicture
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Icon(Icons.camera_alt, size: 36),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
