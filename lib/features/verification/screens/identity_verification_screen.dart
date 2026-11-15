import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class IdentityVerificationScreen extends ConsumerStatefulWidget {
  const IdentityVerificationScreen({
    super.key,
    required this.role,
    required this.nationalId,
    required this.dateOfBirth,
    required this.gender,
    required this.city,
    required this.idFrontPath,
    this.documentPaths = const {},
  });

  final String role;
  final String nationalId;
  final String dateOfBirth;
  final String gender;
  final String city;
  final String? idFrontPath;
  final Map<String, String> documentPaths;

  @override
  ConsumerState<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends ConsumerState<IdentityVerificationScreen> {
  bool _photoTaken = false;
  bool _processingFrame = false;
  bool _cameraLoading = true;
  String? _cameraError;
  String? _faceFeedback;
  DateTime _lastFaceFeedbackAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _challengeStage = 0;
  XFile? _faceFront;
  XFile? _faceRight;
  XFile? _faceLeft;
  DateTime? _poseChallengeCompletedAt;
  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  late final FaceDetector _faceDetector;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : null,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _cameraDescription = camera;
      _cameraController = controller;
      await controller.startImageStream(_processFrame);
      setState(() => _cameraLoading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _cameraLoading = false;
          _cameraError = error.toString();
        });
      }
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _cameraDescription;
    if (camera == null || image.planes.isEmpty) return null;
    final rotation = Platform.isAndroid
        ? _androidInputRotation(camera)
        : InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final supportedFormat = Platform.isAndroid
        ? format == InputImageFormat.nv21
        : Platform.isIOS
        ? format == InputImageFormat.bgra8888
        : false;
    if (rotation == null || !supportedFormat || image.planes.length != 1) {
      return null;
    }
    final plane = image.planes.single;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format!,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _androidInputRotation(CameraDescription camera) {
    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final controller = _cameraController;
    if (controller == null) return null;
    final compensation = orientations[controller.value.deviceOrientation];
    if (compensation == null) return null;
    final degrees = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + compensation) % 360
        : (camera.sensorOrientation - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(degrees);
  }

  void _setFaceFeedback(String message) {
    final now = DateTime.now();
    if (_faceFeedback == message ||
        now.difference(_lastFaceFeedbackAt).inMilliseconds < 700) {
      return;
    }
    _lastFaceFeedbackAt = now;
    if (mounted) setState(() => _faceFeedback = message);
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processingFrame || _photoTaken || _cameraController == null) return;
    final inputImage = _toInputImage(image);
    if (inputImage == null) return;
    _processingFrame = true;
    try {
      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted) return;
      if (faces.isEmpty) {
        _setFaceFeedback('no_face');
        return;
      }
      if (faces.length != 1) {
        _setFaceFeedback('multiple_faces');
        return;
      }
      _setFaceFeedback('face_detected');
      final yaw = faces.single.headEulerAngleY;
      if (yaw == null) {
        _setFaceFeedback('pose_unavailable');
        return;
      }
      // The live selfie preview is mirrored for the user. Invert ML Kit's
      // image-space yaw so the prompts match the user's own left/right.
      final userYaw = cameraLensIsFront ? -yaw : yaw;

      if (_challengeStage == 0 && userYaw.abs() < 12) {
        _faceFront = await _captureFaceAngle();
        if (mounted) setState(() => _challengeStage = 1);
      } else if (_challengeStage == 1 && userYaw > 18) {
        _faceRight = await _captureFaceAngle();
        if (mounted) setState(() => _challengeStage = 2);
      } else if (_challengeStage == 2 && userYaw.abs() < 12) {
        setState(() => _challengeStage = 3);
      } else if (_challengeStage == 3 && userYaw < -18) {
        _faceLeft = await _captureFaceAngle();
        await _finishLivenessCapture();
      }
    } catch (_) {
      _setFaceFeedback('analysis_error');
    } finally {
      _processingFrame = false;
    }
  }

  bool get cameraLensIsFront =>
      _cameraDescription?.lensDirection == CameraLensDirection.front;

  String? _faceFeedbackText(BuildContext context) {
    final message = _faceFeedback;
    if (message == null) return null;
    final (ar, en) = switch (message) {
      'no_face' => (
        'لم يتم رصد وجه بوضوح؛ قرّب وجهك وحسّن الإضاءة.',
        'No clear face detected. Move closer and improve the lighting.',
      ),
      'multiple_faces' => (
        'يجب أن يظهر وجه واحد فقط داخل الإطار.',
        'Only one face should be visible in the frame.',
      ),
      'face_detected' => (
        'تم رصد الوجه؛ اتبع تعليمات الحركة.',
        'Face detected. Follow the movement prompts.',
      ),
      'pose_unavailable' => (
        'ثبّت وجهك أمام الكاميرا لحظة.',
        'Hold your face still in front of the camera.',
      ),
      _ => (
        'تعذر تحليل إطار الكاميرا؛ ثبّت الهاتف وحاول مجددًا.',
        'Could not analyze the camera frame. Hold the phone steady and retry.',
      ),
    };
    return AppStrings.tr(context, ar: ar, en: en);
  }

  Future<XFile> _captureFaceAngle() async {
    final controller = _cameraController;
    if (controller == null || _photoTaken) {
      throw StateError('Camera is not ready to capture the face angle.');
    }
    await controller.stopImageStream();
    try {
      return await controller.takePicture();
    } finally {
      if (mounted && !_photoTaken) {
        await controller.startImageStream(_processFrame);
      }
    }
  }

  Future<void> _finishLivenessCapture() async {
    final controller = _cameraController;
    if (controller == null || _photoTaken) return;
    await controller.stopImageStream();
    if (mounted) {
      setState(() {
        _poseChallengeCompletedAt = DateTime.now().toUtc();
        _photoTaken = true;
        _challengeStage = 4;
      });
    }
  }

  Future<void> _restartChallenge() async {
    final controller = _cameraController;
    if (controller == null) return;
    setState(() {
      _faceFront = null;
      _faceRight = null;
      _faceLeft = null;
      _poseChallengeCompletedAt = null;
      _photoTaken = false;
      _challengeStage = 0;
      _faceFeedback = null;
    });
    await controller.startImageStream(_processFrame);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  void _onContinue() {
    final faceFront = _faceFront;
    final faceRight = _faceRight;
    final faceLeft = _faceLeft;
    final poseChallengeCompletedAt = _poseChallengeCompletedAt;
    if (faceFront == null ||
        faceRight == null ||
        faceLeft == null ||
        poseChallengeCompletedAt == null) {
      return;
    }
    context.push(
      '/verification/driver-docs',
      extra: {
        'role': widget.role,
        'nationalId': widget.nationalId,
        'dateOfBirth': widget.dateOfBirth,
        'gender': widget.gender,
        'city': widget.city,
        'idFrontPath': widget.idFrontPath,
        'documentPaths': widget.documentPaths,
        'faceFrontPath': faceFront.path,
        'faceRightPath': faceRight.path,
        'faceLeftPath': faceLeft.path,
        'poseChallengeCompletedAt': poseChallengeCompletedAt.toIso8601String(),
      },
    );
  }

  String _challengeInstruction(BuildContext context) {
    switch (_challengeStage) {
      case 0:
        return AppStrings.tr(
          context,
          ar: 'ثبّت وجهك داخل الإطار وانظر للأمام',
          en: 'Fit your face in the frame and look straight ahead',
        );
      case 1:
        return AppStrings.tr(
          context,
          ar: 'لفّ وجهك ناحية اليمين',
          en: 'Turn your face to the right',
        );
      case 2:
        return AppStrings.tr(
          context,
          ar: 'تمام، ارجع بوجهك للمنتصف',
          en: 'Good, look straight ahead again',
        );
      case 3:
        return AppStrings.tr(
          context,
          ar: 'لفّ وجهك ناحية الشمال',
          en: 'Turn your face to the left',
        );
      default:
        return AppStrings.tr(
          context,
          ar: 'تم التقاط صور الوجه الأمامية واليمين والشمال',
          en: 'Front, right, and left face photos captured',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  AppStrings.verifyIdentity(context),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  AppStrings.selfieInstruction(context),
                  style: theme.textTheme.bodyMedium,
                ),
              ),

              const Spacer(),

              // إطار كاميرا السيلفي — مطابق لتصميم الـ Figma
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 250,
                    height: 310,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _photoTaken
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (_photoTaken
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFF59E0B))
                                  .withValues(alpha: 0.15),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _photoTaken && _faceFront != null
                        ? Image.file(File(_faceFront!.path), fit: BoxFit.cover)
                        : _cameraController?.value.isInitialized == true
                        ? CameraPreview(_cameraController!)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _photoTaken
                                    ? Icons.check_circle_rounded
                                    : Icons.face_retouching_natural_rounded,
                                size: 110,
                                color: _photoTaken
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B)
                                          .withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _photoTaken
                                    ? AppStrings.tr(
                                        context,
                                        ar: 'تم التقاط الصورة بنجاح',
                                        en: 'Selfie captured',
                                      )
                                    : AppStrings.tr(
                                        context,
                                        ar: 'ضع وجهك هنا',
                                        en: 'Fit face here',
                                      ),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _photoTaken
                                      ? const Color(0xFF10B981)
                                      : theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                  ),

                  // زوايا التأطير (Corner Guides)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFF59E0B), width: 3),
                          left: BorderSide(color: Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Color(0xFFF59E0B), width: 3),
                          right: BorderSide(color: Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFFF59E0B),
                            width: 3,
                          ),
                          left: BorderSide(color: Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFFF59E0B),
                            width: 3,
                          ),
                          right: BorderSide(color: Color(0xFFF59E0B), width: 3),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // أزرار التحكم
              if (_cameraError != null)
                Text(
                  AppStrings.tr(
                    context,
                    ar: 'تعذر تشغيل فحص الوجه. تحقق من إذن الكاميرا ثم حاول مجددًا.',
                    en: 'Could not start the face check. Check camera permission and try again.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else if (!_photoTaken)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: _challengeStage >= 4
                          ? 1
                          : _challengeStage >= 2
                          ? 0.5
                          : 0,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _cameraLoading
                          ? AppStrings.tr(
                              context,
                              ar: 'جارٍ تشغيل الكاميرا…',
                              en: 'Starting camera…',
                            )
                          : _challengeInstruction(context),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_faceFeedback != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _faceFeedbackText(context)!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _faceFeedback == 'face_detected'
                              ? const Color(0xFF10B981)
                              : theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _angleThumbnail(context, _faceFront, 'أمام', 'Front'),
                        const SizedBox(width: 8),
                        _angleThumbnail(context, _faceRight, 'يمين', 'Right'),
                        const SizedBox(width: 8),
                        _angleThumbnail(context, _faceLeft, 'شمال', 'Left'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _onContinue,
                      child: Text(AppStrings.continueBtn(context)),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _restartChallenge,
                      child: Text(
                        AppStrings.retake(context),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _angleThumbnail(
    BuildContext context,
    XFile? image,
    String arabicLabel,
    String englishLabel,
  ) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 54,
            height: 54,
            child: image == null
                ? const ColoredBox(color: Color(0xFFE5E7EB))
                : Image.file(File(image.path), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 3),
        Text(AppStrings.tr(context, ar: arabicLabel, en: englishLabel)),
      ],
    );
  }
}
