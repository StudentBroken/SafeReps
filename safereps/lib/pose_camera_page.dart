import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pose_painter.dart';

class PoseCameraPage extends StatefulWidget {
  const PoseCameraPage({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<PoseCameraPage> createState() => _PoseCameraPageState();
}

class _PoseCameraPageState extends State<PoseCameraPage>
    with WidgetsBindingObserver {
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _controller;
  PoseDetector? _detector;
  int _cameraIndex = 0;
  bool _busy = false;
  bool _initializing = false;
  String? _error;
  List<Pose> _poses = const [];
  Size? _imageSize;
  InputImageRotation? _rotation;

  bool get _supportsPoseDetection =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _detector?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _bootstrap() async {
    if (!_supportsPoseDetection) {
      setState(() => _error = 'Pose detection requires iOS or Android.');
      return;
    }
    if (widget.cameras.isEmpty) {
      setState(() => _error = 'No cameras available on this device.');
      return;
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _error = 'Camera permission denied.');
      return;
    }

    _detector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
    );

    // Prefer the front camera for early form-feedback testing.
    _cameraIndex = widget.cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (_cameraIndex < 0) _cameraIndex = 0;

    await _startCamera();
  }

  Future<void> _startCamera() async {
    if (_initializing) return;
    _initializing = true;

    try {
      // Tear down the previous controller before swapping references so the
      // build method never sees a disposed CameraController.
      final old = _controller;
      _controller = null;
      _busy = false;
      _poses = const [];
      _imageSize = null;
      _rotation = null;
      if (mounted) setState(() {});

      if (old != null) {
        try {
          if (old.value.isStreamingImages) await old.stopImageStream();
        } catch (_) {}
        await old.dispose();
      }

      final desc = widget.cameras[_cameraIndex];
      final controller = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onCameraImage);
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = 'Camera error: ${e.description ?? e.code}');
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2 || _initializing) return;
    _cameraIndex = (_cameraIndex + 1) % widget.cameras.length;
    await _startCamera();
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (_busy || _detector == null || _controller == null) return;
    final input = _toInputImage(image, _controller!.description);
    if (input == null) return;

    _busy = true;
    try {
      final poses = await _detector!.processImage(input);
      if (!mounted) return;
      setState(() {
        _poses = poses;
        _imageSize = input.metadata?.size;
        _rotation = input.metadata?.rotation;
      });
    } catch (_) {
      // Drop frame on detector error.
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    final controller = _controller;
    if (controller == null) return null;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    } else if (Platform.isAndroid) {
      var compensation = _orientations[controller.value.deviceOrientation];
      if (compensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        compensation = (camera.sensorOrientation + compensation) % 360;
      } else {
        compensation =
            (camera.sensorOrientation - compensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(compensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    if (image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('SafeReps · Pose Debug'),
        actions: [
          if (widget.cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: _switchCamera,
              tooltip: 'Switch camera',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final preview = CameraPreview(controller);
    final rotation = _rotation;
    final imageSize = _imageSize;

    return Center(
      child: AspectRatio(
        aspectRatio: 1 / controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            preview,
            if (rotation != null && imageSize != null)
              CustomPaint(
                painter: PosePainter(
                  poses: _poses,
                  imageSize: imageSize,
                  rotation: rotation,
                  cameraLensDirection: controller.description.lensDirection,
                ),
              ),
            Positioned(
              left: 12,
              bottom: 12,
              child: _PoseHud(poseCount: _poses.length),
            ),
          ],
        ),
      ),
    );
  }
}

class _PoseHud extends StatelessWidget {
  const _PoseHud({required this.poseCount});

  final int poseCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        poseCount == 0 ? 'No pose detected' : 'Tracking $poseCount pose(s)',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
