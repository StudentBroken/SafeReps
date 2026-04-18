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
VectorFloat gravity;
VectorInt16 aaRaw;      // raw accel from DMP FIFO (DMP units, ±2 g = 16384 LSB/g)
VectorInt16 aaLinear;   // gravity-free linear accel (same scale)
VectorInt16 gyroRaw;    // gyro from DMP FIFO (±2000 °/s = 16.4 LSB/°/s)
float       ypr[3];

volatile bool mpuInterrupt = false;
void IRAM_ATTR dmpDataReady() { mpuInterrupt = true; }

// ─── EMA smoothing ───────────────────────────────────────────────────────────
float alpha       = 0.5f;
float smoothYaw   = 0, smoothPitch = 0, smoothRoll = 0;

// ─── Zero offsets (runtime, not persisted) ───────────────────────────────────
float yawOffset = 0, pitchOffset = 0, rollOffset = 0;

// ─── Control flags ───────────────────────────────────────────────────────────
bool streamData         = false;
bool calibrateRequested = false;

// ─── Battery ─────────────────────────────────────────────────────────────────
float         batteryVoltage   = 0;
unsigned long lastBatteryCheck = 0;
const unsigned long kBatteryInterval = 5000;

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
        bleSend("{\"status\":\"Data stream ON\"}");
    } else if (command == "DATA_OFF") {
        streamData = false;
        bleSend("{\"status\":\"Data stream OFF\"}");
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
        float newAlpha = command.substring(8).toFloat();
        if (newAlpha > 0.0f && newAlpha <= 1.0f) {
            alpha = newAlpha;
            char buf[64];
            snprintf(buf, sizeof(buf), "{\"status\":\"Damping alpha set to %.2f\"}", alpha);
            bleSend(buf);
        } else {
            bleSend("{\"status\":\"Invalid alpha (must be 0 < a <= 1)\"}");
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
    void onConnect(NimBLEServer*) override {
        deviceConnected = true;
        Serial.println("{\"status\":\"BLE client connected\"}");
    }
    void onDisconnect(NimBLEServer*) override {
        deviceConnected = false;
        streamData      = false;
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
        mpu.CalibrateAccel(6);
        mpu.CalibrateGyro(6);
        mpu.PrintActiveOffsets();
        saveCalibration();
        bleSend("{\"status\":\"Calibration complete\"}");
    }

    if (!dmpReady) return;

    if (mpuInterrupt && mpu.dmpGetCurrentFIFOPacket(fifoBuffer)) {
        mpuInterrupt = false;

        // ── Quaternion → orientation ─────────────────────────────────────────
        mpu.dmpGetQuaternion(&q, fifoBuffer);
        mpu.dmpGetGravity(&gravity, &q);
        mpu.dmpGetYawPitchRoll(ypr, &q, &gravity);

        float rawYaw   = ypr[0] * 180.0f / M_PI;
        float rawPitch = ypr[1] * 180.0f / M_PI;
        float rawRoll  = ypr[2] * 180.0f / M_PI;

        // Wraparound-safe EMA (takes shortest arc through ±180° boundary)
        smoothYaw   = emaAngle(smoothYaw,   rawYaw,   alpha);
        smoothPitch = emaAngle(smoothPitch, rawPitch, alpha);
        smoothRoll  = emaAngle(smoothRoll,  rawRoll,  alpha);

        float finalYaw   = smoothYaw   - yawOffset;
        float finalPitch = smoothPitch - pitchOffset;
        float finalRoll  = smoothRoll  - rollOffset;

        if (streamData) {
            unsigned long now = millis();
            if (now - lastSendMs >= kSendInterval) {
                lastSendMs = now;

                if (now - lastBatteryCheck > kBatteryInterval || lastBatteryCheck == 0) {
                    updateBattery();
                    lastBatteryCheck = now;
                }

                // ── Accel + gyro from DMP FIFO (time-aligned with quaternion) ──
                // aaLinear = raw accel − gravity vector → gives pure motion accel
                mpu.dmpGetAccel(&aaRaw, fifoBuffer);
                mpu.dmpGetLinearAccel(&aaLinear, &aaRaw, &gravity);
                mpu.dmpGetGyro(&gyroRaw, fifoBuffer);

                // aaLinear scale: 16384 LSB/g  |  gyroRaw scale: 16.4 LSB/°/s
                char buf[220];
                snprintf(buf, sizeof(buf),
                    "{\"yaw\":%.2f,\"pitch\":%.2f,\"roll\":%.2f,"
                    "\"ax\":%.3f,\"ay\":%.3f,\"az\":%.3f,"
                    "\"gx\":%.2f,\"gy\":%.2f,\"gz\":%.2f,"
                    "\"batt\":%.2f}\n",
                    finalYaw, finalPitch, finalRoll,
                    aaLinear.x / 16384.0f, aaLinear.y / 16384.0f, aaLinear.z / 16384.0f,
                    gyroRaw.x  / 16.4f,   gyroRaw.y  / 16.4f,   gyroRaw.z  / 16.4f,
                    batteryVoltage
                );
                bleSend(buf);
            }
        }
    }
}
