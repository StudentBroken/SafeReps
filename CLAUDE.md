# SafeReps

Cross-platform fitness app that uses on-device pose estimation to coach exercise form, fused with IMU data streamed over BLE from a wearable ESP32-C3 + MPU6050 module.

## Repo layout

- `safereps/` — Flutter app (iOS, Android primary; macOS/web/desktop best-effort).
  - `lib/main.dart` — entry, initializes `availableCameras()`.
  - `lib/pose_camera_page.dart` — camera lifecycle, permission gate, ML Kit stream loop.
  - `lib/pose_painter.dart` — `CustomPainter` skeleton overlay using the canonical `flutter-ml` coordinate translator.
- `safereps-esp/` — PlatformIO project for ESP32-C3. Reads MPU6050 IMU via I2C, uses DMP for 6-axis orientation, and streams JSON over Serial. Includes a Web Serial `visualizer.html` for desktop testing.

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
# Visualizer: Open safereps-esp/visualizer.html in Chrome/Edge
```

## Roadmap

### Phase 0 — Pose visualizer (current)
- [x] Camera preview + ML Kit pose detection on iOS/Android
- [x] Skeleton overlay (torso, arms, legs colored differently)
- [x] Camera permission flow + camera switcher
- [ ] FPS / latency HUD for tuning

### Phase 1 — Exercise model
- [ ] `Exercise` definition (target joint angles per phase, rep boundaries, tempo)
- [ ] Joint-angle computation from landmarks (shoulder, elbow, hip, knee)
- [ ] Rep counter with state machine (eccentric / bottom / concentric / top)
- [ ] Form rules engine (e.g. "knee valgus during squat", "elbow flare on bench")
- [ ] Per-rep feedback overlay (color-coded skeleton bones when out of tolerance)

### Phase 2 — ESP32 + IMU integration
- [x] ESP32-C3 firmware: read MPU6050 over I2C, DMP/EMA filtering for orientation
- [x] Serial JSON protocol: `{"yaw": 0.0, "pitch": 0.0, "roll": 0.0}` stream
- [x] Web Serial visualizer for IMU testing and calibration
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
- **Keep `PosePainter` framework-agnostic**: it should not import ML Kit types directly — convert to an internal `Skeleton` model so swapping detectors is one file.
- **Don't regress the camera lifecycle**: on Android, always `stopImageStream()` before `dispose()`, null the controller field before awaiting disposal, and handle `inactive`/`paused` lifecycle events. Hot reload doesn't reliably release native camera handles — hot-restart when in doubt.
