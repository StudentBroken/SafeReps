import 'dart:async';
import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show InputImageRotation, InputImageRotationValue;
import 'package:permission_handler/permission_handler.dart';

import '../main.dart' show cameras;
import '../pose/mlkit_pose_estimator.dart';
import '../pose/pose_estimator.dart';
import '../pose/skeleton_smoother.dart';
import '../pose_painter.dart';
import '../services/ble_service.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

// IMU: pitch swing threshold in degrees
const _kImuThreshold = 3.0;
// ML: how far above the shoulder (fraction of image height) counts as "raised"
const _kMlRaiseThreshold = 0.08;
// ML: how close back to shoulder (fraction) counts as "returned"
const _kMlReturnThreshold = 0.02;

const _kGameDuration = 20;

// ── Enums ─────────────────────────────────────────────────────────────────────

enum _Mode { imu, ml }
enum _GameState { idle, running, done }
enum _PitchDir { up, down }
enum _HandPhase { rest, raised }

// ── Per-hand ML tracker ───────────────────────────────────────────────────────

class _HandTracker {
  _HandPhase phase = _HandPhase.rest;

  // Returns true when a full up-down cycle completes.
  // elevation = (shoulderY − wristY) / imageHeight  (positive = wrist above shoulder)
  bool update(double elevation) {
    if (phase == _HandPhase.rest && elevation > _kMlRaiseThreshold) {
      phase = _HandPhase.raised;
    } else if (phase == _HandPhase.raised && elevation < _kMlReturnThreshold) {
      phase = _HandPhase.rest;
      return true;
    }
    return false;
  }

  void reset() => phase = _HandPhase.rest;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class Game67Page extends StatefulWidget {
  const Game67Page({super.key});

  @override
  State<Game67Page> createState() => _Game67PageState();
}

class _Game67PageState extends State<Game67Page> with WidgetsBindingObserver {
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // ── Camera / pose ────────────────────────────────────────────────────────────
  CameraController? _controller;
  PoseEstimator? _estimator;
  final SkeletonSmoother _smoother = SkeletonSmoother();
  List<CameraDescription> _cams = const [];
  int _camIndex = 0;
  bool _busy = false;
  bool _initializing = false;
  String? _error;
  List<Skeleton> _skeletons = const [];
  FrameMeta? _frameMeta;
  int _fps = 0;
  int _latencyMs = 0;
  final List<DateTime> _frameTimes = [];

  // ── Mode ─────────────────────────────────────────────────────────────────────
  _Mode _mode = _Mode.imu;

  // ── Game state ───────────────────────────────────────────────────────────────
  _GameState _gameState = _GameState.idle;
  int _score = 0;
  int _bestScore = 0;
  int _secsLeft = _kGameDuration;
  Timer? _gameTimer;

  // IMU tracking
  _PitchDir? _lastDir;
  double? _refPitch;

  // ML tracking
  final _leftHand  = _HandTracker();
  final _rightHand = _HandTracker();
  double _leftElevation  = 0;
  double _rightElevation = 0;

  BleService? _ble;

  bool get _supportsPose =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBest();
    _bootstrap().catchError((e) {
      if (mounted) setState(() => _error = 'Startup error: $e');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ble = BleScope.of(context);
    if (ble != _ble) {
      _ble?.removeListener(_onImu);
      _ble = ble;
      _ble!.addListener(_onImu);
      ble.startImuStream();
    }
  }

  @override
  void dispose() {
    _ble?.removeListener(_onImu);
    WidgetsBinding.instance.removeObserver(this);
    _gameTimer?.cancel();
    _controller?.dispose();
    _estimator?.close();
    super.dispose();
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
      if (_cams.isNotEmpty && _controller == null) _startCamera();
    }
  }

  // ── Persistence ──────────────────────────────────────────────────────────────

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _bestScore = prefs.getInt('game67_best') ?? 0);
  }

  Future<void> _saveBest(int score) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('game67_best', score);
  }

  void _maybeUpdateBest(int newScore) {
    if (newScore > _bestScore) {
      _bestScore = newScore;
      _saveBest(newScore);
    }
  }

  // ── Camera / bootstrap ───────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    if (!_supportsPose) {
      setState(() => _error = 'Pose detection requires iOS or Android.');
      return;
    }
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied || status.isRestricted) {
      setState(() => _error = 'Camera access blocked. Enable in Settings.');
      return;
    }
    if (!status.isGranted) {
      setState(() => _error = 'Camera permission denied.');
      return;
    }
    var cams = cameras.isNotEmpty ? cameras : await _queryCameras();
    if (cams.isEmpty) {
      setState(() => _error = 'No cameras found.');
      return;
    }
    _cams = cams;
    _camIndex = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    if (_camIndex < 0) _camIndex = 0;

    if (_estimator == null) {
      final est = MlKitPoseEstimator();
      try {
        await est.initialize();
      } catch (e) {
        setState(() => _error = 'Pose detector init failed: $e');
        return;
      }
      _estimator = est;
    }
    await _startCamera();
  }

  Future<List<CameraDescription>> _queryCameras() async {
    try { return await availableCameras(); } catch (_) { return const []; }
  }

  Future<void> _startCamera() async {
    if (_initializing || _cams.isEmpty) return;
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
        try { if (old.value.isStreamingImages) await old.stopImageStream(); } catch (_) {}
        await old.dispose();
      }

      final ctl = CameraController(
        _cams[_camIndex],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await ctl.initialize();
      if (!mounted) { await ctl.dispose(); return; }
      _controller = ctl;
      await ctl.startImageStream(_onFrame);
      if (mounted) setState(() {});
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    final ctl = _controller;
    final est = _estimator;
    if (_busy || est == null || ctl == null) return;
    final meta = _buildMeta(image, ctl);
    if (meta == null) return;
    _busy = true;
    final t0 = DateTime.now();
    try {
      final skeletons = await est.processFrame(image, ctl.description, meta);
      final now = DateTime.now();
      _frameTimes.add(now);
      _frameTimes.removeWhere((t) => now.difference(t) > const Duration(seconds: 1));
      if (!mounted) return;

      final smoothed = _smoother.smooth(skeletons);

      // ML hand tracking — run regardless of game state so elevations are live
      double leftEl = 0, rightEl = 0;
      if (smoothed.isNotEmpty) {
        final sk = smoothed.first;
        final imgH = meta.imageSize.height;
        leftEl  = _calcElevation(sk, SkeletonJoint.leftShoulder,  SkeletonJoint.leftWrist,  imgH);
        rightEl = _calcElevation(sk, SkeletonJoint.rightShoulder, SkeletonJoint.rightWrist, imgH);
      }

      int scoreDelta = 0;
      if (_mode == _Mode.ml && _gameState == _GameState.running) {
        if (_leftHand.update(leftEl))   scoreDelta++;
        if (_rightHand.update(rightEl)) scoreDelta++;
      }

      setState(() {
        _skeletons = smoothed;
        _frameMeta = FrameMeta(
          imageSize: meta.imageSize,
          rotation: meta.rotation,
          lensDirection: meta.lensDirection,
        );
        _fps = _frameTimes.length;
        _latencyMs = now.difference(t0).inMilliseconds;
        _leftElevation  = leftEl;
        _rightElevation = rightEl;

        if (scoreDelta > 0) {
          _score += scoreDelta;
          _maybeUpdateBest(_score);
        }
      });
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  // elevation = (shoulderY − wristY) / imageHeight  (positive = wrist above shoulder)
  double _calcElevation(Skeleton sk, SkeletonJoint shoulderJ, SkeletonJoint wristJ, double imgH) {
    final shoulder = sk[shoulderJ];
    final wrist    = sk[wristJ];
    if (shoulder == null || wrist == null) return 0;
    if (shoulder.visibility < 0.3 || wrist.visibility < 0.3) return 0;
    return (shoulder.y - wrist.y) / imgH;
  }

  FrameMetadata? _buildMeta(CameraImage image, CameraController ctl) {
    final cam = ctl.description;
    InputImageRotation? rot;
    if (Platform.isIOS) {
      rot = InputImageRotationValue.fromRawValue(cam.sensorOrientation);
    } else if (Platform.isAndroid) {
      var comp = _orientations[ctl.value.deviceOrientation];
      if (comp == null) return null;
      comp = cam.lensDirection == CameraLensDirection.front
          ? (cam.sensorOrientation + comp) % 360
          : (cam.sensorOrientation - comp + 360) % 360;
      rot = InputImageRotationValue.fromRawValue(comp);
    }
    if (rot == null) return null;
    return FrameMetadata(
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: _toRot(rot),
      lensDirection: cam.lensDirection,
    );
  }

  static FrameRotation _toRot(InputImageRotation r) => switch (r) {
        InputImageRotation.rotation0deg => FrameRotation.deg0,
        InputImageRotation.rotation90deg => FrameRotation.deg90,
        InputImageRotation.rotation180deg => FrameRotation.deg180,
        InputImageRotation.rotation270deg => FrameRotation.deg270,
      };

  // ── IMU listener ─────────────────────────────────────────────────────────────

  void _onImu() {
    final ble = _ble;
    if (ble == null) return;

    if (ble.connectionState == BleConnectionState.connected && !ble.isStreaming) {
      ble.startImuStream();
    }

    if (_mode != _Mode.imu) return;

    final raw = ble.latestData?.pitch;
    if (raw == null) return;
    final p = -raw; // IMU upside down

    if (_gameState != _GameState.running) {
      _refPitch = p;
      return;
    }

    if (_refPitch == null) {
      _refPitch = p;
      return;
    }

    final ref = _refPitch!;
    final delta = p - ref;

    if (delta > _kImuThreshold && _lastDir != _PitchDir.up) {
      final newScore = _score + 2;
      _maybeUpdateBest(newScore);
      setState(() { _score = newScore; _lastDir = _PitchDir.up; _refPitch = p; });
    } else if (delta < -_kImuThreshold && _lastDir != _PitchDir.down) {
      final newScore = _score + 2;
      _maybeUpdateBest(newScore);
      setState(() { _score = newScore; _lastDir = _PitchDir.down; _refPitch = p; });
    } else {
      if (_lastDir == _PitchDir.up   && p > ref) _refPitch = p;
      if (_lastDir == _PitchDir.down && p < ref) _refPitch = p;
    }
  }

  // ── Game control ─────────────────────────────────────────────────────────────

  void _startGame() {
    _gameTimer?.cancel();
    _leftHand.reset();
    _rightHand.reset();
    setState(() {
      _score     = 0;
      _secsLeft  = _kGameDuration;
      _gameState = _GameState.running;
      _lastDir   = null;
      _refPitch  = null;
    });
    _gameTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _secsLeft--;
        if (_secsLeft <= 0) {
          t.cancel();
          _gameState = _GameState.done;
        }
      });
    });
  }

  void _restart() {
    _gameTimer?.cancel();
    _leftHand.reset();
    _rightHand.reset();
    setState(() {
      _score     = 0;
      _secsLeft  = _kGameDuration;
      _gameState = _GameState.idle;
      _lastDir   = null;
      _refPitch  = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final imu     = BleScope.of(context).latestData;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('67 Game',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_cams.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () async {
                _camIndex = (_camIndex + 1) % _cams.length;
                await _startCamera();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildCameraView()),
          _buildHud(imu, primary),
        ],
      ),
    );
  }

  Widget _buildHud(ImuData? imu, Color primary) {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Mode toggle ───────────────────────────────────────────────────────
          _ModeToggle(
            mode: _mode,
            onChanged: _gameState == _GameState.idle
                ? (m) => setState(() { _mode = m; _leftHand.reset(); _rightHand.reset(); })
                : null,
            primary: primary,
          ),
          const SizedBox(height: 12),

          // ── Score + timer ─────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SCORE',
                      style: TextStyle(color: Colors.white38, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  Text('$_score',
                      style: const TextStyle(color: Colors.white, fontSize: 52,
                          fontWeight: FontWeight.bold, height: 1.0)),
                  Text('best  $_bestScore',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _gameState == _GameState.idle
                          ? 1.0
                          : _secsLeft / _kGameDuration,
                      strokeWidth: 5,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _gameState == _GameState.done ? Colors.white38 : primary,
                      ),
                    ),
                    Text(
                      _gameState == _GameState.idle ? '$_kGameDuration' : '$_secsLeft',
                      style: const TextStyle(color: Colors.white, fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Mode-specific indicator ───────────────────────────────────────────
          if (_mode == _Mode.imu) ...[
            if (imu != null)
              _PitchBar(
                pitch: -imu.pitch - (_refPitch ?? -imu.pitch),
                threshold: _kImuThreshold,
                lastDir: _lastDir,
                primary: primary,
              )
            else
              Text('No IMU — connect ESP32 in BLE Debug',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                  textAlign: TextAlign.center),
          ] else ...[
            _HandBars(
              leftElevation:  _leftElevation,
              rightElevation: _rightElevation,
              leftPhase:  _leftHand.phase,
              rightPhase: _rightHand.phase,
              raiseThreshold: _kMlRaiseThreshold,
              primary: primary,
            ),
          ],

          const SizedBox(height: 12),

          // ── Start / Restart ───────────────────────────────────────────────────
          _HudButton(
            label:    _gameState == _GameState.idle ? 'Start' : 'Restart',
            icon:     _gameState == _GameState.idle
                ? Icons.play_arrow_rounded
                : Icons.refresh_rounded,
            color:    _gameState == _GameState.idle ? primary : Colors.white70,
            onPressed: _gameState == _GameState.idle ? _startGame : _restart,
          ),

          if (_gameState == _GameState.done) ...[
            const SizedBox(height: 10),
            Text("Time's up!  Score: $_score",
                style: TextStyle(color: primary, fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center),
        ),
      );
    }
    final ctl = _controller;
    if (ctl == null || !ctl.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final meta = _frameMeta;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 1 / ctl.value.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(ctl),
                if (meta != null)
                  CustomPaint(
                    painter: PosePainter(
                      skeletons: _skeletons,
                      meta: meta,
                      angles: null,
                      isPoseValid: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: _FpsChip(fps: _fps, latencyMs: _latencyMs),
        ),
      ],
    );
  }
}

// ── Mode toggle ───────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.onChanged,
    required this.primary,
  });

  final _Mode mode;
  final ValueChanged<_Mode>? onChanged;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _Tab(label: 'IMU',    icon: Icons.sensors_rounded,       selected: mode == _Mode.imu, primary: primary,
               onTap: onChanged == null ? null : () => onChanged!(_Mode.imu)),
          _Tab(label: 'ML Kit', icon: Icons.person_outlined, selected: mode == _Mode.ml,  primary: primary,
               onTap: onChanged == null ? null : () => onChanged!(_Mode.ml)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: primary.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14,
                  color: selected ? primary : Colors.white38),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? primary : Colors.white38,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hand bars (ML mode indicator) ─────────────────────────────────────────────

class _HandBars extends StatelessWidget {
  const _HandBars({
    required this.leftElevation,
    required this.rightElevation,
    required this.leftPhase,
    required this.rightPhase,
    required this.raiseThreshold,
    required this.primary,
  });

  final double leftElevation;
  final double rightElevation;
  final _HandPhase leftPhase;
  final _HandPhase rightPhase;
  final double raiseThreshold;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _HandBar(label: 'L', elevation: leftElevation,
            phase: leftPhase, threshold: raiseThreshold, primary: primary)),
        const SizedBox(width: 10),
        Expanded(child: _HandBar(label: 'R', elevation: rightElevation,
            phase: rightPhase, threshold: raiseThreshold, primary: primary)),
      ],
    );
  }
}

class _HandBar extends StatelessWidget {
  const _HandBar({
    required this.label,
    required this.elevation,
    required this.phase,
    required this.threshold,
    required this.primary,
  });

  final String label;
  final double elevation;
  final _HandPhase phase;
  final double threshold;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final raised  = phase == _HandPhase.raised;
    final clamped = elevation.clamp(0.0, 0.4);
    final fraction = clamped / 0.4; // 0–1 fill

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: raised ? primary : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            Text(raised ? 'UP' : 'rest',
                style: TextStyle(
                    color: raised ? primary : Colors.white24,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (_, c) {
          final threshFrac = (threshold / 0.4).clamp(0.0, 1.0);
          final threshPx   = threshFrac * c.maxWidth;
          final fillPx     = fraction * c.maxWidth;
          return SizedBox(
            height: 14,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  width: fillPx,
                  child: Container(
                    decoration: BoxDecoration(
                      color: raised
                          ? primary.withValues(alpha: 0.8)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Positioned(
                  left: threshPx - 1, top: 0, bottom: 0,
                  child: Container(width: 2, color: Colors.white38),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── Pitch bar (IMU mode indicator) ────────────────────────────────────────────

class _PitchBar extends StatelessWidget {
  const _PitchBar({
    required this.pitch,
    required this.threshold,
    required this.lastDir,
    required this.primary,
  });

  final double pitch;
  final double threshold;
  final _PitchDir? lastDir;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final clamped  = pitch.clamp(-20.0, 20.0);
    final fraction = clamped / 20.0;
    final hitUp    = lastDir == _PitchDir.up;
    final hitDown  = lastDir == _PitchDir.down;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('DOWN',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: hitDown ? primary : Colors.white24)),
            Text('${pitch.toStringAsFixed(1)}°',
                style: const TextStyle(color: Colors.white60, fontSize: 11)),
            Text('UP',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: hitUp ? primary : Colors.white24)),
          ],
        ),
        const SizedBox(height: 4),
        LayoutBuilder(builder: (_, c) {
          final width     = c.maxWidth;
          final center    = width / 2;
          final threshPx  = (threshold / 20.0) * center;
          final indicatorX = center + fraction * center;

          return SizedBox(
            height: 20,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Positioned(
                  top: 0, bottom: 0,
                  left: fraction >= 0 ? center : indicatorX,
                  width: (fraction.abs() * center).clamp(0, center),
                  child: Container(
                    decoration: BoxDecoration(
                      color: (fraction.abs() * 20 > threshold)
                          ? primary.withValues(alpha: 0.7)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Positioned(
                    left: center + threshPx - 1, top: 0, bottom: 0,
                    child: Container(width: 2, color: Colors.white38)),
                Positioned(
                    left: center - threshPx - 1, top: 0, bottom: 0,
                    child: Container(width: 2, color: Colors.white38)),
                Positioned(
                    left: center - 1, top: 0, bottom: 0,
                    child: Container(width: 2, color: Colors.white54)),
                Positioned(
                  left: indicatorX - 3, top: 2, bottom: 2,
                  child: Container(
                    width: 6,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── HUD button ────────────────────────────────────────────────────────────────

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: onPressed == null
              ? Colors.white10
              : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: onPressed == null
                  ? Colors.white12
                  : color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18,
                color: onPressed == null ? Colors.white24 : color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: onPressed == null ? Colors.white24 : color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ── FPS chip ──────────────────────────────────────────────────────────────────

class _FpsChip extends StatelessWidget {
  const _FpsChip({required this.fps, required this.latencyMs});
  final int fps;
  final int latencyMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(8)),
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
