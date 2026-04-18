import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show InputImageRotation, InputImageRotationValue;
import 'package:permission_handler/permission_handler.dart';

import 'pose/mlkit_pose_estimator.dart';
import 'pose/pose_estimator.dart';
import 'pose/skeleton_smoother.dart';
import 'pose_painter.dart';
import 'analysis/joint_angles.dart';

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
  PoseEstimator? _estimator;
  final SkeletonSmoother _smoother = SkeletonSmoother();

  // Resolved after permission is granted (may differ from widget.cameras on
  // iOS, where availableCameras() returns empty before permission).
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  bool _busy = false;
  bool _initializing = false;

  // null = loading, non-null = show error UI
  String? _error;
  bool _errorNeedsSettings = false;

  List<Skeleton> _skeletons = const [];
  FrameMeta? _frameMeta;
  JointAngles? _angles;

  final List<DateTime> _frameTimes = [];
  int _fps = 0;
  int _latencyMs = 0;

  bool get _supportsPoseDetection =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap().catchError((e) {
      if (mounted) _setError('Startup error: $e');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _estimator?.close();
    super.dispose();
  }

  void _setError(String msg, {bool needsSettings = false}) {
    if (!mounted) return;
    setState(() {
      _error = msg;
      _errorNeedsSettings = needsSettings;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller = null;
      if (mounted) setState(() {});
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameras.isNotEmpty) _startCamera();
    }
  }

  Future<void> _bootstrap() async {
    if (!_supportsPoseDetection) {
      _setError('Pose detection requires iOS or Android.');
      return;
    }

    // Request permission first; on iOS the system dialog only appears once.
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied || status.isRestricted) {
      _setError(
        'Camera access is blocked. Enable it in Settings → Privacy → Camera.',
        needsSettings: true,
      );
      return;
    }
    if (!status.isGranted) {
      _setError('Camera permission denied.');
      return;
    }

    // On iOS, availableCameras() may return empty before permission is granted.
    // Re-query now that we have permission.
    var cameras = widget.cameras.isNotEmpty
        ? widget.cameras
        : await _queryCameras();

    if (cameras.isEmpty) {
      _setError('No cameras found on this device.');
      return;
    }
    _cameras = cameras;
    _cameraIndex = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (_cameraIndex < 0) _cameraIndex = 0;

    if (_estimator == null) {
      final estimator = MlKitPoseEstimator();
      try {
        await estimator.initialize();
      } catch (e) {
        _setError('Failed to initialize pose detector: $e');
        return;
      }
      _estimator = estimator;
    }

    await _startCamera();
  }

  Future<List<CameraDescription>> _queryCameras() async {
    try {
      return await availableCameras();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _startCamera() async {
    if (_initializing || _cameras.isEmpty) return;
    _initializing = true;
    try {
      final old = _controller;
      _controller = null;
      _busy = false;
      _skeletons = const [];
      _frameMeta = null;
      _smoother.reset();
      if (mounted) setState(() {});

      if (old != null) {
        try {
          if (old.value.isStreamingImages) await old.stopImageStream();
        } catch (_) {}
        await old.dispose();
      }

      final desc = _cameras[_cameraIndex];
      final controller = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      final ls = WidgetsBinding.instance.lifecycleState;
      if (!mounted ||
          ls == AppLifecycleState.inactive ||
          ls == AppLifecycleState.paused) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onCameraImage);
      if (mounted) setState(() {});
    } catch (e) {
      _setError('Camera error: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _initializing) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera();
  }

  Future<void> _copyAngles() async {
    final angles = _angles;
    if (_skeletons.isEmpty || angles == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No person detected to copy angles.')),
      );
      return;
    }
    final sk = _skeletons.first;
    final text = angles.toClipboardString(sk);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Joint angles copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onCameraImage(CameraImage image) async {
    final controller = _controller;
    final estimator = _estimator;
    if (_busy || estimator == null || controller == null) return;

    final meta = _buildFrameMeta(image, controller);
    if (meta == null) return;

    _busy = true;
    final frameStart = DateTime.now();
    try {
      final skeletons =
          await estimator.processFrame(image, controller.description, meta);

      final now = DateTime.now();
      _frameTimes.add(now);
      _frameTimes.removeWhere(
          (t) => now.difference(t) > const Duration(seconds: 1));

      if (!mounted) return;
      setState(() {
        _skeletons = _smoother.smooth(skeletons);
        _angles = _skeletons.isNotEmpty ? computeJointAngles(_skeletons.first) : null;
        _frameMeta = FrameMeta(
          imageSize: meta.imageSize,
          rotation: meta.rotation,
          lensDirection: meta.lensDirection,
        );
        _fps = _frameTimes.length;
        _latencyMs = now.difference(frameStart).inMilliseconds;
      });
    } catch (_) {
      // Drop frame.
    } finally {
      _busy = false;
    }
  }

  FrameMetadata? _buildFrameMeta(CameraImage image, CameraController ctl) {
    final camera = ctl.description;
    InputImageRotation? mlRot;
    if (Platform.isIOS) {
      mlRot = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    } else if (Platform.isAndroid) {
      var comp = _orientations[ctl.value.deviceOrientation];
      if (comp == null) return null;
      comp = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + comp) % 360
          : (camera.sensorOrientation - comp + 360) % 360;
      mlRot = InputImageRotationValue.fromRawValue(comp);
    }
    if (mlRot == null) return null;
    return FrameMetadata(
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: _toFrameRotation(mlRot),
      lensDirection: camera.lensDirection,
    );
  }

  static FrameRotation _toFrameRotation(InputImageRotation r) => switch (r) {
        InputImageRotation.rotation0deg => FrameRotation.deg0,
        InputImageRotation.rotation90deg => FrameRotation.deg90,
        InputImageRotation.rotation180deg => FrameRotation.deg180,
        InputImageRotation.rotation270deg => FrameRotation.deg270,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('SafeReps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyAngles,
            tooltip: 'Copy joint angles',
          ),
          if (_cameras.length > 1)
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              if (_errorNeedsSettings)
                FilledButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Open Settings'),
                )
              else
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _errorNeedsSettings = false;
                    });
                    _bootstrap().catchError((e) {
                      if (mounted) _setError('Startup error: $e');
                    });
                  },
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final meta = _frameMeta;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 1 / controller.value.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                if (meta != null)
                  CustomPaint(
                    painter: PosePainter(
                      skeletons: _skeletons,
                      meta: meta,
                      angles: _angles,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: _FpsHud(fps: _fps, latencyMs: _latencyMs),
        ),
      ],
    );
  }
}

class _FpsHud extends StatelessWidget {
  const _FpsHud({required this.fps, required this.latencyMs});

  final int fps;
  final int latencyMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$fps fps  ·  ${latencyMs}ms',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
