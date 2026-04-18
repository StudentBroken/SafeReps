#include <Arduino.h>
#include <Wire.h>
#include <I2Cdev.h>
#include <MPU6050_6Axis_MotionApps20.h>
#include <NimBLEDevice.h>

MPU6050 mpu;

// Pin definitions for ESP32-C3
#define SDA_PIN        8
#define SCL_PIN        9
#define INTERRUPT_PIN  10
#define BATTERY_PIN    1   // GPIO1 — ADC1_CH1, 100k/100k divider

// Nordic UART Service (NUS)
#define NUS_SERVICE_UUID "6E400001-B5A4-F393-E0A9-E50E24DCCA9E"
#define NUS_RX_UUID      "6E400002-B5A4-F393-E0A9-E50E24DCCA9E"  // phone → ESP32
#define NUS_TX_UUID      "6E400003-B5A4-F393-E0A9-E50E24DCCA9E"  // ESP32 → phone

NimBLEServer*         pServer   = nullptr;
NimBLECharacteristic* pTxChar   = nullptr;
NimBLECharacteristic* pRxChar   = nullptr;
bool deviceConnected = false;

// MPU / DMP state
bool     dmpReady  = false;
uint8_t  mpuIntStatus;
uint8_t  devStatus;
uint16_t packetSize;
uint8_t  fifoBuffer[64];

Quaternion  q;
VectorFloat gravity;
float       ypr[3];

volatile bool mpuInterrupt = false;
void IRAM_ATTR dmpDataReady() { mpuInterrupt = true; }

// EMA smoothing
float alpha       = 0.5f;
float smoothYaw   = 0, smoothPitch = 0, smoothRoll = 0;

// Zero offsets
float yawOffset = 0, pitchOffset = 0, rollOffset = 0;

// Control
bool streamData = false;

// Battery
float         batteryVoltage   = 0;
unsigned long lastBatteryCheck = 0;
const unsigned long kBatteryInterval = 5000;

// Rate-limit BLE output to 10 Hz
unsigned long lastSendMs = 0;
const unsigned long kSendInterval = 100;

// ─── BLE helpers ─────────────────────────────────────────────────────────────

void bleSend(const char* msg) {
    if (deviceConnected && pTxChar) {
        pTxChar->setValue(reinterpret_cast<const uint8_t*>(msg), strlen(msg));
        pTxChar->notify();
    }
    Serial.println(msg);  // mirror to serial for debugging
}

// ─── Commands (called from both Serial and BLE RX) ───────────────────────────

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
        bleSend("{\"status\":\"Calibrating... keep IMU static.\"}");
        mpu.CalibrateAccel(6);
        mpu.CalibrateGyro(6);
        mpu.PrintActiveOffsets();
        bleSend("{\"status\":\"Calibration complete\"}");
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
    // Calibrated: user reported 4.37V when it was actually 3.95V (factor = 0.90389)
    batteryVoltage = pinV * 2.0f * 0.90389f;
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
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);  // max TX power

    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    NimBLEService* pService = pServer->createService(NUS_SERVICE_UUID);

    pTxChar = pService->createCharacteristic(
        NUS_TX_UUID,
        NIMBLE_PROPERTY::NOTIFY
    );

    pRxChar = pService->createCharacteristic(
        NUS_RX_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    pRxChar->setCallbacks(new RxCallbacks());

    pService->start();

    NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
    pAdv->addServiceUUID(NUS_SERVICE_UUID);
    pAdv->setScanResponse(true);
    NimBLEDevice::startAdvertising();

    Serial.println("{\"status\":\"BLE advertising as SafeReps-IMU\"}");
}

// ─── Arduino setup ───────────────────────────────────────────────────────────

void setup() {
    Serial.begin(115200);
    delay(2000);  // ESP32-C3 native USB needs a moment

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

    // Factory-calibration seed offsets
    mpu.setXGyroOffset(220);
    mpu.setYGyroOffset(76);
    mpu.setZGyroOffset(-85);
    mpu.setZAccelOffset(1788);

    if (devStatus == 0) {
        Serial.println("{\"status\":\"Running initial DMP calibration...\"}");
        mpu.CalibrateAccel(6);
        mpu.CalibrateGyro(6);
        mpu.PrintActiveOffsets();

        mpu.setDMPEnabled(true);
        attachInterrupt(digitalPinToInterrupt(INTERRUPT_PIN), dmpDataReady, RISING);
        mpuIntStatus = mpu.getIntStatus();

        dmpReady   = true;
        packetSize = mpu.dmpGetFIFOPacketSize();
        Serial.println("{\"status\":\"DMP ready\"}");
    } else {
        char buf[64];
        snprintf(buf, sizeof(buf), "{\"error\":\"DMP init failed (code %d)\"}", devStatus);
        Serial.println(buf);
    }

    setupBLE();
}

// ─── Arduino loop ────────────────────────────────────────────────────────────

void loop() {
    // Handle commands from serial (for bench testing without BLE)
    if (Serial.available()) {
        String cmd = Serial.readStringUntil('\n');
        parseCommand(cmd);
    }

    if (!dmpReady) return;

    if (mpuInterrupt && mpu.dmpGetCurrentFIFOPacket(fifoBuffer)) {
        mpuInterrupt = false;

        // DMP → quaternion → yaw/pitch/roll
        mpu.dmpGetQuaternion(&q, fifoBuffer);
        mpu.dmpGetGravity(&gravity, &q);
        mpu.dmpGetYawPitchRoll(ypr, &q, &gravity);

        float rawYaw   = ypr[0] * 180.0f / M_PI;
        float rawPitch = ypr[1] * 180.0f / M_PI;
        float rawRoll  = ypr[2] * 180.0f / M_PI;

        smoothYaw   = alpha * rawYaw   + (1.0f - alpha) * smoothYaw;
        smoothPitch = alpha * rawPitch + (1.0f - alpha) * smoothPitch;
        smoothRoll  = alpha * rawRoll  + (1.0f - alpha) * smoothRoll;

        float finalYaw   = smoothYaw   - yawOffset;
        float finalPitch = smoothPitch - pitchOffset;
        float finalRoll  = smoothRoll  - rollOffset;

        if (streamData) {
            unsigned long now = millis();
            if (now - lastSendMs >= kSendInterval) {
                lastSendMs = now;

                // Update battery periodically
                if (now - lastBatteryCheck > kBatteryInterval || lastBatteryCheck == 0) {
                    updateBattery();
                    lastBatteryCheck = now;
                }

                // Raw accel (±2g → divide by 16384 for g) and gyro (±250°/s → divide by 131)
                int16_t ax, ay, az, gx, gy, gz;
                mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);

                char buf[192];
                snprintf(buf, sizeof(buf),
                    "{\"yaw\":%.2f,\"pitch\":%.2f,\"roll\":%.2f,"
                    "\"ax\":%.3f,\"ay\":%.3f,\"az\":%.3f,"
                    "\"gx\":%.2f,\"gy\":%.2f,\"gz\":%.2f,"
                    "\"batt\":%.2f}\n",
                    finalYaw, finalPitch, finalRoll,
                    ax / 16384.0f, ay / 16384.0f, az / 16384.0f,
                    gx / 131.0f,  gy / 131.0f,  gz / 131.0f,
                    batteryVoltage
                );
                bleSend(buf);
            }
        }
    }
}
