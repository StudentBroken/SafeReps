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
import 'analysis/exercise.dart';
import 'analysis/rep_counter.dart';
import 'models/session_model.dart';

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

  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  bool _busy = false;
  bool _initializing = false;

  String? _error;
  bool _errorNeedsSettings = false;

  List<Skeleton> _skeletons = const [];
  FrameMeta? _frameMeta;
  JointAngles? _angles;

  final List<DateTime> _frameTimes = [];
  int _fps = 0;
  int _latencyMs = 0;

  Exercise? _activeExercise;
  RepCounter? _repCounter;
  RepResult? _repResult;

  DateTime? _lastFullyInFrameTime;
  bool _isPoseValid = true;

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
    if (state == AppLifecycleState.paused) {
      final c = _controller;
      if (c == null || !c.value.isInitialized) return;
      _controller = null;
      if (mounted) setState(() {});
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameras.isNotEmpty && _controller == null) _startCamera();
    }
  }

  Future<void> _bootstrap() async {
    if (!_supportsPoseDetection) {
      _setError('Pose detection requires iOS or Android.');
      return;
    }

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
      if (!mounted || ls == AppLifecycleState.paused) {
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

  void _toggleExercise(Exercise exercise) {
    setState(() {
      if (_activeExercise == exercise) {
        _activeExercise = null;
        _repCounter = null;
        _repResult = null;
      } else {
        _activeExercise = exercise;
        _repCounter = RepCounter(exercise);
        _repResult = null;
      }
    });
  }

  void _resetReps() {
    _repCounter?.reset();
    if (mounted) setState(() => _repResult = null);
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

        // Check if limbs are in frame.
        if (_skeletons.isNotEmpty) {
          final isCurrentlyInFrame = _skeletons.first.isFullyInFrame(meta.imageSize);
          if (isCurrentlyInFrame) {
            _lastFullyInFrameTime = now;
            _isPoseValid = true;
          } else {
            final lastTime = _lastFullyInFrameTime;
            if (lastTime != null && now.difference(lastTime) > const Duration(seconds: 1)) {
              _isPoseValid = false;
            }
          }
        } else {
          // No skeleton visible at all.
          final lastTime = _lastFullyInFrameTime;
          if (lastTime != null && now.difference(lastTime) > const Duration(seconds: 1)) {
            _isPoseValid = false;
          }
        }

        final counter = _repCounter;
        final angles = _angles;
        if (counter != null && angles != null && _isPoseValid) {
          final prevReps = counter.reps;
          _repResult = counter.update(angles);
          if (counter.reps != prevReps && counter.lastRepDuration != null) {
            SessionScope.of(context).reportRepSpeed(counter.lastRepDuration);
          }
        }
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
        title: null,
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
      bottomNavigationBar: _ExercisePanel(
        activeExercise: _activeExercise,
        repResult: _repResult,
        onToggle: _toggleExercise,
        onReset: _resetReps,
      ),
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
                      isPoseValid: _isPoseValid,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!_isPoseValid && _skeletons.isNotEmpty)
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Keep all limbs in frame!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
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

// ── Exercise bottom panel ─────────────────────────────────────────────────────

class _ExercisePanel extends StatelessWidget {
  const _ExercisePanel({
    required this.activeExercise,
    required this.repResult,
    required this.onToggle,
    required this.onReset,
  });

  final Exercise? activeExercise;
  final RepResult? repResult;
  final ValueChanged<Exercise> onToggle;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.black87,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + bottomPadding),
      child: Row(
        children: [
          Expanded(
            child: _ExerciseTile(
              exercise: lateralRaise,
              isActive: activeExercise == lateralRaise,
              repResult: activeExercise == lateralRaise ? repResult : null,
              onTap: () => onToggle(lateralRaise),
              onReset: onReset,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ExerciseTile(
              exercise: bicepCurl,
              isActive: activeExercise == bicepCurl,
              repResult: activeExercise == bicepCurl ? repResult : null,
              onTap: () => onToggle(bicepCurl),
              onReset: onReset,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.isActive,
    required this.repResult,
    required this.onTap,
    required this.onReset,
  });

  final Exercise exercise;
  final bool isActive;
  final RepResult? repResult;
  final VoidCallback onTap;
  final VoidCallback onReset;

  double _progress() {
    final angle = repResult?.primaryAngle;
    if (angle == null) return 0;
    final inverted = exercise.topThreshold < exercise.bottomThreshold;
    if (inverted) {
      return ((angle - exercise.topThreshold) /
              (exercise.bottomThreshold - exercise.topThreshold))
          .clamp(0.0, 1.0);
    } else {
      return ((exercise.topThreshold - angle) /
              (exercise.topThreshold - exercise.bottomThreshold))
          .clamp(0.0, 1.0);
    }
  }

  String _phaseLabel(RepPhase phase) => switch (phase) {
        RepPhase.idle => 'get in position',
        RepPhase.top => 'ready',
        RepPhase.descending => '↑',
        RepPhase.bottom => 'hold',
        RepPhase.ascending => '↓',
      };

  @override
  Widget build(BuildContext context) {
    final reps = repResult?.totalReps ?? 0;
    final phase = repResult?.phase;
    final progress = _progress();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive ? Colors.green.shade900 : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.greenAccent : Colors.grey.shade700,
            width: isActive ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: isActive
            ? Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.greenAccent),
                        ),
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          exercise.name,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          '$reps',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                        if (phase != null)
                          Text(
                            _phaseLabel(phase),
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    color: Colors.white54,
                    onPressed: onReset,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.play_circle_outline,
                      color: Colors.white38, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      exercise.name,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── FPS HUD ───────────────────────────────────────────────────────────────────

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
