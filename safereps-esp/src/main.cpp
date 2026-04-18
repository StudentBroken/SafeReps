#include <Arduino.h>
#include <Wire.h>
#include <I2Cdev.h>
#include <MPU6050_6Axis_MotionApps20.h>

MPU6050 mpu;

// Pin Definitions for ESP32-C3
#define SDA_PIN 8
#define SCL_PIN 9
#define INTERRUPT_PIN 10
#define BATTERY_PIN 0  // GPIO0 is ADC1_CH0

// MPU control/status vars
bool dmpReady = false;  // set true if DMP init was successful
uint8_t mpuIntStatus;   // holds actual interrupt status byte from MPU
uint8_t devStatus;      // return status after each device operation (0 = success, !0 = error)
uint16_t packetSize;    // expected DMP packet size (default is 42 bytes)
uint16_t fifoCount;     // count of all bytes currently in FIFO
uint8_t fifoBuffer[64]; // FIFO storage buffer

// orientation/motion vars
Quaternion q;           // [w, x, y, z]         quaternion container
VectorFloat gravity;    // [x, y, z]            gravity vector
float ypr[3];           // [yaw, pitch, roll]   yaw/pitch/roll container and gravity vector

volatile bool mpuInterrupt = false;
void IRAM_ATTR dmpDataReady() {
    mpuInterrupt = true;
}

// Variables for Damping (Exponential Moving Average)
float alpha = 0.5; // Smoothing factor (0.0 < alpha <= 1.0)
float smoothYaw = 0, smoothPitch = 0, smoothRoll = 0;

// Variables for Zeroing (Offsets)
float yawOffset = 0, pitchOffset = 0, rollOffset = 0;

// Serial Control
bool streamData = false;

// Battery monitoring
float batteryVoltage = 0;
unsigned long lastBatteryCheck = 0;
const unsigned long batteryInterval = 5000;

void updateBattery() {
    int raw = 0;
    for(int i=0; i<10; i++) raw += analogRead(BATTERY_PIN);
    raw /= 10;
    float pinVoltage = (raw / 4095.0) * 3.3;
    batteryVoltage = pinVoltage * 2.0; // 100k/100k divider
}

void parseCommand(String command) {
    command.trim();
    if (command == "DATA_ON") {
        streamData = true;
        Serial.println("{\"status\": \"Data stream ON\"}");
    } else if (command == "DATA_OFF") {
        streamData = false;
        Serial.println("{\"status\": \"Data stream OFF\"}");
    } else if (command == "ZERO") {
        yawOffset = smoothYaw;
        pitchOffset = smoothPitch;
        rollOffset = smoothRoll;
        Serial.println("{\"status\": \"Zeroed current position\"}");
    } else if (command == "CALIBRATE") {
        Serial.println("{\"status\": \"Calibrating... Keep IMU static.\"}");
        mpu.CalibrateAccel(6);
        mpu.CalibrateGyro(6);
        mpu.PrintActiveOffsets();
        Serial.println("{\"status\": \"Calibration complete\"}");
    } else if (command.startsWith("DAMPING ")) {
        String valStr = command.substring(8);
        float newAlpha = valStr.toFloat();
        if (newAlpha > 0.0 && newAlpha <= 1.0) {
            alpha = newAlpha;
            Serial.printf("{\"status\": \"Damping alpha set to %.2f\"}\n", alpha);
        } else {
            Serial.println("{\"status\": \"Invalid alpha. Must be > 0 and <= 1.0\"}");
        }
    }
}

void setup() {
    Serial.begin(115200);
    // ESP32-C3 requires a slight delay to setup native USB serial
    delay(2000); 

    Wire.begin(SDA_PIN, SCL_PIN);
    Wire.setClock(400000); // 400kHz I2C clock

    Serial.println("{\"status\": \"Initializing I2C devices...\"}");
    mpu.initialize();
    analogReadResolution(12); // ESP32 default is 12-bit (0-4095)
    pinMode(INTERRUPT_PIN, INPUT_PULLUP);

    bool connected = mpu.testConnection();
    Serial.println(connected ? "{\"status\": \"MPU6050 connection successful\"}" : "{\"status\": \"MPU6050 connection failed\"}");

    devStatus = mpu.dmpInitialize();

    // Default offsets
    mpu.setXGyroOffset(220);
    mpu.setYGyroOffset(76);
    mpu.setZGyroOffset(-85);
    mpu.setZAccelOffset(1788);

    if (devStatus == 0) {
        Serial.println("{\"status\": \"Applying initial calibration...\"}");
        mpu.CalibrateAccel(6);
        mpu.CalibrateGyro(6);
        mpu.PrintActiveOffsets();

        Serial.println("{\"status\": \"Enabling DMP...\"}");
        mpu.setDMPEnabled(true);

        attachInterrupt(digitalPinToInterrupt(INTERRUPT_PIN), dmpDataReady, RISING);
        mpuIntStatus = mpu.getIntStatus();

        Serial.println("{\"status\": \"DMP ready! Waiting for first interrupt...\"}");
        dmpReady = true;
        packetSize = mpu.dmpGetFIFOPacketSize();
    } else {
        Serial.printf("{\"error\": \"DMP Initialization failed (code %d)\"}\n", devStatus);
    }
}

void loop() {
    // Handle Serial Commands
    if (Serial.available()) {
        String cmd = Serial.readStringUntil('\n');
        parseCommand(cmd);
    }

    if (!dmpReady) return;

    // Check for MPU interrupt
    if (mpuInterrupt && mpu.dmpGetCurrentFIFOPacket(fifoBuffer)) {
        mpuInterrupt = false;
        // Get quaternions and convert to Euler angles (Yaw, Pitch, Roll)
        mpu.dmpGetQuaternion(&q, fifoBuffer);
        mpu.dmpGetGravity(&gravity, &q);
        mpu.dmpGetYawPitchRoll(ypr, &q, &gravity);

        // Convert radians to degrees
        float rawYaw = ypr[0] * 180 / M_PI;
        float rawPitch = ypr[1] * 180 / M_PI;
        float rawRoll = ypr[2] * 180 / M_PI;

        // Apply Exponential Moving Average (EMA) Damping
        smoothYaw = (alpha * rawYaw) + ((1.0 - alpha) * smoothYaw);
        smoothPitch = (alpha * rawPitch) + ((1.0 - alpha) * smoothPitch);
        smoothRoll = (alpha * rawRoll) + ((1.0 - alpha) * smoothRoll);

        // Apply Zero offsets
        float finalYaw = smoothYaw - yawOffset;
        float finalPitch = smoothPitch - pitchOffset;
        float finalRoll = smoothRoll - rollOffset;

        if (streamData) {
            if (millis() - lastBatteryCheck > batteryInterval || lastBatteryCheck == 0) { updateBattery(); lastBatteryCheck = millis(); }
            Serial.printf("{\\"yaw\\": %.2f, \\"pitch\\": %.2f, \\"roll\\": %.2f, \\"batt\\": %.2f}\\n", finalYaw, finalPitch, finalRoll, batteryVoltage);
        }
    }
}

