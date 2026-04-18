#pragma once
#include <Arduino.h>
#include <MPU6050_6Axis_MotionApps20.h>

// ─── IMUModule ────────────────────────────────────────────────────────────────
// Encapsulates all MPU6050 DMP setup and per-frame data retrieval.
// Usage:
//   IMUModule imu;
//   imu.begin(SDA_PIN, SCL_PIN, INTERRUPT_PIN);
//   if (imu.isReady() && imu.update()) { float* ypr = imu.getYPR(); }
// ─────────────────────────────────────────────────────────────────────────────

class IMUModule {
public:
    IMUModule() = default;

    /// Initialise I2C, DMP and attach the interrupt.
    bool begin(uint8_t sda, uint8_t scl, uint8_t intPin);

    /// Call every loop. Returns true when fresh DMP data is available.
    bool update();

    bool isReady() const { return _dmpReady; }

    /// Raw Yaw/Pitch/Roll in degrees (no smoothing, no offset applied).
    float* getRawYPR() { return _rawYPR; }

    /// Calibrate accelerometer and gyroscope (blocks ~2 s).
    void calibrate();

    MPU6050& mpu() { return _mpu; }

private:
    MPU6050     _mpu;
    uint8_t     _fifoBuffer[64] = {};
    Quaternion  _q;
    VectorFloat _gravity;
    float       _rawYPR[3] = {};
    bool        _dmpReady   = false;
    uint16_t    _packetSize = 0;

    static volatile bool _interrupt;
    static void IRAM_ATTR _isr() { _interrupt = true; }
};
