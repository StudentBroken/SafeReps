import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show pi;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show InputImageRotation, InputImageRotationValue;

import '../analysis/exercise.dart';
import '../analysis/exercise_imu_profile.dart';
import '../analysis/joint_angles.dart';
import '../analysis/rep_counter.dart';
import '../analysis/rep_form_tracker.dart';
import '../main.dart' show cameras;
import '../models/coach_settings.dart';
import '../models/goals_model.dart';
import '../pose/mlkit_pose_estimator.dart';
import '../pose/pose_estimator.dart';
import '../pose/skeleton_smoother.dart';
import '../pose_painter.dart';
import '../services/ble_service.dart';
import '../services/voice_coach_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';

// ---------------------------------------------------------------------------
// Session phase state machine
// ---------------------------------------------------------------------------

enum _Phase { preview, imuCalibration, getReady, active, rest, done }

// ---------------------------------------------------------------------------
// Per-exercise form summary (accumulated across all sets/reps)
// ---------------------------------------------------------------------------

class _ExerciseSummary {
  _ExerciseSummary(this.name);

  final String name;
  final List<RepFormResult> repResults = [];

  bool get hasData => repResults.isNotEmpty;

  double get avgQuality => repResults.isEmpty
      ? 100.0
      : repResults.fold(0.0, (s, r) => s + r.quality) / repResults.length;

  bool get hadSustainedTremor => repResults.any((r) => r.sustainedTremor);
  bool get hadSustainedSwing => repResults.any((r) => r.sustainedSwing);
  bool get hadYawIssue => repResults.any((r) => r.yawViolated);
  bool get hadRollIssue => repResults.any((r) => r.rollViolated);
  bool get hadPitchIssue => repResults.any((r) => r.pitchViolated);

  List<String> get recommendations {
    final recs = <String>[];
    if (avgQuality < 70) {
      recs.add('Consider lighter weights for better control.');
    }
    if (hadSustainedTremor) {
      recs.add('Fatigue detected — rest more between sets.');
    }
    if (hadSustainedSwing) {
      recs.add('Slow down — control the movement on both phases.');
    }
    if (hadYawIssue) {
      recs.add('Keep your arm in the lateral plane — avoid reaching forward.');
    }
    if (hadRollIssue) {
      recs.add('Maintain forearm rotation through the lift.');
    }
    if (hadPitchIssue) {
      recs.add('Keep your forearm supinated throughout the curl.');
    }
    return recs;
  }

  /// Positive aspects — what went well.
  List<(String, IconData)> get goodAspects {
    if (!hasData) return [('Session completed!', Icons.check_circle_rounded)];
    final goods = <(String, IconData)>[];
    if (avgQuality >= 85) {
      goods.add(('Excellent form consistency', Icons.star_rounded));
    } else if (avgQuality >= 65) {
      goods.add(('Solid form overall', Icons.thumb_up_alt_rounded));
    }
    if (!hadSustainedTremor) {
      goods.add(('No fatigue tremors', Icons.battery_full_rounded));
    }
    if (!hadSustainedSwing) {
      goods.add(('Controlled movement pace', Icons.check_circle_outline_rounded));
    }
    if (!hadYawIssue) {
      goods.add(('Clean arm path', Icons.straighten_rounded));
    }
    return goods;
  }

  /// Negative aspects — issues detected.
  List<(String, IconData)> get issueAspects {
    final issues = <(String, IconData)>[];
    if (hadSustainedTremor) {
      issues.add(('Fatigue tremors detected', Icons.vibration_rounded));
    }
    if (hadSustainedSwing) {
      issues.add(('Excessive swing speed', Icons.speed_rounded));
    }
    if (hadYawIssue) {
      issues.add(('Arm drifted out of plane', Icons.rotate_left_rounded));
    }
    if (hadRollIssue) {
      issues.add(('Forearm rotation issue', Icons.rotate_right_rounded));
    }
    if (hadPitchIssue) {
      issues.add(('Supination loss', Icons.flip_rounded));
    }
    return issues;
  }
}

// ---------------------------------------------------------------------------

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.goals, this.ble});
  final GoalsModel goals;
  final BleService? ble;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> with WidgetsBindingObserver {
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

  // ── Voice coach ───────────────────────────────────────────────────────────
  late final VoiceCoachService _coach;
  // Per-category cooldowns — prevents one cue type blocking a totally different one.
  final Map<CueCategory, DateTime> _lastCueFiredAt = {};
  static const _correctionCooldown = Duration(milliseconds: 2000);
  static const _positiveCooldown   = Duration(milliseconds: 4000);
  // Arms-not-straight alert dedup
  DateTime? _armsNotStraightLastAt;

  // ROM tracking: min/max primary angle seen during the current rep
  double _repMinAngle = double.infinity;
  double _repMaxAngle = double.negativeInfinity;
  CueCategory? _pendingRomCue;

  // Last-reps motivation gate (fires once per set when ≤3 reps remain)
  bool _lastRepsMotivFired = false;

  // Form / notification state
  bool _isPoseValid = true;
  DateTime? _lastFullyInFrameTime;
  DateTime? _lastRepTime;
  int _lastKnownReps = 0;
  String? _notification;
  bool _notificationIsGood = false;
  Timer? _notificationTimer;

  // ── IMU calibration ───────────────────────────────────────────────────────
  bool _isTposeDetected = false;
  DateTime? _tPoseStableAt;
  bool _tPoseCalibrating = false; // zero sent, waiting 2 s before advancing

  // ── Form tracking (IMU) ───────────────────────────────────────────────────
  final _formTracker = RepFormTracker();
  DateTime? _lastBleTime;
  double _currentRepQuality = 100.0; // quality of last completed rep

  // Sustained-alert deduplication: reset each rep
  bool _tremorAlertShown = false;
  bool _swingAlertShown = false;

  // Fatigue override: set to (completedReps + 3) when fatigue detected
  int? _fatigueRepsTarget;

  // ── Session-level form data ───────────────────────────────────────────────
  late final List<_ExerciseSummary> _exerciseSummaries;
  bool _bleWasConnected = false;

  // ── Island triple-tap debug ───────────────────────────────────────────────
  int _islandTapCount = 0;
  DateTime? _islandTapLastAt;
  bool _showImuDebug = false;

  // ── IMU-gated rep counting ────────────────────────────────────────────────
  int _confirmedReps = 0;          // reps counted only after IMU confirms movement
  bool _imuRepConfirmed = false;   // IMU confirmed current rep's peak position
  bool _incompleteRepPending = false; // ML Kit counted a rep but IMU gate failed

  // ── Derived getters ───────────────────────────────────────────────────────

  ExerciseGoal get _currentGoal => widget.goals.exercises[_exerciseIndex];

  int get _effectiveRepsGoal =>
      _fatigueRepsTarget ??
      (_exerciseIndex < widget.goals.exercises.length
          ? _currentGoal.repsPerSet
          : 1);

  double get _repProgress =>
      (_confirmedReps / _effectiveRepsGoal).clamp(0.0, 1.0);



  Exercise get _currentExercise => builtInExercises.firstWhere(
    (e) => e.name == _currentGoal.name,
    orElse: () => builtInExercises.first,
  );

  bool get _bleConnected =>
      widget.ble != null &&
      widget.ble!.connectionState == BleConnectionState.connected;

  /// Ring value: form quality when BLE connected, set-progress otherwise.
  double get _ringProgress {
    if (!_bleConnected) return _repProgress;
    final phase = _repResult?.phase;
    if (phase == RepPhase.descending ||
        phase == RepPhase.bottom ||
        phase == RepPhase.ascending) {
      return _formTracker.currentQuality / 100.0;
    }
    return _currentRepQuality / 100.0;
  }

  /// IMU profile for the current exercise, with any per-goal overrides applied.
  ExerciseImuProfile get _currentImuProfile =>
      imuProfileForExercise(_currentGoal.name).copyWith(
        tremorThreshold: _currentGoal.tremorThreshold,
        swingThreshold: _currentGoal.swingThreshold,
      );

  /// Form intensity 0–1: max of tremor badness and swing badness (2.5× threshold = full bar).
  double get _formIntensity {
    if (!_bleConnected || _phase != _Phase.active) return 0.0;
    final data = widget.ble?.latestData;
    if (data == null) return 0.0;
    final profile = _currentImuProfile;
    final tremorBad = (data.tremor / (profile.tremorThreshold * 2.5)).clamp(0.0, 1.0);
    final swingBad = (data.swing / (profile.swingThreshold * 2.5)).clamp(0.0, 1.0);
    return tremorBad > swingBad ? tremorBad : swingBad;
  }

  /// Rep completion bar (0–1): ML-Kit angle-based + optional IMU pitch.
  double get _repCompletionProgress {
    final result = _repResult;
    if (result == null) return 0.0;
    final phase = result.phase;
    final angle = result.primaryAngle;
    final exercise = _currentExercise;
    final inverted = exercise.topThreshold < exercise.bottomThreshold;

    double mlProgress;
    if (angle == null) {
      mlProgress = switch (phase) {
        RepPhase.idle || RepPhase.top => 0.0,
        RepPhase.descending => 0.25,
        RepPhase.bottom => 0.5,
        RepPhase.ascending => 0.75,
      };
    } else if (inverted) {
      final range = exercise.bottomThreshold - exercise.topThreshold;
      mlProgress = switch (phase) {
        RepPhase.idle || RepPhase.top => 0.0,
        RepPhase.descending =>
          ((angle - exercise.topThreshold) / range * 0.5).clamp(0.0, 0.5),
        RepPhase.bottom => 0.5,
        RepPhase.ascending =>
          (0.5 + (1.0 - (angle - exercise.topThreshold) / range) * 0.5).clamp(
            0.5,
            1.0,
          ),
      };
    } else {
      final range = exercise.topThreshold - exercise.bottomThreshold;
      mlProgress = switch (phase) {
        RepPhase.idle || RepPhase.top => 0.0,
        RepPhase.descending =>
          ((exercise.topThreshold - angle) / range * 0.5).clamp(0.0, 0.5),
        RepPhase.bottom => 0.5,
        RepPhase.ascending =>
          (0.5 + (angle - exercise.bottomThreshold) / range * 0.5).clamp(
            0.5,
            1.0,
          ),
      };
    }

    // Lateral raise: blend 70% ML Kit + 30% IMU pitch.
    final bleData = widget.ble?.latestData;
    if (bleData != null && _currentGoal.name == 'Lateral Raise') {
      // After ZERO at T-pose: rest≈-90°, T-pose≈0°.
      final pitchProgress = ((bleData.pitch + 90) / 90).clamp(0.0, 1.0);
      return (mlProgress * 0.7 + pitchProgress * 0.3).clamp(0.0, 1.0);
    }
    return mlProgress;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _exerciseSummaries = widget.goals.exercises
        .map((e) => _ExerciseSummary(e.name))
        .toList();
    widget.ble?.addListener(_onBleData);
    _initCamera();
    _startPreviewCountdown();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Safe to use context here for InheritedWidget lookup.
    if (!_coachInitialized) {
      _coach = VoiceCoachService(CoachSettingsScope.of(context));
      _coachInitialized = true;
    }
  }

  bool _coachInitialized = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _notificationTimer?.cancel();
    _controller?.dispose();
    _estimator?.close();
    widget.ble?.removeListener(_onBleData);
    widget.ble?.stopImuStream();
    if (_coachInitialized) _coach.dispose();
    super.dispose();
  }

  void _showNotification(String message, {bool good = false}) {
    _notificationTimer?.cancel();
    setState(() {
      _notification = message;
      _notificationIsGood = good;
    });
    _notificationTimer = Timer(Duration(milliseconds: good ? 3500 : 2500), () {
      if (mounted) setState(() => _notification = null);
    });
  }

  /// Shows a brief high-priority overlay notification (used for live form alerts
  /// like "Straighten your arms!" that need to be unmissable).
  void _showQuickPopup(String message) {
    if (!mounted) return;
    _showNotification(message, good: false);
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
    final avail = cameras.isNotEmpty ? cameras : await _queryCameras();
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
    if (_phase != _Phase.active && _phase != _Phase.imuCalibration) return;

    final meta = _buildFrameMeta(image, controller);
    if (meta == null) return;

    _busy = true;
    final prevIsPoseValid = _isPoseValid;
    final prevRepCount = _lastKnownReps;
    // Capture before setState so post-setState check uses the start-of-frame value.
    final prevTposeStableAt = _tPoseStableAt;
    try {
      final skeletons = await estimator.processFrame(
        image,
        controller.description,
        meta,
      );
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
          if (last != null &&
              now.difference(last) > const Duration(seconds: 1)) {
            newIsPoseValid = false;
          }
        }
      }

      final smoothed = _smoother.smooth(skeletons);
      final angles = smoothed.isNotEmpty
          ? computeJointAngles(smoothed.first)
          : null;

      setState(() {
        _skeletons = smoothed;
        _angles = angles;
        _frameMeta = FrameMeta(
          imageSize: meta.imageSize,
          rotation: meta.rotation,
          lensDirection: meta.lensDirection,
        );
        _isPoseValid = newIsPoseValid;

        if (_phase == _Phase.imuCalibration && !_tPoseCalibrating) {
          final ls = angles?.leftShoulder;
          final rs = angles?.rightShoulder;
          final isTpose = ls != null && rs != null && ls > 75 && rs > 75;
          _isTposeDetected = isTpose;
          if (isTpose) {
            _tPoseStableAt ??= now;
          } else {
            _tPoseStableAt = null;
          }
        } else if (_phase == _Phase.active) {
          final counter = _repCounter;
          if (counter != null && angles != null) {
            final prevPhase = _repResult?.phase;
            _repResult = counter.update(angles);
            final newReps = _repResult?.totalReps ?? 0;
            final newPhase = _repResult?.phase;

            // Track angle extremes for post-rep ROM analysis.
            final primaryAngle = _repResult?.primaryAngle;
            if (primaryAngle != null) {
              if (primaryAngle < _repMinAngle) _repMinAngle = primaryAngle;
              if (primaryAngle > _repMaxAngle) _repMaxAngle = primaryAngle;
            }

            // Reset IMU gate when a new rep begins (top → descending).
            if (prevPhase == RepPhase.top &&
                newPhase == RepPhase.descending) {
              _imuRepConfirmed = false;
            }

            if (newReps > _lastKnownReps) {
              final imuOk = !_bleConnected || _imuRepConfirmed;
              if (imuOk) {
                _confirmedReps++;
                _pendingRomCue = _evaluateRomCue(_repMaxAngle, _repMinAngle);
                final repResult = _formTracker.finish();
                _currentRepQuality = repResult.quality;
                if (_exerciseIndex < _exerciseSummaries.length) {
                  _exerciseSummaries[_exerciseIndex].repResults.add(repResult);
                }
              } else {
                _incompleteRepPending = true;
              }
              _repMinAngle = double.infinity;
              _repMaxAngle = double.negativeInfinity;
              _formTracker.reset();
              _tremorAlertShown = false;
              _swingAlertShown = false;
            }
            _lastKnownReps = newReps;
            _checkSetComplete();
          }
        }
      });

      // IMU-gated rep: rep was blocked — notify user outside setState.
      if (_incompleteRepPending) {
        _incompleteRepPending = false;
        _showNotification('Raise higher — rep not counted');
      }

      // Trigger calibration completion outside setState (side-effects).
      if (_phase == _Phase.imuCalibration &&
          !_tPoseCalibrating &&
          prevTposeStableAt != null &&
          now.difference(prevTposeStableAt) >= const Duration(seconds: 1)) {
        setState(() => _tPoseCalibrating = true);
        widget.ble?.zero();
        Timer(const Duration(seconds: 2), () {
          if (mounted) _startGetReady();
        });
      }

      // Strategic coach cues + notifications
      if (_phase == _Phase.active) {
        if (!newIsPoseValid && prevIsPoseValid) {
          _showNotification('Keep all limbs in frame!');
        }
        final newReps = _repResult?.totalReps ?? 0;
        if (newReps > prevRepCount) {
          final repDuration = _lastRepTime != null
              ? now.difference(_lastRepTime!).inMilliseconds
              : 9999;
          bool correctionFired = false;

          // 1. Tempo — fires first; fastest tactile feedback.
          if (repDuration < 800) {
            _showNotification('Slow down — control the movement');
            if (_currentGoal.name.contains('Curl')) {
              _fireCoachCue(CueCategory.bicepTempo, correction: true);
            } else {
              _fireCoachCue(CueCategory.lateralTempo, correction: true);
            }
            correctionFired = true;
          }

          // 2. ROM correction — only when tempo was fine.
          if (!correctionFired) {
            final romCue = _pendingRomCue;
            _pendingRomCue = null;
            if (romCue != null) {
              _fireCoachCue(romCue, correction: true);
              correctionFired = true;
            }
          } else {
            _pendingRomCue = null;
          }

          // 3. Last-reps motivation — only at the very end of the set.
          if (!correctionFired) {
            final remaining = _effectiveRepsGoal - _confirmedReps;
            if (remaining > 0 && remaining <= 3 && !_lastRepsMotivFired) {
              _lastRepsMotivFired = true;
              if (_currentGoal.name.contains('Curl')) {
                _fireCoachCue(CueCategory.bicepLastRepsMotiv);
              } else {
                _fireCoachCue(CueCategory.lateralPositiveStruggle);
              }
            }
          }

      // ── Continuous per-frame form checks (outside rep-boundary events) ────
      if (_phase == _Phase.active && angles != null) {
        final isCurl = _currentGoal.name.contains('Curl');
        final repPhase = _repResult?.phase;

        // Bicep Curl: Form cues
        if (isCurl) {
          final elbowAngle = (angles.leftElbow != null && angles.rightElbow != null)
              ? (angles.leftElbow! + angles.rightElbow!) / 2
              : (angles.leftElbow ?? angles.rightElbow);

          if (elbowAngle != null) {
            final now2 = DateTime.now();
            final lastArm = _armsNotStraightLastAt;
            final canFire = lastArm == null ||
                now2.difference(lastArm) > const Duration(seconds: 4);

            if (canFire) {
              // 1. Extension check: at the hanging/start phase
              if ((repPhase == RepPhase.top || repPhase == RepPhase.idle) &&
                  elbowAngle < 140) {
                _armsNotStraightLastAt = now2;
                _showQuickPopup('Straighten your arms!');
                _fireCoachCue(CueCategory.bicepRomBottom, correction: true);
              }
              // 2. Contraction check: at the peak of the curl
              else if (repPhase == RepPhase.bottom && elbowAngle > 55) {
                _armsNotStraightLastAt = now2;
                _showQuickPopup('Curl higher!');
                _fireCoachCue(CueCategory.bicepRomTop, correction: true);
              }
            }
          }
        }

        // Lateral: if shoulder angle stays below 15° mid-rep the user isn't
        // raising high enough — give a live nudge.
        // Lateral Raise: Form cues
        if (!isCurl) {
          // Raise higher: during active lift (descending)
          if (repPhase == RepPhase.descending) {
            final ls = angles.leftShoulder;
            final rs = angles.rightShoulder;
            final shoulderAngle = (ls != null && rs != null)
                ? (ls + rs) / 2
                : (ls ?? rs);
            if (shoulderAngle != null && shoulderAngle < 15) {
              final now2 = DateTime.now();
              final lastArm = _armsNotStraightLastAt;
              if (lastArm == null ||
                  now2.difference(lastArm) > const Duration(seconds: 4)) {
                _armsNotStraightLastAt = now2;
                _showQuickPopup('Raise higher!');
                _fireCoachCue(CueCategory.lateralRom, correction: true);
              }
            }
          }

          // Straighten arms: during active lift (descending) or peak (bottom)
          if (repPhase == RepPhase.descending || repPhase == RepPhase.bottom) {
            final le = angles.leftElbow;
            final re = angles.rightElbow;
            final elbowAngle = (le != null && re != null)
                ? (le + re) / 2
                : (le ?? re);
            if (elbowAngle != null && elbowAngle < 140) {
              final now2 = DateTime.now();
              final lastArm = _armsNotStraightLastAt;
              if (lastArm == null ||
                  now2.difference(lastArm) > const Duration(seconds: 4)) {
                _armsNotStraightLastAt = now2;
                _showQuickPopup('Straighten your arms!');
                _fireCoachCue(CueCategory.lateralElbowWrist, correction: true);
              }
            }
          }
        }
      }

          _lastRepTime = now;
        }
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  // ── BLE form tracking ─────────────────────────────────────────────────────

  void _onBleData() {
    if (_phase != _Phase.active) return;
    final data = widget.ble?.latestData;
    if (data == null) return;

    final now = DateTime.now();
    final dt = _lastBleTime != null
        ? now.difference(_lastBleTime!).inMilliseconds / 1000.0
        : 0.0;
    _lastBleTime = now;

    if (dt <= 0 || dt >= 1.0) return;

    final profile = _currentImuProfile;
    _formTracker.update(data, dt, profile);
    _checkImuRepConfirmation(data);

    // Axis deviations — only during the active portion of a rep.
    final repPhase = _repResult?.phase;
    final repActive =
        repPhase == RepPhase.descending ||
        repPhase == RepPhase.bottom ||
        repPhase == RepPhase.ascending;
    if (repActive) {
      final isCurl = _currentGoal.name.contains('Curl');
      if (profile.yawLimit != null && data.yaw.abs() > profile.yawLimit!) {
        _formTracker.flagYawViolation(profile.axisDeductionPct);
        // Yaw = arm drifting out of plane → elbow/alignment cue
        _fireCoachCue(
          isCurl ? CueCategory.bicepElbows : CueCategory.lateralElbowWrist,
          correction: true,
        );
      }
      if (profile.rollLimit != null && data.roll.abs() > profile.rollLimit!) {
        _formTracker.flagRollViolation(profile.axisDeductionPct);
        // Roll = forearm/wrist rotation → shoulder/wrist cue
        _fireCoachCue(
          isCurl ? CueCategory.bicepShoulderWrist : CueCategory.lateralShoulderTrap,
          correction: true,
        );
      }
      if (profile.pitchDeviationLimit != null &&
          data.pitch.abs() > profile.pitchDeviationLimit!) {
        _formTracker.flagPitchViolation(profile.axisDeductionPct);
        // Pitch deviation = elbow drift (curl) or shoulder shrug (lateral)
        _fireCoachCue(
          isCurl ? CueCategory.bicepElbows : CueCategory.lateralShoulderTrap,
          correction: true,
        );
      }
    }

    // Sustained-tremor alert (fires once per rep when threshold first crossed).
    if (_formTracker.tremorSustained && !_tremorAlertShown) {
      _tremorAlertShown = true;
      _showNotification('Tremor detected — control your movement');
      final isCurl = _currentGoal.name.contains('Curl');
      // Body/stability cue (existing)
      _fireCoachCue(
        isCurl ? CueCategory.bicepBackBody : CueCategory.lateralBodySwing,
        correction: true,
      );
      // Generic form correction fires separately — different category, own cooldown
      _fireCoachCue(CueCategory.genericFormCorrection, correction: true);
      // Motivation to push through the last reps
      _fireCoachCue(
        isCurl ? CueCategory.bicepLastRepsMotiv : CueCategory.lateralPositiveStruggle,
      );
      _checkFatigue();
    }

    // Sustained-swing alert.
    if (_formTracker.swingSustained && !_swingAlertShown) {
      _swingAlertShown = true;
      _showNotification('Reduce your swing speed');
      final isCurl = _currentGoal.name.contains('Curl');
      _fireCoachCue(
        isCurl ? CueCategory.bicepBackBody : CueCategory.lateralBodySwing,
        correction: true,
      );
      // Also fire a generic form correction on a separate cooldown
      _fireCoachCue(CueCategory.genericFormCorrection, correction: true);
    }

    if (mounted) setState(() {});
  }

  // ── Voice coach helpers ───────────────────────────────────────────────────

  /// Play a correction cue, respecting a cooldown to avoid spamming.
  void _fireCoachCue(CueCategory cat, {bool correction = false}) {
    final now = DateTime.now();
    final cooldown = correction ? _correctionCooldown : _positiveCooldown;
    final last = _lastCueFiredAt[cat];
    if (last != null && now.difference(last) < cooldown) return;
    _lastCueFiredAt[cat] = now;
    if (correction) {
      _coach.playMandatory(cat);
    } else {
      _coach.play(cat);
    }
  }

  void _onIslandTap() {
    final now = DateTime.now();
    final last = _islandTapLastAt;
    if (last == null || now.difference(last) > const Duration(milliseconds: 600)) {
      _islandTapCount = 1;
    } else {
      _islandTapCount++;
    }
    _islandTapLastAt = now;
    if (_islandTapCount >= 3) {
      _islandTapCount = 0;
      setState(() => _showImuDebug = !_showImuDebug);
    }
  }

  void _checkFatigue() {
    if (_fatigueRepsTarget != null) return;
    final completed = _confirmedReps;
    final remaining = _currentGoal.repsPerSet - completed;
    if (remaining >= 4) {
      final stopAt = completed + 3;
      setState(() => _fatigueRepsTarget = stopAt);
      _showNotification(
        'Fatigue detected — finishing at $stopAt reps',
        good: true,
      );
    }
  }

  /// Returns a ROM correction cue if the rep's angle range was insufficient.
  /// [maxAngle] and [minAngle] are the extremes seen during the rep.
  CueCategory? _evaluateRomCue(double maxAngle, double minAngle) {
    if (maxAngle == double.negativeInfinity || minAngle == double.infinity) {
      return null;
    }
    final name = _currentGoal.name;
    if (name.contains('Curl')) {
      // Bicep curl: top ~155° (curled), bottom ~25° (extended)
      if (maxAngle < 140) return CueCategory.bicepRomTop;    // didn't curl enough
      if (minAngle > 40)  return CueCategory.bicepRomBottom; // didn't extend enough
    } else {
      // Lateral raise: top ~25° (shoulder height), bottom ~80° (at side)
      if (minAngle > 40) return CueCategory.lateralRom; // didn't raise high enough
    }
    return null;
  }

  /// Sets _imuRepConfirmed when pitch confirms the rep peak was reached.
  void _checkImuRepConfirmation(ImuData data) {
    if (_imuRepConfirmed) return;
    final repPhase = _repResult?.phase;
    if (repPhase != RepPhase.bottom && repPhase != RepPhase.ascending) return;
    if (_currentGoal.name == 'Lateral Raise') {
      // After ZERO at T-pose: rest≈-90°, T-pose≈0°. Require pitch > -45° (halfway up).
      if (data.pitch > -45) _imuRepConfirmed = true;
    } else {
      _imuRepConfirmed = true;
    }
  }

  // ── Frame meta helpers ────────────────────────────────────────────────────

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
        if (_bleConnected) {
          _startImuCalibration();
        } else {
          _startGetReady();
        }
      }
    });
  }

  void _startImuCalibration() {
    _isTposeDetected = false;
    _tPoseStableAt = null;
    _tPoseCalibrating = false;
    setState(() => _phase = _Phase.imuCalibration);
  }

  void _startGetReady() {
    _getReadyCountdown = 3;
    _timer?.cancel();
    setState(() => _phase = _Phase.getReady);
    // Fire a session-start cue
    _coach.playMandatory(CueCategory.start);
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
    _formTracker.reset();
    _currentRepQuality = 100.0;
    _lastKnownReps = 0;
    _lastBleTime = null;
    _tremorAlertShown = false;
    _swingAlertShown = false;
    _fatigueRepsTarget = null;
    _confirmedReps = 0;
    _imuRepConfirmed = false;
    _incompleteRepPending = false;
    _repMinAngle = double.infinity;
    _repMaxAngle = double.negativeInfinity;
    _pendingRomCue = null;
    _lastRepsMotivFired = false;
    _lastCueFiredAt.clear();
    if (_bleConnected) _bleWasConnected = true;
    setState(() => _phase = _Phase.active);
    widget.ble?.startImuStream();
  }

  void _checkSetComplete() {
    if (_confirmedReps >= _effectiveRepsGoal) {
      _advanceSession();
    }
  }

  void _advanceSession() {
    widget.goals.markSetComplete(_exerciseIndex, _currentGoal.repsPerSet);

    _repCounter = null;
    _repResult = null;
    _setIndex++;

    if (_setIndex >= widget.goals.sessionSets) {
      _setIndex = 0;
      _exerciseIndex++;
      if (_exerciseIndex >= widget.goals.exercises.length) {
        widget.ble?.stopImuStream();
        // Session complete
        _coach.playMandatory(CueCategory.finishCongrats);
        setState(() => _phase = _Phase.done);
        return;
      }
      // Exercise complete (not final)
      _coach.playMandatory(CueCategory.finishCongrats);
      _startRest(widget.goals.interExerciseRestSecs);
    } else {
      // Set complete
      _coach.playMandatory(CueCategory.finishCongrats);
      _startRest(widget.goals.interSetRestSecs);
    }
  }

  void _startRest(int seconds) {
    widget.ble?.stopImuStream();
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
    final cameraReady = controller != null && controller.value.isInitialized;
    final isActive = _phase == _Phase.active;
    final hasExercise = _exerciseIndex < widget.goals.exercises.length;

    // Hold progress for T-pose calibration ring (0–1 over 1 second).
    final tposeHold = (_tPoseStableAt != null && !_tPoseCalibrating)
        ? (DateTime.now().difference(_tPoseStableAt!).inMilliseconds / 1000.0)
              .clamp(0.0, 1.0)
        : (_tPoseCalibrating ? 1.0 : 0.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-screen camera ─────────────
          if (cameraReady)
            Positioned.fill(
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.previewSize?.height ?? 1080,
                    height:
                        controller.value.previewSize?.width ??
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

          // ── IMU calibration overlay ────────────────────────────────────
          if (_phase == _Phase.imuCalibration)
            _TposeCalibrationOverlay(
              isTposeDetected: _isTposeDetected,
              holdProgress: tposeHold,
              calibrated: _tPoseCalibrating,
            ),

          // ── Close (X) button ───────────────────────────────
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
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),

          // ── Audio debug button ──────────────────────────────────────────
          if (_coachInitialized)
            Positioned(
              top: 0,
              right: 60,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GlassCard(
                    padding: EdgeInsets.zero,
                    borderRadius: 100,
                    child: IconButton(
                      tooltip: 'Test audio',
                      icon: const Icon(
                        Icons.volume_up_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      onPressed: () {
                        _coach.playMandatory(CueCategory.start);
                      },
                    ),
                  ),
                ),
              ),
            ),

          // ── Active: progress ring island (triple-tap → IMU debug) ──
          if (isActive && hasExercise)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GestureDetector(
                    onTap: _onIslandTap,
                    behavior: HitTestBehavior.opaque,
                    child: _ProgressIsland(
                      exerciseName: _currentGoal.name,
                      setIndex: _setIndex,
                      totalSets: widget.goals.sessionSets,
                      progress: _ringProgress,
                      isFormMode: _bleConnected,
                    ),
                  ),
                ),
              ),
            ),

          // ── IMU debug overlay (triple-tap island to toggle) ────
          if (_showImuDebug && _bleConnected)
            Positioned(
              top: 130,
              left: 12,
              child: SafeArea(
                child: _ImuDebugPanel(ble: widget.ble!),
              ),
            ),

          // ── Active: form intensity bar (right side, BLE only) ──
          if (isActive && _bleConnected)
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: SafeArea(
                  child: _FormIntensityBar(intensity: _formIntensity),
                ),
              ),
            ),

          // ── Active: rep count pill + completion bar ────────────
          if (isActive && hasExercise)
            Positioned(
              bottom: 0,
              left: 24,
              right: 24,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RepCompletionBar(progress: _repCompletionProgress),
                      const SizedBox(height: 8),
                      _RepCountPill(
                        reps: _confirmedReps,
                        goal: _effectiveRepsGoal,
                        exerciseName: _currentGoal.name,
                        fatigue: _fatigueRepsTarget != null,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Notification banner ─────────────────────
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
                    child: _NotificationBanner(
                      message: _notification ?? '',
                      isGood: _notificationIsGood,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Caption overlay ─────────────────────────────────────────────
          if (_coachInitialized)
            ListenableBuilder(
              listenable: _coach,
              builder: (context, _) {
                final settings = CoachSettingsScope.of(context);
                final caption = _coach.lastCaption;
                final show = settings.captions && caption != null && isActive;
                final primary = Theme.of(context).colorScheme.primary;
                return Positioned(
                  bottom: 104,
                  left: 20,
                  right: 20,
                  child: AnimatedOpacity(
                    opacity: show ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 350),
                    child: AnimatedSlide(
                      offset: show ? Offset.zero : const Offset(0, 0.3),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 1,
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left accent bar
                                  Container(
                                    width: 3,
                                    decoration: BoxDecoration(
                                      color: primary,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(14),
                                        bottomLeft: Radius.circular(14),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      child: Text(
                                        caption ?? '',
                                        textAlign: TextAlign.left,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: settings.captionSize,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                          letterSpacing: 0.1,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 8,
                                              color: Colors.black.withValues(alpha: 0.6),
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),


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
              offset: _phase == _Phase.rest
                  ? Offset.zero
                  : const Offset(0, 1.5),
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
              summaries: _exerciseSummaries,
              bleWasConnected: _bleWasConnected,
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
// T-pose calibration overlay
// ---------------------------------------------------------------------------

class _TposeCalibrationOverlay extends StatelessWidget {
  const _TposeCalibrationOverlay({
    required this.isTposeDetected,
    required this.holdProgress,
    required this.calibrated,
  });

  final bool isTposeDetected;
  final double holdProgress;
  final bool calibrated;

  @override
  Widget build(BuildContext context) {
    final Color silhouetteColor = calibrated
        ? const Color(0xFF4CAF50)
        : isTposeDetected
        ? const Color(0xFF4CAF50)
        : Colors.white54;

    return Container(
      color: Colors.black54,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Silhouette - positioned at the bottom, slightly oversized
          Positioned(
            left: 0,
            right: 0,
            bottom: -60, // Nudge further down
            child: Transform.scale(
              scale: 1.45, // Marginally smaller
              alignment: Alignment.bottomCenter,
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  silhouetteColor.withValues(alpha: 0.4),
                  BlendMode.srcATop,
                ),
                child: Image.asset(
                  'assets/calibration/calib_image.webp',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // Content overlay
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 48, 28, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      calibrated
                          ? 'Calibrated! Grab your weights…'
                          : isTposeDetected
                          ? 'Hold still…'
                          : 'Strike a T-pose to calibrate',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 6,
                        child: LinearProgressIndicator(
                          value: holdProgress,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            calibrated
                                ? const Color(0xFF4CAF50)
                                : silhouetteColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return GlassCard(
      tint: themeColors.glassTint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session Preview',
            style: TextStyle(
              color: themeColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
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
                      color: themeColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      size: 16,
                      color: themeColors.textDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.name,
                      style: TextStyle(
                        color: themeColors.textDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Text(
                    '${goals.sessionSets} × ${e.repsPerSet} reps',
                    style: TextStyle(color: themeColors.textMid, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.timer_outlined,
                size: 13,
                color: themeColors.textLight,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${_fmtSecs(goals.interSetRestSecs)} between sets  ·  '
                  '${_fmtSecs(goals.interExerciseRestSecs)} between exercises',
                  style: TextStyle(color: themeColors.textLight, fontSize: 11),
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
                child: Text(
                  'Cancel',
                  style: TextStyle(color: themeColors.textMid),
                ),
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
                      valueColor: AlwaysStoppedAnimation<Color>(primary),
                    ),
                    Text(
                      '$countdown',
                      style: TextStyle(
                        color: primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
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
  const _GetReadyCard({required this.exerciseName, required this.countdown});

  final String exerciseName;
  final int countdown;

  @override
  Widget build(BuildContext context) {
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return GlassCard(
      tint: themeColors.glassTint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Get Ready for',
            style: TextStyle(
              color: themeColors.textMid,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            exerciseName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: primary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
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
                    color: filled ? primary : primary.withValues(alpha: 0.2),
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
    required this.isFormMode,
  });

  final String exerciseName;
  final int setIndex;
  final int totalSets;
  final double
  progress; // 0–1; form quality when isFormMode, set progress otherwise
  final bool isFormMode;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
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
          if (isFormMode) ...[
            const SizedBox(height: 2),
            const Text(
              'Form',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
// Active HUD: rep completion bar
// ---------------------------------------------------------------------------

class _RepCompletionBar extends StatelessWidget {
  const _RepCompletionBar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            width: constraints.maxWidth,
            child: Stack(
              children: [
                Container(color: Colors.white24),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CAF50),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(4),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Active HUD: rep count pill (bottom floating)
// ---------------------------------------------------------------------------

class _RepCountPill extends StatelessWidget {
  const _RepCountPill({
    required this.reps,
    required this.goal,
    required this.exerciseName,
    this.fatigue = false,
  });

  final int reps;
  final int goal;
  final String exerciseName;
  final bool fatigue; // true when fatigue override is active

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bgColor = fatigue
        ? const Color(0xEB7B5200) // amber-tinted when fatigued
        : primary.withValues(alpha: 0.92);

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(100),
          boxShadow: [
            BoxShadow(
              color: (fatigue ? const Color(0xFFFFA000) : primary).withValues(
                alpha: 0.4,
              ),
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
              style: TextStyle(
                color: fatigue ? const Color(0xFFFFA000) : Colors.white60,
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
// Notification banner
// ---------------------------------------------------------------------------

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({required this.message, this.isGood = false});
  final String message;
  final bool isGood;

  @override
  Widget build(BuildContext context) {
    final bgColor = isGood ? const Color(0xCC2E7D32) : const Color(0xCCE8175A);
    final glowColor = isGood
        ? const Color(0xFF2E7D32)
        : const Color(0xFFE8175A);
    final icon = isGood
        ? Icons.check_circle_outline_rounded
        : Icons.warning_amber_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.3),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
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
    final themeColors = AppTheme.colors(context);
    final primary = Theme.of(context).colorScheme.primary;

    return GlassCard(
      tint: const Color(0x22C8E6C9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Rest',
            style: TextStyle(
              color: themeColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _fmtSecs(secondsRemaining),
            style: TextStyle(
              color: primary,
              fontSize: 44,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          if (nextLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              'Next: $nextLabel',
              style: TextStyle(color: themeColors.textMid, fontSize: 13),
            ),
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
// Done overlay — session report
// ---------------------------------------------------------------------------

Color _qualityColor(double q) {
  if (q >= 85) return const Color(0xFF4CAF50);
  if (q >= 65) return const Color(0xFFFFA000);
  return const Color(0xFFE53935);
}

String _qualityLabel(double q) {
  if (q >= 90) return 'Excellent';
  if (q >= 75) return 'Good';
  if (q >= 60) return 'Fair';
  return 'Keep practicing';
}

class _DoneOverlay extends StatefulWidget {
  const _DoneOverlay({
    required this.summaries,
    required this.bleWasConnected,
    required this.onFinish,
  });

  final List<_ExerciseSummary> summaries;
  final bool bleWasConnected;
  final VoidCallback onFinish;

  @override
  State<_DoneOverlay> createState() => _DoneOverlayState();
}

class _DoneOverlayState extends State<_DoneOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  double get _overallQuality {
    final withData = widget.summaries.where((s) => s.hasData).toList();
    if (withData.isEmpty) return 100.0;
    return withData.fold(0.0, (s, e) => s + e.avgQuality) / withData.length;
  }

  IconData _faceIcon(double q) {
    if (q >= 85) return Icons.sentiment_very_satisfied_rounded;
    if (q >= 65) return Icons.sentiment_satisfied_rounded;
    if (q >= 45) return Icons.sentiment_neutral_rounded;
    return Icons.sentiment_very_dissatisfied_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final hasFormData =
        widget.bleWasConnected && widget.summaries.any((s) => s.hasData);
    final overallQ = _overallQuality;
    final faceColor =
        hasFormData ? _qualityColor(overallQ) : AppColors.pinkBright;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          color: AppColors.background,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          hasFormData
                              ? _faceIcon(overallQ)
                              : Icons.sentiment_very_satisfied_rounded,
                          size: 84,
                          color: faceColor,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Session Complete!',
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (hasFormData) ...[
                          Text(
                            '${overallQ.round()}%  ·  ${_qualityLabel(overallQ)}',
                            style: TextStyle(
                              color: faceColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Overall form quality',
                            style: TextStyle(
                                color: AppColors.textLight, fontSize: 12),
                          ),
                        ] else
                          const Text(
                            'Great work today!',
                            style: TextStyle(
                                color: AppColors.textMid, fontSize: 15),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Per-exercise cards ──────────────────────────────────
                  ...widget.summaries.map(
                    (s) => _ExerciseReportCard(
                      summary: s,
                      showFormData: widget.bleWasConnected,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Finish ──────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: widget.onFinish,
                      child: const Text('Finish'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseReportCard extends StatefulWidget {
  const _ExerciseReportCard({
    required this.summary,
    required this.showFormData,
  });

  final _ExerciseSummary summary;
  final bool showFormData;

  @override
  State<_ExerciseReportCard> createState() => _ExerciseReportCardState();
}

class _ExerciseReportCardState extends State<_ExerciseReportCard> {
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    final hasForm = widget.showFormData && widget.summary.hasData;
    final q = widget.summary.avgQuality;
    final recs = widget.summary.recommendations;
    final goods = hasForm ? widget.summary.goodAspects : <(String, IconData)>[];
    final issues = hasForm ? widget.summary.issueAspects : <(String, IconData)>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exercise name + quality badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.summary.name,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hasForm)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _qualityColor(q).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _qualityColor(q).withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      '${q.round()}%  ${_qualityLabel(q)}',
                      style: TextStyle(
                        color: _qualityColor(q),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Text(
                    '${widget.summary.repResults.length} reps',
                    style: const TextStyle(
                        color: AppColors.textMid, fontSize: 13),
                  ),
              ],
            ),

            // Quality bar
            if (hasForm) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    children: [
                      Container(color: Colors.black.withAlpha(20)),
                      FractionallySizedBox(
                        widthFactor: (q / 100).clamp(0.0, 1.0),
                        child: Container(color: _qualityColor(q)),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Advanced toggle + per-rep breakdown
            if (hasForm && widget.summary.repResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Advanced',
                      style: TextStyle(
                        color: AppColors.textLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: _showAdvanced ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _showAdvanced
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PER REP',
                              style: TextStyle(
                                color: AppColors.textLight,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...widget.summary.repResults.asMap().entries.map((e) {
                              final idx = e.key;
                              final rep = e.value;
                              final repQ = rep.quality;
                              final flags = <IconData>[
                                if (rep.sustainedTremor) Icons.vibration_rounded,
                                if (rep.sustainedSwing) Icons.speed_rounded,
                                if (rep.yawViolated) Icons.rotate_left_rounded,
                                if (rep.rollViolated) Icons.rotate_right_rounded,
                                if (rep.pitchViolated) Icons.flip_rounded,
                              ];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    // Rep number
                                    SizedBox(
                                      width: 38,
                                      child: Text(
                                        'Rep ${idx + 1}',
                                        style: const TextStyle(
                                          color: AppColors.textLight,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    // Quality dot
                                    Container(
                                      width: 32,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: _qualityColor(repQ)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: _qualityColor(repQ)
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${repQ.round()}',
                                          style: TextStyle(
                                            color: _qualityColor(repQ),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Issue flags
                                    if (flags.isEmpty)
                                      const Text(
                                        'Clean',
                                        style: TextStyle(
                                          color: Color(0xFF2E7D32),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    else
                                      Wrap(
                                        spacing: 4,
                                        children: flags
                                            .map((icon) => Icon(
                                                  icon,
                                                  size: 13,
                                                  color: const Color(0xFFBF360C),
                                                ))
                                            .toList(),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],

            // ── What went well ───────────────────────────────────
            if (hasForm && goods.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionLabel(
                label: 'What went well',
                icon: Icons.sentiment_satisfied_alt_rounded,
                color: const Color(0xFF2E7D32),
              ),
              const SizedBox(height: 6),
              ...goods.map((a) => _AspectRow(label: a.$1, isGood: true)),
            ],

            // ── Needs improvement ────────────────────────────────
            if (hasForm && issues.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SectionLabel(
                label: 'Needs improvement',
                icon: Icons.sentiment_dissatisfied_rounded,
                color: const Color(0xFFBF360C),
              ),
              const SizedBox(height: 6),
              ...issues.map((a) => _AspectRow(label: a.$1, isGood: false)),
            ],

            // ── How to improve ───────────────────────────────────
            if (hasForm && recs.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0x12F57C00),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x40F57C00)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded,
                            size: 15, color: Color(0xFFF57C00)),
                        SizedBox(width: 6),
                        Text(
                          'How to improve',
                          style: TextStyle(
                            color: Color(0xFFF57C00),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...recs.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '•  ',
                              style: TextStyle(
                                color: Color(0xFFF57C00),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                r,
                                style: const TextStyle(
                                  color: AppColors.textDark,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form intensity pill (right-side live feedback)
// ---------------------------------------------------------------------------

class _FormIntensityBar extends StatelessWidget {
  const _FormIntensityBar({required this.intensity});
  final double intensity; // 0–1

  static Color _colorFor(double t) {
    if (t < 0.5) {
      return Color.lerp(const Color(0xFF4CAF50), const Color(0xFFFFC107), t * 2)!;
    } else {
      return Color.lerp(const Color(0xFFFFC107), const Color(0xFFE53935), (t - 0.5) * 2)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(intensity.clamp(0.0, 1.0));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 14,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(100),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.icon,
    required this.color,
  });
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class _AspectRow extends StatelessWidget {
  const _AspectRow({required this.label, required this.isGood});
  final String label;
  final bool isGood;

  @override
  Widget build(BuildContext context) {
    final face = isGood
        ? Icons.sentiment_satisfied_alt_rounded
        : Icons.sentiment_dissatisfied_rounded;
    final color =
        isGood ? const Color(0xFF2E7D32) : const Color(0xFFBF360C);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(face, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// IMU debug panel (triple-tap island to toggle)
// ---------------------------------------------------------------------------

class _ImuDebugPanel extends StatelessWidget {
  const _ImuDebugPanel({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final data = ble.latestData;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, fontFamily: 'monospace')),
            ],
          ),
        );

    String f(double? v, {int d = 2}) =>
        v == null ? '—' : v.toStringAsFixed(d);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('IMU DEBUG',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 6),
          if (data == null)
            const Text('No data', style: TextStyle(color: Colors.white38, fontSize: 10))
          else ...[
            row('Yaw',    '${f(data.yaw)}°'),
            row('Pitch',  '${f(data.pitch)}°'),
            row('Roll',   '${f(data.roll)}°'),
            const SizedBox(height: 4),
            row('Tremor', '${f(data.tremor, d: 4)} g'),
            row('aX',     '${f(data.ax, d: 3)} g'),
            row('aY',     '${f(data.ay, d: 3)} g'),
            row('aZ',     '${f(data.az, d: 3)} g'),
            const SizedBox(height: 4),
            row('gX',     '${f(data.gx, d: 1)}°/s'),
            row('gY',     '${f(data.gy, d: 1)}°/s'),
            row('gZ',     '${f(data.gz, d: 1)}°/s'),
            const SizedBox(height: 4),
            row('Batt',   '${f(data.batt)} V'),
          ],
        ],
      ),
    );
  }
}
