# SafeReps

Cross-platform fitness app that uses on-device pose estimation to coach exercise form, fused with IMU data streamed over BLE from a wearable ESP32-C3 + MPU6050 module.

## Repo layout

- `safereps/` — Flutter app (iOS, Android primary; macOS/web/desktop best-effort).
  - `lib/main.dart` — entry, initializes `availableCameras()`.
  - `lib/pose_camera_page.dart` — camera lifecycle, permission gate, ML Kit stream loop.
  - `lib/pose_painter.dart` — `CustomPainter` skeleton overlay using the canonical `flutter-ml` coordinate translator.
- `safereps-esp/` — PlatformIO project for ESP32-C3. Currently a blink stub; will become the MPU6050 BLE peripheral.

## Common dev commands

Flutter app (run from `safereps/`):

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <ios|android device id>     # full pose detection
flutter run -d macos                        # camera only, no pose detection yet
flutter clean && flutter pub get            # when native plugins act up
```

ESP32 firmware (run from `safereps-esp/`):

```bash
pio run                                     # build
pio run -t upload                           # flash
pio device monitor                          # serial monitor
```

## Roadmap

### Phase 0 — Pose visualizer (current)
- [x] Camera preview + ML Kit pose detection on iOS/Android
- [x] Skeleton overlay (torso, arms, legs colored differently)
- [x] Camera permission flow + camera switcher
- [ ] Migrate from ML Kit to MediaPipe Pose Landmarker (see plan below)
- [ ] FPS / latency HUD for tuning

### Phase 1 — Exercise model
- [ ] `Exercise` definition (target joint angles per phase, rep boundaries, tempo)
- [ ] Joint-angle computation from landmarks (shoulder, elbow, hip, knee)
- [ ] Rep counter with state machine (eccentric / bottom / concentric / top)
- [ ] Form rules engine (e.g. "knee valgus during squat", "elbow flare on bench")
- [ ] Per-rep feedback overlay (color-coded skeleton bones when out of tolerance)

### Phase 2 — ESP32 + IMU integration
- [ ] ESP32-C3 firmware: read MPU6050 over I2C, complementary/Madgwick filter for orientation
- [ ] BLE GATT service exposing quaternion + accel + gyro (consider Nordic UART or custom service)
- [ ] Flutter BLE client (`flutter_blue_plus`) — scan, connect, subscribe, reconnect
- [ ] Sensor fusion: align IMU on a tracked limb (e.g. forearm) with the corresponding pose vector
- [ ] Calibration flow (T-pose for orientation reference)

### Phase 3 — Workout UX
- [ ] Exercise library (squat, bench, OHP, deadlift, row to start)
- [ ] Set/rep/rest tracker
- [ ] Session history persistence (sqflite or drift)
- [ ] Post-set form summary with key issues + replay

### Phase 4 — Polish
- [ ] Onboarding + permission re-prompts
- [ ] Light/dark theme, accessibility
- [ ] iOS TestFlight + Android internal testing builds

## Common objectives (recurring tasks)

- **Add a new exercise**: define joint-angle thresholds, key landmarks, rep state machine — keep the rules engine declarative, no per-exercise hardcoded if-chains.
- **Improve detection accuracy**: prefer model upgrade (MediaPipe `_full` → `_heavy`) over hand-tuned heuristics. Profile with the FPS HUD before optimizing.
- **Keep `PosePainter` framework-agnostic**: it should not import ML Kit or MediaPipe types directly — convert to an internal `Skeleton` model so swapping detectors is one file.
- **Don't regress the camera lifecycle**: on Android, always `stopImageStream()` before `dispose()`, null the controller field before awaiting disposal, and handle `inactive`/`paused` lifecycle events. Hot reload doesn't reliably release native camera handles — hot-restart when in doubt.

## MediaPipe migration plan

Why move: MediaPipe Pose Landmarker beats ML Kit on (a) cross-platform reach (web + desktop, not just mobile), (b) tighter landmarks including world-space 3D coords (useful for joint angle math without perspective distortion), and (c) selectable model size for the accuracy/latency tradeoff.

### Step 1 — Introduce a detector abstraction

Define an internal model so the rest of the app stops depending on `google_mlkit_pose_detection` types:

```dart
// lib/pose/skeleton.dart
class SkeletonLandmark { final double x, y, z, visibility; ... }
class Skeleton { final Map<SkeletonJoint, SkeletonLandmark> joints; ... }
enum SkeletonJoint { nose, leftShoulder, rightShoulder, ... }   // 33 joints
```

```dart
// lib/pose/pose_estimator.dart
abstract class PoseEstimator {
  Future<void> initialize();
  Future<List<Skeleton>> processFrame(CameraImage image, CameraDescription camera);
  Future<void> dispose();
}
```

Refactor `PosePainter` to take `List<Skeleton>` instead of `List<Pose>`. After this step the app still uses ML Kit under the hood.

### Step 2 — Wrap current ML Kit code as `MlKitPoseEstimator implements PoseEstimator`

Translate `Pose.landmarks` → `Skeleton`. No behavior change. Verify on device.

### Step 3 — Add MediaPipe implementation

The Flutter ecosystem doesn't ship a single MediaPipe Pose package that covers all targets — implement per-platform under one Dart class:

- **Android / iOS**: bind to native MediaPipe Tasks SDKs via a thin method channel (`mediapipe_pose_platform_interface`). Pass camera frames as bytes (NV21 / BGRA) similar to the current ML Kit path. Bundle `pose_landmarker_lite.task` (~5MB) as an asset; load via the native SDK's model file API.
- **Web**: JS interop with `@mediapipe/tasks-vision`. Feed `<video>` element from the camera plugin's web preview directly to the landmarker.
- **macOS / Windows / Linux**: use `tflite_flutter` with the same `.task` model unpacked to a `.tflite` (or use MediaPipe's C++ SDK via FFI if `tflite_flutter` is too lossy).

Add the model:

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/models/pose_landmarker_lite.task
```

### Step 4 — Switch the default

Wire `MediaPipePoseEstimator` as the default in `pose_camera_page.dart`. Keep `MlKitPoseEstimator` available behind a debug toggle (useful for A/B comparing accuracy/FPS on the same body).

### Step 5 — Take advantage of 3D

MediaPipe gives world-coordinate landmarks. Use these for joint-angle math in the rules engine (Phase 1) instead of 2D image coordinates — image-space angles distort with camera tilt and perspective.

### Step 6 — Retire ML Kit

Once MediaPipe is shipped on all targets we ship to and parity is verified, drop `google_mlkit_pose_detection` from `pubspec.yaml` and delete `MlKitPoseEstimator`. Also bumps the Android `minSdk` requirement down (ML Kit needed 21; MediaPipe bundled .task is more forgiving).

### Risks / open questions

- No mature pub.dev MediaPipe Pose plugin yet — we will likely write the platform channels ourselves. Budget a spike before committing.
- Web camera frame → landmarker pipeline has to avoid copying through Dart; use JS interop end-to-end.
- Model asset size affects app size; offer the `_lite` model as default, `_full`/`_heavy` as optional download.
