<p align="center">
  <img src="safereps/assets/SafeReps_Logo.png" width="400" alt="SafeReps Logo">
</p>

# SafeReps
### Movement Intelligence for Home Strength Training
**Correct form. Prevent injuries. Know your limits.**

---

## 📽️ THE PROBLEM
### "Training Blind"
When you work out at home, you're training blind. You follow a video on a screen, but the screen can't see you back—and it definitely can't tell you that your back is rounding or that you stopped hitting full range of motion three reps ago.

*   **Invisible Fatigue**: Muscle tremors and form breakdown happen before you consciously feel them.
*   **The Feedback Gap**: Videos are a one-way street. Without a coach, bad habits compound into chronic injury.
*   **Missing Context**: Heart rate monitors tell you *how hard* you're working, but they don't know *if* you're lifting safely.

---

## 💡 THE SOLUTION
### A Personal Trainer in Your Living Room
SafeReps is a dual-stream coaching ecosystem that fuses two data sources into a single real-time picture of your movement.

#### **1. VISION (The Eyes)**
Google ML Kit tracks 33 skeletal landmarks at 30 FPS. It calculates joint angles and range of motion using the phone you already own.

#### **2. WEARABLE (The Senses)**
A high-speed sensor module detecting the "invisible" physics: momentum cheating, muscle tremors, and plane-of-motion drift that no camera can catch.

> **The Digital Twin**: When these streams align, SafeReps builds a live model of your workout. The moment form degrades, the AI coach fires immediately: *"Slow your descent"* or *"Straighten your arm."*

---

## 🧠 THE "SECRET SAUCE"
### High-Fidelity DSP & Logic

| Layer | Technology |
| :--- | :--- |
| **Mobile App** | Flutter + Google ML Kit |
| **Wearable** | ESP32-C3 with low-latency BLE |
| **Sensing** | MPU6050 6-Axis IMU at 100Hz |
| **DSP** | On-chip high-pass tremor filters + Angular/Linear velocity ratios |
| **Logic** | 5-Stage FSM (Idle → Top → Descending → Bottom → Ascending) |

---

## 🛠️ THE HARDWARE
### Pro-Level Tech. DIY Price.

| Component | Role |
| :--- | :--- |
| **ESP32-C3** | Logic & Low-Latency Bluetooth |
| **MPU6050** | 6-Axis IMU (Sensing) |
| **Power Path** | USB-C Charger, Switch, & Protection Diode |
| **Monitoring** | 100k Ohm Voltage Divider (Battery Level) |

> **Hardware Economics**: Our working prototype costs under **$5** in components. With a custom PCB at volume, the BOM drops to **~$3**, making a $50 retail price highly realistic for pro-grade coaching.

---

## ⚖️ THE SETUP
### T-Pose Calibration
Accuracy starts with alignment. SafeReps requires a 1-second **T-Pose** before every set to software-align the sensor's coordinate system to your specific limb geometry. No manual setup required.

---

## 🧪 WHAT WE LEARNED
*   **Latency is the UX**: In fitness, 500ms is the difference between a useful cue and an injury. Optimizing the sensor-to-coach pipeline was our most impactful work.
*   **Cameras see position. Sensors feel effort**: Vision tells you where a limb is. A 100Hz IMU tells you how hard the muscles are working and how stable the movement is. You need both.
*   **Calibration beats features**: User-friendly auto-alignment (T-Pose) matters more than any individual algorithm. If setup is hard, users skip it.

---

## 🔮 THE FUTURE
*   **🍎 LiDAR-Enhanced Tracking**: Integrating front-facing LiDAR for true depth-aware skeletal tracking and sub-centimeter joint positioning.
*   **🥊 Shadow Boxing**: High-speed strike velocity and "snap" analysis for combat sports.
*   **🕶️ AR Overlays**: Visual "ghost reps" projected over your body in real-time.
*   **🏥 Physical Therapy**: High-fidelity tracking for home-based rehabilitation.

---
<p align="center">
  <b>Built for those who lift smart.</b><br>
  Check the <code>/safereps</code> and <code>/safereps-esp</code> folders to get started.
</p>
