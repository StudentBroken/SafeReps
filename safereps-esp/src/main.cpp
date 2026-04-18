#include <Arduino.h>

void setup() {
  // Serial initialization. ESP32-C3 SuperMini uses USB CDC.
  Serial.begin(115200);
  delay(2000);
  Serial.println("ESP32-C3 SuperMini Initialized");
  
  // Internal LED on ESP32-C3 SuperMini is often GPIO 8
  pinMode(8, OUTPUT);
}

void loop() {
  digitalWrite(8, HIGH);
  Serial.println("Tick");
  delay(1000);
  digitalWrite(8, LOW);
  Serial.println("Tock");
  delay(1000);
}
