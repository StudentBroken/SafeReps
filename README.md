<p align="center">
  <img src="safereps/assets/SafeReps_Logo.png" width="200" alt="SafeReps Logo">
</p>

# SafeReps

### AI-Powered Fitness Coaching with Sensor Fusion

SafeReps is a next-generation fitness tracking ecosystem that combines **on-device computer vision** with **wearable sensor fusion** to provide real-time, high-precision coaching. By fusing live pose data from your phone's camera with sub-degree orientation data from a wrist-mounted IMU, SafeReps detects form breakdown, tracks fatigue, and counts reps with industry-leading accuracy.

---

## 🌟 Key Features

*   **Dual-Stream Sensor Fusion**: Merges Google ML Kit pose landmarks with high-frequency IMU data (Yaw/Pitch/Roll) via Bluetooth Low Energy (BLE).
*   **Intelligent Form Coaching**: Detects specific form violations like "swinging," "short range of motion," and "poor tempo."
*   **Fatigue Analysis (Tremor Detection)**: Uses an onboard high-pass filter (100Hz) on the ESP32 to measure muscle tremors—a leading indicator of neuromuscular fatigue.
*   **AI Voice Coach**: Real-time audio feedback that adapts to your performance, providing corrections exactly when you need them.
*   **Liquid Glass UI**: A premium, matte-beige and frosted-glass aesthetic designed for high visibility in gym environments.
*   **Persistent Analytics**: Track your volume, intensity, and form quality over time with automated session logging.

---

## 🛠 Tech Stack

### Mobile App (Flutter)
- **Engine**: Flutter SDK (Dart)
- **AI**: Google ML Kit (Pose Detection)
- **Communication**: `flutter_blue_plus` for low-latency BLE (Nordic UART Service)
- **UI System**: Custom "Liquid Glass" theme with `BackdropFilter` effects

### Wearable Firmware (ESP32)
- **Hardware**: ESP32-C3 + MPU6050 (6-axis IMU)
- **Framework**: PlatformIO (Arduino + NimBLE)
- **DSP**: Digital Motion Processor (DMP) with EMA smoothing and gravity compensation
- **Onboard Logic**: Real-time tremor calculation and PCA-based mount-angle calibration

---

## 📂 Repository Structure

- `safereps/` — The primary Flutter application directory.
    - `lib/pose/` — Pose estimation logic and skeletal smoothing.
    - `lib/analysis/` — Exercise-specific analysis and rep counting state machines.
    - `lib/services/` — BLE communication and data persistence.
    - `lib/theme.dart` — The centralized design system and color palette.
- `safereps-esp/` — The C++ firmware for the wearable module.
    - `src/main.cpp` — The core firmware including IMU processing and BLE stack.
- `firmware/` — Alternative firmware versions and legacy builds.

---

## 🚀 Getting Started

### 1. Hardware Setup (Wearable)
SafeReps requires a wrist-mounted ESP32-C3 with an MPU6050 IMU.
- **Build**: Connect MPU6050 via I2C (SDA: GPIO8, SCL: GPIO9) to an ESP32-C3.
- **Flash**:
  ```bash
  cd safereps-esp
  pio run -t upload
  ```

### 2. Mobile App Setup
Ensure you have the Flutter SDK installed.
- **Install Dependencies**:
  ```bash
  cd safereps
  flutter pub get
  ```
- **Run**:
  ```bash
  flutter run
  ```
  *(Note: Use a physical device for full pose estimation and BLE functionality.)*

---

## ⚖️ Calibration & Usage

1.  **Mounting**: Secure the IMU module to your wrist or forearm.
2.  **Pairing**: Open the SafeReps app, navigate to **Settings > BLE Debug**, and connect to "SafeReps-IMU".
3.  **Calibration**:
    *   **Static Cal**: Keep the sensor perfectly still and hit **CALIBRATE** to save offsets to the ESP32's non-volatile storage (NVS).
    *   **Mount Align**: Run **MOUNT_CAL** while swinging your arm normally to help the AI understand exactly how the sensor is oriented on your limb.
4.  **Workout**: Select an exercise (e.g., Lateral Raise) and position your phone to see your full body. The AI will take care of the rest!

---

## 📊 Roadmap

### Phase 1: Core Engine (Complete)
- [x] High-precision pose detection
- [x] BLE data streaming protocol
- [x] Basic rep counting (Bicep Curls, Lateral Raises)

### Phase 2: Intelligence (Current)
- [x] Onboard tremor/fatigue detection
- [x] Advanced "swing" (cheat) detection
- [x] AI Voice Coach implementation
- [ ] Multi-limb sensor support

### Phase 3: Ecosystem
- [ ] Cloud sync for workout history
- [ ] Community challenges and leaderboards
- [ ] Export to Apple Health / Google Fit

---

## 🔮 The Future: Beyond the Rep

SafeReps is evolving from a rep counter into a complete movement intelligence platform. Our upcoming roadmap includes:

*   **⌚ Smart Watch Integration**: Porting our sensor fusion algorithms to Apple Watch and Wear OS for a seamless, peripheral-free experience.
*   **🎮 Gamification & Play**:
    *   **Movement-Based Games**: Turn your workout into a literal game where your body is the controller.
    *   **Artistic Expression**: "Drawing" in 3D space using movement trajectories.
    *   **Gamified Progress**: RPG-style stat progression based on the quality and consistency of your reps.
*   **🥋 Expanded Disciplines**:
    *   **Shadow Boxing**: High-speed tracking and strike analysis for combat sports.
    *   **Rehabilitation**: Dedicated modules for physical therapy and injury recovery with sub-degree ROM tracking.
    *   **Movement Analysis**: Professional-grade biomechanical breakdowns for peak performance.
*   **🧭 Cutting-Edge Tracking**:
    *   **Dead Reckoning**: Advanced IMU-only positioning and spatial tracking for when the camera view is obstructed.
    *   **Full-Body Fusion**: Support for multi-sensor arrays to track every joint simultaneously.

---

## 📄 License

This project is proprietary. All rights reserved.

---
<p align="center">Made with ❤️ for the safe heavy lifters.</p>
