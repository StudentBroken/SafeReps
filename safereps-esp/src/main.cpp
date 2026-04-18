#include <Arduino.h>
#include <Wire.h>
#include <I2Cdev.h>
#include <MPU6050_6Axis_MotionApps20.h>
#include <NimBLEDevice.h>
#include <Preferences.h>   // ESP32 NVS wrapper (built-in, no lib_dep needed)

MPU6050    mpu;
Preferences prefs;

// ─── Pin definitions ─────────────────────────────────────────────────────────
#define SDA_PIN        8
#define SCL_PIN        9
#define INTERRUPT_PIN  10
#define BATTERY_PIN    1   // GPIO1 — ADC1_CH1, 100k/100k voltage divider

// ─── Nordic UART Service ──────────────────────────────────────────────────────
#define NUS_SERVICE_UUID "6E400001-B5A4-F393-E0A9-E50E24DCCA9E"
#define NUS_RX_UUID      "6E400002-B5A4-F393-E0A9-E50E24DCCA9E"
#define NUS_TX_UUID      "6E400003-B5A4-F393-E0A9-E50E24DCCA9E"

NimBLEServer*         pServer = nullptr;
NimBLECharacteristic* pTxChar = nullptr;
NimBLECharacteristic* pRxChar = nullptr;
bool deviceConnected = false;

// ─── MPU / DMP state ─────────────────────────────────────────────────────────
bool     dmpReady  = false;
uint8_t  mpuIntStatus;
uint8_t  devStatus;
uint16_t packetSize;
uint8_t  fifoBuffer[64];

Quaternion  q;
VectorFloat gravity;    // unit gravity vector in sensor body frame (from DMP quaternion)
float       ypr[3];

volatile bool mpuInterrupt = false;
void IRAM_ATTR dmpDataReady() { mpuInterrupt = true; }

// ─── EMA smoothing ───────────────────────────────────────────────────────────
float alpha       = 0.5f;
float smoothYaw   = 0, smoothPitch = 0, smoothRoll = 0;

// ─── Tremor detection (100 Hz) ───────────────────────────────────────────────
// 1st-order HP on linear accel.  α = RC/(RC+dt).
// Higher α → higher cutoff → only very fast jitter passes.
// Tunable at runtime via TREMOR_HP <alpha>.
float kTremorHpAlpha = 0.761f;  // fc≈5 Hz default
float kTremorAlpha   = 0.08f;   // EMA smoothing, τ≈125 ms
float prevLax = 0, prevLay = 0, prevLaz = 0;
float hpx = 0, hpy = 0, hpz = 0;
float tremorScore = 0;

// ─── Cheat-swing detection (100 Hz, wrist-mounted) ───────────────────────────
// cheatScore = |gyro| / (|linear_accel| + kCheatEps)
// Low linear_accel while rotating = pendulum/gravity swing, not muscle.
// Tunable at runtime via CHEAT_EPS <eps>.
float kCheatEps      = 0.05f;   // g — baseline muscle-force floor
float kCheatEmaAlpha = 0.05f;   // slow EMA, τ≈200 ms
float swingScore = 0;           // EMA of cheat ratio (°/s per g)

// ─── Zero offsets (runtime, not persisted) ───────────────────────────────────
float yawOffset = 0, pitchOffset = 0, rollOffset = 0;

// ─── Control flags ───────────────────────────────────────────────────────────
bool streamData         = false;
bool battOnly           = false;   // true = connected but not streaming full IMU
bool calibrateRequested = false;

// ─── Battery ─────────────────────────────────────────────────────────────────
float         batteryVoltage    = 0;
unsigned long lastBatteryCheck  = 0;
unsigned long lastBattOnlySend  = 0;
const unsigned long kBatteryInterval  = 5000;
const unsigned long kBattOnlyInterval = 5000;  // 0.2 Hz — minimal BLE traffic

// ─── Send rate ───────────────────────────────────────────────────────────────
unsigned long lastSendMs = 0;
const unsigned long kSendInterval = 100;   // 10 Hz

// ─── BLE helper ───────────────────────────────────────────────────────────────

void bleSend(const char* msg) {
    if (deviceConnected && pTxChar) {
        pTxChar->setValue(reinterpret_cast<const uint8_t*>(msg), strlen(msg));
        pTxChar->notify();
    }
    Serial.println(msg);
}

// ─── NVS calibration ─────────────────────────────────────────────────────────

void saveCalibration() {
    prefs.begin("imu-cal", false);
    prefs.putShort("ax", mpu.getXAccelOffset());
    prefs.putShort("ay", mpu.getYAccelOffset());
    prefs.putShort("az", mpu.getZAccelOffset());
    prefs.putShort("gx", mpu.getXGyroOffset());
    prefs.putShort("gy", mpu.getYGyroOffset());
    prefs.putShort("gz", mpu.getZGyroOffset());
    prefs.putBool("valid", true);
    prefs.end();
    Serial.println("{\"status\":\"Calibration saved to NVS\"}");
}

// Returns true if valid calibration was found and applied.
bool loadCalibration() {
    prefs.begin("imu-cal", true);
    bool valid = prefs.getBool("valid", false);
    if (valid) {
        mpu.setXAccelOffset(prefs.getShort("ax", 0));
        mpu.setYAccelOffset(prefs.getShort("ay", 0));
        mpu.setZAccelOffset(prefs.getShort("az", 0));
        mpu.setXGyroOffset(prefs.getShort("gx", 0));
        mpu.setYGyroOffset(prefs.getShort("gy", 0));
        mpu.setZGyroOffset(prefs.getShort("gz", 0));
    }
    prefs.end();
    return valid;
}

void clearCalibration() {
    prefs.begin("imu-cal", false);
    prefs.clear();
    prefs.end();
}

// ─── Angle EMA — shortest-path to avoid ±180° wrap artefacts ─────────────────

float emaAngle(float current, float raw, float a) {
    float diff = raw - current;
    // Unwrap to [-180, 180] so the filter takes the short arc
    while (diff >  180.0f) diff -= 360.0f;
    while (diff < -180.0f) diff += 360.0f;
    float next = current + a * diff;
    // Re-wrap result to [-180, 180]
    while (next >  180.0f) next -= 360.0f;
    while (next < -180.0f) next += 360.0f;
    return next;
}

// ─── Commands ─────────────────────────────────────────────────────────────────

void parseCommand(String command) {
    command.trim();
    if (command == "DATA_ON") {
        streamData = true;
        battOnly   = false;
        bleSend("{\"status\":\"Data stream ON\"}");
    } else if (command == "DATA_OFF" || command == "BATT_ONLY") {
        streamData       = false;
        battOnly         = true;
        lastBattOnlySend = 0;   // send battery immediately on next loop tick
        bleSend("{\"status\":\"Battery-only mode\"}");
    } else if (command == "ZERO") {
        yawOffset   = smoothYaw;
        pitchOffset = smoothPitch;
        rollOffset  = smoothRoll;
        bleSend("{\"status\":\"Zeroed current position\"}");
    } else if (command == "CALIBRATE") {
        calibrateRequested = true;
        bleSend("{\"status\":\"Calibrating... keep IMU static.\"}");
    } else if (command == "RESET_CAL") {
        clearCalibration();
        bleSend("{\"status\":\"Saved calibration cleared — reboot to auto-calibrate\"}");
    } else if (command.startsWith("DAMPING ")) {
        float v = command.substring(8).toFloat();
        if (v > 0.0f && v <= 1.0f) {
            alpha = v;
            char buf[64];
            snprintf(buf, sizeof(buf), "{\"status\":\"Damping alpha=%.3f\"}", alpha);
            bleSend(buf);
        } else {
            bleSend("{\"status\":\"Invalid alpha (0 < a <= 1)\"}");
        }
    } else if (command.startsWith("TREMOR_HP ")) {
        float v = command.substring(10).toFloat();
        if (v > 0.0f && v < 1.0f) {
            // Changing alpha resets HP state to avoid transient spike.
            kTremorHpAlpha = v;
            hpx = hpy = hpz = 0;
            char buf[64];
            snprintf(buf, sizeof(buf), "{\"status\":\"Tremor HP alpha=%.3f\"}", kTremorHpAlpha);
            bleSend(buf);
        } else {
            bleSend("{\"status\":\"Invalid TREMOR_HP (0 < a < 1)\"}");
        }
    } else if (command.startsWith("TREMOR_EMA ")) {
        float v = command.substring(11).toFloat();
        if (v > 0.0f && v <= 1.0f) {
            kTremorAlpha = v;
            char buf[64];
            snprintf(buf, sizeof(buf), "{\"status\":\"Tremor EMA alpha=%.3f\"}", kTremorAlpha);
            bleSend(buf);
        } else {
            bleSend("{\"status\":\"Invalid TREMOR_EMA (0 < a <= 1)\"}");
        }
    } else if (command.startsWith("CHEAT_EPS ")) {
        float v = command.substring(10).toFloat();
        if (v > 0.0f && v <= 2.0f) {
            kCheatEps = v;
            char buf[64];
            snprintf(buf, sizeof(buf), "{\"status\":\"Cheat eps=%.3f g\"}", kCheatEps);
            bleSend(buf);
        } else {
            bleSend("{\"status\":\"Invalid CHEAT_EPS (0 < eps <= 2)\"}");
        }
    } else if (command.startsWith("CHEAT_EMA ")) {
        float v = command.substring(10).toFloat();
        if (v > 0.0f && v <= 1.0f) {
            kCheatEmaAlpha = v;
            char buf[64];
            snprintf(buf, sizeof(buf), "{\"status\":\"Cheat EMA alpha=%.3f\"}", kCheatEmaAlpha);
            bleSend(buf);
        } else {
            bleSend("{\"status\":\"Invalid CHEAT_EMA (0 < a <= 1)\"}");
        }
    }
}

// ─── Battery ─────────────────────────────────────────────────────────────────

void updateBattery() {
    int raw = 0;
    for (int i = 0; i < 10; i++) raw += analogRead(BATTERY_PIN);
    raw /= 10;
    float pinV    = (raw / 4095.0f) * 3.3f;
    batteryVoltage = pinV * 2.0f * 0.90389f;   // factor for 100k/100k divider
}

// ─── BLE callbacks ───────────────────────────────────────────────────────────

class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, ble_gap_conn_desc* desc) override {
        deviceConnected  = true;
        battOnly         = true;
        streamData       = false;
        lastBattOnlySend = 0;   // send battery immediately on next loop tick
        // Request 10 s supervision timeout so calibration (~5 s) survives.
        pServer->updateConnParams(desc->conn_handle, 24, 48, 0, 1000);
        Serial.println("{\"status\":\"BLE client connected\"}");
    }
    void onDisconnect(NimBLEServer*) override {
        deviceConnected = false;
        streamData      = false;
        battOnly        = false;
        Serial.println("{\"status\":\"BLE client disconnected\"}");
        NimBLEDevice::startAdvertising();
    }
};

class RxCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar) override {
        std::string val = pChar->getValue();
        parseCommand(String(val.c_str()));
    }
};

// ─── BLE setup ───────────────────────────────────────────────────────────────

void setupBLE() {
    NimBLEDevice::init("SafeReps-IMU");
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);

    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    NimBLEService* pService = pServer->createService(NUS_SERVICE_UUID);

    pTxChar = pService->createCharacteristic(NUS_TX_UUID, NIMBLE_PROPERTY::NOTIFY);
    pRxChar = pService->createCharacteristic(
        NUS_RX_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
    pRxChar->setCallbacks(new RxCallbacks());

    pService->start();

    NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
    pAdv->addServiceUUID(NUS_SERVICE_UUID);
    pAdv->setScanResponse(true);
    NimBLEDevice::startAdvertising();

    Serial.println("{\"status\":\"BLE advertising as SafeReps-IMU\"}");
}

// ─── Setup ───────────────────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(2000);

    Wire.begin(SDA_PIN, SCL_PIN);
    Wire.setClock(400000);

    analogReadResolution(12);
    pinMode(INTERRUPT_PIN, INPUT_PULLUP);

    Serial.println("{\"status\":\"Initializing MPU6050...\"}");
    mpu.initialize();

    bool ok = mpu.testConnection();
    Serial.println(ok
        ? "{\"status\":\"MPU6050 connected\"}"
        : "{\"status\":\"MPU6050 connection FAILED\"}");

    devStatus = mpu.dmpInitialize();
    if (devStatus != 0) {
        char buf[64];
        snprintf(buf, sizeof(buf), "{\"error\":\"DMP init failed (code %d)\"}", devStatus);
        Serial.println(buf);
        setupBLE();
        return;
    }

    // Try to restore saved calibration; fall back to factory seed + auto-cal.
    bool calLoaded = loadCalibration();
    if (calLoaded) {
        Serial.println("{\"status\":\"Loaded saved calibration from NVS\"}");
    } else {
        Serial.println("{\"status\":\"No saved calibration — running auto-calibration...\"}");
        // Apply factory seed offsets before letting the calibration routine run
        mpu.setXGyroOffset(220);
        mpu.setYGyroOffset(76);
        mpu.setZGyroOffset(-85);
        mpu.setZAccelOffset(1788);
        mpu.CalibrateAccel(6);
        mpu.CalibrateGyro(6);
        mpu.PrintActiveOffsets();
        saveCalibration();
    }

    mpu.setDMPEnabled(true);
    attachInterrupt(digitalPinToInterrupt(INTERRUPT_PIN), dmpDataReady, RISING);
    mpuIntStatus = mpu.getIntStatus();
    dmpReady     = true;
    packetSize   = mpu.dmpGetFIFOPacketSize();
    Serial.println("{\"status\":\"DMP ready\"}");

    setupBLE();
}

// ─── Loop ────────────────────────────────────────────────────────────────────

void loop() {
    if (Serial.available()) {
        parseCommand(Serial.readStringUntil('\n'));
    }

    // Deferred calibration — runs in the Arduino task so NimBLE's task stays free.
    if (calibrateRequested) {
        calibrateRequested = false;

        // Disable DMP first: CalibrateAccel/Gyro read raw registers and will
        // fight the DMP if it is still active, causing the loop to never converge.
        mpu.setDMPEnabled(false);
        delay(50);

        mpu.CalibrateAccel(6);
        mpu.CalibrateGyro(6);
        mpu.PrintActiveOffsets();
        saveCalibration();

        // Re-enable DMP and flush any stale FIFO data that built up.
        mpu.resetFIFO();
        mpuInterrupt = false;
        mpu.setDMPEnabled(true);

        bleSend("{\"status\":\"Calibration complete\"}");
    }

    // ── Battery-only heartbeat (runs even if DMP is not ready) ──────────────────
    if (battOnly && deviceConnected) {
        unsigned long now = millis();
        if (now - lastBattOnlySend >= kBattOnlyInterval) {
            lastBattOnlySend = now;
            updateBattery();
            char buf[32];
            snprintf(buf, sizeof(buf), "{\"batt\":%.2f}\n", batteryVoltage);
            bleSend(buf);
        }
    }

    if (!dmpReady) return;

    if (mpuInterrupt && mpu.dmpGetCurrentFIFOPacket(fifoBuffer)) {
        mpuInterrupt = false;

        // ── Quaternion → orientation ─────────────────────────────────────────
        mpu.dmpGetQuaternion(&q, fifoBuffer);
        mpu.dmpGetGravity(&gravity, &q);
        mpu.dmpGetYawPitchRoll(ypr, &q, &gravity);

        float rawYaw   = ypr[0] * 180.0f / M_PI;
        float rawPitch = ypr[2] * 180.0f / M_PI; // Swapped for 90deg mount
        float rawRoll  = ypr[1] * 180.0f / M_PI; // Swapped for 90deg mount

        // Wraparound-safe EMA (takes shortest arc through ±180° boundary)
        smoothYaw   = emaAngle(smoothYaw,   rawYaw,   alpha);
        smoothPitch = emaAngle(smoothPitch, rawPitch, alpha);
        smoothRoll  = emaAngle(smoothRoll,  rawRoll,  alpha);

        float finalYaw   = smoothYaw   - yawOffset;
        float finalPitch = smoothPitch - pitchOffset;
        float finalRoll  = smoothRoll  - rollOffset;

        // ── 100 Hz: linear accel + tremor pipeline ───────────────────────────
        // Read raw sensor registers every DMP packet (time-aligned with gravity).
        int16_t rax, ray, raz, rgx, rgy, rgz;
        mpu.getMotion6(&rax, &ray, &raz, &rgx, &rgy, &rgz);

        // Gravity-compensated linear acceleration in g (swapped for 90deg mount).
        float lax = ray / 16384.0f - gravity.y;
        float lay = rax / 16384.0f - gravity.x;
        float laz = raz / 16384.0f - gravity.z;

        // ── Tremor: HP on linear accel >5 Hz ────────────────────────────────
        hpx = kTremorHpAlpha * (hpx + lax - prevLax);
        hpy = kTremorHpAlpha * (hpy + lay - prevLay);
        hpz = kTremorHpAlpha * (hpz + laz - prevLaz);
        prevLax = lax;  prevLay = lay;  prevLaz = laz;

        float tremorMag = sqrtf(hpx*hpx + hpy*hpy + hpz*hpz);
        tremorScore = kTremorAlpha * tremorMag + (1.0f - kTremorAlpha) * tremorScore;

        // ── Cheat-swing: ratio of angular speed to muscle-generated force ────
        // Near-zero linear_accel during a gravity/momentum swing (pendulum mode)
        // means the muscle isn't doing work — cheatRaw spikes regardless of speed.
        float linearMag = sqrtf(lax*lax + lay*lay + laz*laz);
        float cheatRaw  = fabsf(rgx / 131.0f) / (linearMag + kCheatEps);
        swingScore = kCheatEmaAlpha * cheatRaw + (1.0f - kCheatEmaAlpha) * swingScore;

        // ── 10 Hz: BLE send ──────────────────────────────────────────────────
        if (streamData) {
            unsigned long now = millis();
            if (now - lastSendMs >= kSendInterval) {
                lastSendMs = now;

                if (now - lastBatteryCheck > kBatteryInterval || lastBatteryCheck == 0) {
                    updateBattery();
                    lastBatteryCheck = now;
                }

                char buf[256];
                snprintf(buf, sizeof(buf),
                    "{\"yaw\":%.2f,\"pitch\":%.2f,\"roll\":%.2f,"
                    "\"ax\":%.3f,\"ay\":%.3f,\"az\":%.3f,"
                    "\"gx\":%.2f,\"gy\":%.2f,\"gz\":%.2f,"
                    "\"tremor\":%.3f,\"swing\":%.1f,\"batt\":%.2f}\n",
                    finalYaw, finalPitch, finalRoll,
                    lax, lay, laz,
                    rgy / 131.0f, rgx / 131.0f, rgz / 131.0f, // Swapped
                    tremorScore, swingScore,
                    batteryVoltage
                );
                bleSend(buf);
            }
        }
    }
}
