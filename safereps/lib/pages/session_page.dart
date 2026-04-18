import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show pi;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show InputImageRotation, InputImageRotationValue;

import '../analysis/exercise.dart';
import '../analysis/joint_angles.dart';
import '../analysis/rep_counter.dart';
import '../main.dart' show cameras;
import '../models/goals_model.dart';
import '../pose/mlkit_pose_estimator.dart';
import '../pose/pose_estimator.dart';
import '../pose/skeleton_smoother.dart';
import '../pose_painter.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

// ---------------------------------------------------------------------------
// Session phase state machine
// ---------------------------------------------------------------------------

enum _Phase { preview, getReady, active, rest, done }

// ---------------------------------------------------------------------------

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.goals});
  final GoalsModel goals;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage>
    with WidgetsBindingObserver {
  // ── Camera ────────────────────────────────────────────────────────────────
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _controller;
  PoseEstimator? _estimator;
  final _smoother = SkeletonSmoother();
  bool _busy = false;

  List<Skeleton> _skeletons = const [];
  FrameMeta? _frameMeta;
  JointAngles? _angles;

  // ── Session ───────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.preview;
  int _exerciseIndex = 0;
  int _setIndex = 0;

  RepCounter? _repCounter;
  RepResult? _repResult;

  int _previewCountdown = 5;
  int _getReadyCountdown = 3;
  int _restRemaining = 0;

  Timer? _timer;

  // Form / notification state
  bool _isPoseValid = true;
  DateTime? _lastFullyInFrameTime;
  DateTime? _lastRepTime;
  int _lastKnownReps = 0;
  String? _notification;
  Timer? _notificationTimer;

  ExerciseGoal get _currentGoal =>
      widget.goals.exercises[_exerciseIndex];

  double get _repProgress {
    final goal = _exerciseIndex < widget.goals.exercises.length
        ? _currentGoal.repsPerSet
        : 1;
    return ((_repResult?.totalReps ?? 0) / goal).clamp(0.0, 1.0);
  }

  Exercise get _currentExercise => builtInExercises.firstWhere(
        (e) => e.name == _currentGoal.name,
        orElse: () => builtInExercises.first,
      );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _startPreviewCountdown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _notificationTimer?.cancel();
    _controller?.dispose();
    _estimator?.close();
    super.dispose();
  }

  void _showNotification(String message) {
    _notificationTimer?.cancel();
    setState(() => _notification = message);
    _notificationTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _notification = null);
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
      _initCamera();
    }
  }

  // ── Camera setup ──────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    final avail =
        cameras.isNotEmpty ? cameras : await _queryCameras();
    if (avail.isEmpty || !mounted) return;

    if (_estimator == null) {
      final est = MlKitPoseEstimator();
      try {
        await est.initialize();
      } catch (_) {
        return;
      }
      _estimator = est;
    }

    final desc = avail.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => avail.first,
    );

    final controller = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onCameraImage);
      if (mounted) setState(() {});
    } catch (_) {
      controller.dispose();
    }
  }

  Future<List<CameraDescription>> _queryCameras() async {
    try {
      return await availableCameras();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    final controller = _controller;
    final estimator = _estimator;
    if (_busy || estimator == null || controller == null) return;
    if (_phase != _Phase.active) return;

    final meta = _buildFrameMeta(image, controller);
    if (meta == null) return;

    _busy = true;
    final prevIsPoseValid = _isPoseValid;
    final prevRepCount = _lastKnownReps;
    try {
      final skeletons =
          await estimator.processFrame(image, controller.description, meta);
      if (!mounted) return;

      final now = DateTime.now();
      bool newIsPoseValid = _isPoseValid;

      if (skeletons.isNotEmpty) {
        final inFrame = skeletons.first.isFullyInFrame(meta.imageSize);
        if (inFrame) {
          _lastFullyInFrameTime = now;
          newIsPoseValid = true;
        } else {
          final last = _lastFullyInFrameTime;
          if (last != null && now.difference(last) > const Duration(seconds: 1)) {
            newIsPoseValid = false;
          }
        }
      }

      setState(() {
        _skeletons = _smoother.smooth(skeletons);
        _angles = _skeletons.isNotEmpty
            ? computeJointAngles(_skeletons.first)
            : null;
        _frameMeta = FrameMeta(
          imageSize: meta.imageSize,
          rotation: meta.rotation,
          lensDirection: meta.lensDirection,
        );
        _isPoseValid = newIsPoseValid;
        if (_phase == _Phase.active) {
          final counter = _repCounter;
          final angles = _angles;
          if (counter != null && angles != null) {
            _repResult = counter.update(angles);
            _lastKnownReps = _repResult?.totalReps ?? 0;
            _checkSetComplete();
          }
        }
      });

      // Notifications (called after setState)
      if (_phase == _Phase.active) {
        if (!newIsPoseValid && prevIsPoseValid) {
          _showNotification('Keep all limbs in frame!');
        }
        final newReps = _repResult?.totalReps ?? 0;
        if (newReps > prevRepCount) {
          final repDuration = _lastRepTime != null
              ? now.difference(_lastRepTime!).inMilliseconds
              : 9999;
          if (repDuration < 800) {
            _showNotification('Slow down — control the movement');
          }
          _lastRepTime = now;
        }
      }
    } catch (_) {
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

  // ── Session flow ──────────────────────────────────────────────────────────

  void _startPreviewCountdown() {
    _previewCountdown = 5;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _previewCountdown--);
      if (_previewCountdown <= 0) {
        t.cancel();
        _startGetReady();
      }
    });
  }

  void _startGetReady() {
    _getReadyCountdown = 3;
    _timer?.cancel();
    setState(() => _phase = _Phase.getReady);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _getReadyCountdown--);
      if (_getReadyCountdown <= 0) {
        t.cancel();
        _startActive();
      }
    });
  }

  void _startActive() {
    _repResult = null;
    _repCounter = RepCounter(_currentExercise);
    setState(() => _phase = _Phase.active);
  }

  void _checkSetComplete() {
    final result = _repResult;
    if (result == null) return;
    if (result.totalReps >= _currentGoal.repsPerSet) {
      _advanceSession();
    }
  }

  void _advanceSession() {
    // Record completed reps in the model so dashboard updates live
    widget.goals.markSetComplete(_exerciseIndex, _currentGoal.repsPerSet);

    _repCounter = null;
    _repResult = null;
    _setIndex++;

    if (_setIndex >= widget.goals.sessionSets) {
      _setIndex = 0;
      _exerciseIndex++;
      if (_exerciseIndex >= widget.goals.exercises.length) {
        setState(() => _phase = _Phase.done);
        return;
      }
      _startRest(widget.goals.interExerciseRestSecs);
    } else {
      _startRest(widget.goals.interSetRestSecs);
    }
  }

  void _startRest(int seconds) {
    _restRemaining = seconds;
    _timer?.cancel();
    setState(() => _phase = _Phase.rest);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _restRemaining--);
      if (_restRemaining <= 0) {
        t.cancel();
        _startGetReady();
      }
    });
  }

  void _skipRest() {
    _timer?.cancel();
    _startGetReady();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final meta = _frameMeta;
    final cameraReady =
        controller != null && controller.value.isInitialized;
    final isActive = _phase == _Phase.active;
    final hasExercise = _exerciseIndex < widget.goals.exercises.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-screen camera (cover crop, no black bars) ─────────────
          if (cameraReady)
            Positioned.fill(
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.previewSize?.height ?? 1080,
                    height: controller.value.previewSize?.width ??
                        (1080 * controller.value.aspectRatio),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(controller),
                        if (meta != null)
                          CustomPaint(
                            painter: PosePainter(
                              skeletons: _skeletons,
                              meta: meta,
                              angles: isActive ? _angles : null,
                              isPoseValid: _isPoseValid,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),

          // ── Close (X) button — top right ───────────────────────────────
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: 100,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),

          // ── Active: progress ring island — top left ─────────────────────
          if (isActive && hasExercise)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ProgressIsland(
                    exerciseName: _currentGoal.name,
                    setIndex: _setIndex,
                    totalSets: widget.goals.sessionSets,
                    progress: _repProgress,
                  ),
                ),
              ),
            ),

          // ── Active: rep count pill — bottom floating ────────────────────
          if (isActive && hasExercise)
            Positioned(
              bottom: 0,
              left: 24,
              right: 24,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _RepCountPill(
                    reps: _repResult?.totalReps ?? 0,
                    goal: _currentGoal.repsPerSet,
                    exerciseName: _currentGoal.name,
                  ),
                ),
              ),
            ),

          // ── Notification banner — top slide, always mounted for smooth exit
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: AnimatedOpacity(
                  opacity: _notification != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                  child: AnimatedSlide(
                    offset: _notification != null
                        ? Offset.zero
                        : const Offset(0, -0.6),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    child: _NotificationBanner(message: _notification ?? ''),
                  ),
                ),
              ),
            ),
          ),

          // ── Preview overlay ─────────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset: _phase == _Phase.preview
                  ? Offset.zero
                  : const Offset(0, 1.5),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOut,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _PreviewSheet(
                    goals: widget.goals,
                    countdown: _previewCountdown,
                    onCancel: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),

          // ── Get ready overlay ───────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset: _phase == _Phase.getReady
                  ? Offset.zero
                  : const Offset(0, 1.5),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeInOut,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: _GetReadyCard(
                    exerciseName: hasExercise ? _currentGoal.name : '',
                    countdown: _getReadyCountdown,
                  ),
                ),
              ),
            ),
          ),

          // ── Rest overlay ────────────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset:
                  _phase == _Phase.rest ? Offset.zero : const Offset(0, 1.5),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeInOut,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _RestSheet(
                    secondsRemaining: _restRemaining,
                    nextLabel: hasExercise ? _currentGoal.name : null,
                    onSkip: _skipRest,
                  ),
                ),
              ),
            ),
          ),

          // ── Done overlay ────────────────────────────────────────────────
          if (_phase == _Phase.done)
            _DoneOverlay(
              goals: widget.goals,
              onFinish: () => Navigator.pop(context),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper
// ---------------------------------------------------------------------------

String _fmtSecs(int secs) {
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  final s = secs % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}

// ---------------------------------------------------------------------------
// Session preview sheet
// ---------------------------------------------------------------------------

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    required this.goals,
    required this.countdown,
    required this.onCancel,
  });

  final GoalsModel goals;
  final int countdown;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: AppColors.glassPinkTint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Session Preview',
            style: TextStyle(
                color: AppColors.textDark,
                fontSize: 18,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          ...goals.exercises.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.pink,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.fitness_center_rounded,
                        size: 16, color: AppColors.textDark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(e.name,
                        style: const TextStyle(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                  Text(
                    '${goals.sessionSets} × ${e.repsPerSet} reps',
                    style: const TextStyle(
                        color: AppColors.textMid, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  size: 13, color: AppColors.textLight),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${_fmtSecs(goals.interSetRestSecs)} between sets  ·  '
                  '${_fmtSecs(goals.interExerciseRestSecs)} between exercises',
                  style: const TextStyle(
                      color: AppColors.textLight, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.textMid)),
              ),
              // Countdown ring
              SizedBox(
                width: 58,
                height: 58,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: countdown / 5,
                      strokeWidth: 3.5,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.pinkBright),
                    ),
                    Text(
                      '$countdown',
                      style: const TextStyle(
                          color: AppColors.pinkBright,
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Get ready card
// ---------------------------------------------------------------------------

class _GetReadyCard extends StatelessWidget {
  const _GetReadyCard({
    required this.exerciseName,
    required this.countdown,
  });

  final String exerciseName;
  final int countdown;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: AppColors.glassPinkTint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Get Ready for',
            style: TextStyle(
                color: AppColors.textMid,
                fontSize: 14,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            exerciseName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.pinkBright,
                fontSize: 26,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          // Dot countdown: 3 dots, filled ones = remaining seconds
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final filled = i < countdown;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  width: filled ? 14 : 9,
                  height: filled ? 14 : 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? AppColors.pinkBright
                        : AppColors.pinkBright.withAlpha(55),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active HUD: progress ring island (top left)
// ---------------------------------------------------------------------------

class _ProgressIsland extends StatelessWidget {
  const _ProgressIsland({
    required this.exerciseName,
    required this.setIndex,
    required this.totalSets,
    required this.progress,
  });

  final String exerciseName;
  final int setIndex;
  final int totalSets;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pinkBright.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.pinkBright.withValues(alpha: 0.35),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: CustomPaint(
              painter: _MiniRingPainter(progress: progress),
              child: Center(
                child: Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            exerciseName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'Set ${setIndex + 1}/$totalSets',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  const _MiniRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 4;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white30
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniRingPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// Active HUD: rep count pill (bottom floating)
// ---------------------------------------------------------------------------

class _RepCountPill extends StatelessWidget {
  const _RepCountPill({
    required this.reps,
    required this.goal,
    required this.exerciseName,
  });

  final int reps;
  final int goal;
  final String exerciseName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.pinkBright.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: AppColors.pinkBright.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              exerciseName,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 1.5, height: 22, color: Colors.white38),
            const SizedBox(width: 16),
            Text(
              '$reps',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            Text(
              ' / $goal',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notification banner (top-slide, translucent red)
// ---------------------------------------------------------------------------

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xCCE8175A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8175A).withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rest sheet
// ---------------------------------------------------------------------------

class _RestSheet extends StatelessWidget {
  const _RestSheet({
    required this.secondsRemaining,
    required this.nextLabel,
    required this.onSkip,
  });

  final int secondsRemaining;
  final String? nextLabel;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: const Color(0x22C8E6C9), // soft green tint during rest
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Rest',
              style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            _fmtSecs(secondsRemaining),
            style: const TextStyle(
                color: AppColors.pinkBright,
                fontSize: 44,
                fontWeight: FontWeight.w800,
                height: 1),
          ),
          if (nextLabel != null) ...[
            const SizedBox(height: 8),
            Text('Next: $nextLabel',
                style: const TextStyle(
                    color: AppColors.textMid, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSkip,
              child: const Text('Skip Rest'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Done overlay
// ---------------------------------------------------------------------------

class _DoneOverlay extends StatelessWidget {
  const _DoneOverlay({required this.goals, required this.onFinish});

  final GoalsModel goals;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.pinkBright,
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 44),
              ),
              const SizedBox(height: 24),
              const Text(
                'Session Complete!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Great work 💪',
                  style: TextStyle(color: Colors.white60, fontSize: 15)),
              const SizedBox(height: 32),
              GlassCard(
                child: Column(
                  children: goals.exercises
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              Text('${e.totalGoal} reps',
                                  style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 14)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onFinish,
                  child: const Text('Finish'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
