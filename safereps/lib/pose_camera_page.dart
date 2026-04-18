import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show InputImageRotation, InputImageRotationValue;
import 'package:permission_handler/permission_handler.dart';

import 'analysis/exercise.dart';
import 'analysis/joint_angles.dart';
import 'analysis/rep_counter.dart';
import 'pose/mlkit_pose_estimator.dart';
import 'pose/pose_estimator.dart';
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
  PoseEstimator? _estimator;
  int _cameraIndex = 0;
  bool _busy = false;
  bool _initializing = false;
  String? _error;

  List<SkeletonWithAngles> _results = const [];
  FrameMeta? _frameMeta;

  // Exercise tracking.
  Exercise _exercise = squat;
  late RepCounter _repCounter = RepCounter(_exercise);
  RepResult? _lastRepResult;

  // FPS tracking.
  final List<DateTime> _frameTimes = [];
  int _fps = 0;
  int _latencyMs = 0;

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
    _estimator?.close();
    super.dispose();
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
    final estimator = MlKitPoseEstimator();
    await estimator.initialize();
    _estimator = estimator;

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
      final old = _controller;
      _controller = null;
      _busy = false;
      _results = const [];
      _frameMeta = null;
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

  void _selectExercise(Exercise ex) {
    setState(() {
      _exercise = ex;
      _repCounter = RepCounter(ex);
      _lastRepResult = null;
    });
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

      final results = skeletons.map((sk) {
        final angles = computeJointAngles(sk);
        return SkeletonWithAngles(sk, angles);
      }).toList();

      RepResult? repResult;
      if (results.isNotEmpty) {
        repResult = _repCounter.update(results.first.angles);
      }

      final now = DateTime.now();
      _frameTimes.add(now);
      _frameTimes.removeWhere(
          (t) => now.difference(t) > const Duration(seconds: 1));

      if (!mounted) return;
      setState(() {
        _results = results;
        _frameMeta = FrameMeta(
          imageSize: meta.imageSize,
          rotation: meta.rotation,
          lensDirection: meta.lensDirection,
        );
        _lastRepResult = repResult;
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
        title: const Text('SafeReps · Pose Debug'),
        actions: [
          // Exercise picker.
          PopupMenuButton<Exercise>(
            icon: const Icon(Icons.fitness_center),
            tooltip: 'Select exercise',
            initialValue: _exercise,
            onSelected: _selectExercise,
            itemBuilder: (_) => builtInExercises
                .map((e) => PopupMenuItem(value: e, child: Text(e.name)))
                .toList(),
          ),
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
                      skeletons: _results.map((r) => r.skeleton).toList(),
                      meta: meta,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Overlay HUD panels.
        Positioned(
          left: 12,
          top: 12,
          child: _FpsHud(fps: _fps, latencyMs: _latencyMs),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _ExerciseHud(
            exercise: _exercise,
            repResult: _lastRepResult,
            onReset: () => setState(() {
              _repCounter.reset();
              _lastRepResult = null;
            }),
          ),
        ),
        if (_results.isNotEmpty)
          Positioned(
            left: 12,
            bottom: 12,
            child: _AngleHud(angles: _results.first.angles),
          ),
      ],
    );
  }
}

// ── Data carrier ──────────────────────────────────────────────────────────────

class SkeletonWithAngles {
  const SkeletonWithAngles(this.skeleton, this.angles);
  final Skeleton skeleton;
  final JointAngles angles;
}

// ── HUD widgets ───────────────────────────────────────────────────────────────

class _FpsHud extends StatelessWidget {
  const _FpsHud({required this.fps, required this.latencyMs});

  final int fps;
  final int latencyMs;

  @override
  Widget build(BuildContext context) {
    return _HudCard(
      child: Text(
        '$fps fps  ·  ${latencyMs}ms',
        style: const TextStyle(color: Colors.white70, fontSize: 11,
            fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _ExerciseHud extends StatelessWidget {
  const _ExerciseHud({
    required this.exercise,
    required this.repResult,
    required this.onReset,
  });

  final Exercise exercise;
  final RepResult? repResult;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final reps = repResult?.totalReps ?? 0;
    final phase = repResult?.phase ?? RepPhase.idle;
    return GestureDetector(
      onLongPress: onReset,
      child: _HudCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(exercise.name,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            Text(
              '$reps',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              _phaseLabel(phase),
              style: TextStyle(
                color: _phaseColor(phase),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            const Text('hold to reset',
                style: TextStyle(color: Colors.white30, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  static String _phaseLabel(RepPhase p) => switch (p) {
        RepPhase.idle => 'get in position',
        RepPhase.top => 'ready',
        RepPhase.descending => '▼ down',
        RepPhase.bottom => '● bottom',
        RepPhase.ascending => '▲ up',
      };

  static Color _phaseColor(RepPhase p) => switch (p) {
        RepPhase.idle => Colors.white38,
        RepPhase.top => Colors.greenAccent,
        RepPhase.descending => Colors.orangeAccent,
        RepPhase.bottom => Colors.cyanAccent,
        RepPhase.ascending => Colors.lightGreenAccent,
      };
}

class _AngleHud extends StatelessWidget {
  const _AngleHud({required this.angles});

  final JointAngles angles;

  @override
  Widget build(BuildContext context) {
    return _HudCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _angleRow('Knee', angles.avgKnee),
          _angleRow('Hip', angles.avgHip),
          _angleRow('Elbow', angles.avgElbow),
          _angleRow('Shoulder', angles.avgShoulder),
        ],
      ),
    );
  }

  static Widget _angleRow(String label, double? deg) {
    final text = deg != null ? '${deg.toStringAsFixed(0)}°' : '--';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          SizedBox(
            width: 36,
            child: Text(text,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
          ),
        ],
      ),
    );
  }
}

class _HudCard extends StatelessWidget {
  const _HudCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
