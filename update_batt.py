import os

path = r'c:\Users\lettu\Downloads\github clone\SafeReps\safereps-esp\src\main.cpp'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('#define INTERRUPT_PIN 10', '#define INTERRUPT_PIN 10\n#define BATTERY_PIN 0  // GPIO0 is ADC1_CH0')

content = content.replace('// Serial Control\nbool streamData = false;', '''// Serial Control
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
}''')

content = content.replace('mpu.initialize();', 'mpu.initialize();\n    analogReadResolution(12);')

old_stream = '''        if (streamData) {
            Serial.printf("{\\"yaw\\": %.2f, \\"pitch\\": %.2f, \\"roll\\": %.2f}\\n", finalYaw, finalPitch, finalRoll);
        }'''
new_stream = '''        if (streamData) {
            if (millis() - lastBatteryCheck > batteryInterval || lastBatteryCheck == 0) {
                updateBattery();
                lastBatteryCheck = millis();
            }
            Serial.printf("{\\"yaw\\": %.2f, \\"pitch\\": %.2f, \\"roll\\": %.2f, \\"batt\\": %.2f}\\n", 
                          finalYaw, finalPitch, finalRoll, batteryVoltage);
        }'''
content = content.replace(old_stream, new_stream)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done updating firmware!')
