#include <WiFi.h>
#include <WiFiAP.h>
#include <WiFiUdp.h>
#include "src/intercept-mid-xye/decode_xye.h"
#include "esp_wifi.h"

#define MASTER_START_BYTE 0xAA
#define MASTER_END_BYTE 0x55
#define RCV_BUFFER_LENGTH 128
#define SEND_RECEIVE_ENABLE_485 34 //receiving when low

const char *ssid = "HVAC-Shark";
const char *password = "12345678";
const int udpPort = 22222;

HardwareSerial serialRS485(2); // Use UART2
WiFiUDP udp;



void setup() {
  Serial.begin(115200); // USB console output
  serialRS485.begin(4800, SERIAL_8N1, 16, 17); // RS232 interface (RX, TX)
  Serial.println("Hello, this is the HVAC shark for Midea"); // Hello world for serial port check

  pinMode(SEND_RECEIVE_ENABLE_485, OUTPUT); //sending currently not implemented, so fix for receiving
  digitalWrite(SEND_RECEIVE_ENABLE_485, LOW);

  // Start the Wi-Fi access point
  WiFi.softAP(ssid, password);
  Serial.println("Wi-Fi access point started");

  // Set Wi-Fi transmit power (range: 8 to 84, corresponding to -1 to 20.5 dBm)
  // Values and corresponding dBm: 8 -> -1 dBm, 16 -> 2 dBm, 24 -> 5 dBm, 32 -> 8 dBm, 40 -> 11 dBm, 48 -> 14 dBm, 56 -> 17 dBm, 64 -> 20 dBm, 72 -> 23 dBm, 80 -> 26 dBm, 84 -> 27 dBm
  esp_wifi_set_max_tx_power(12); // Set to 20 for example, adjust as needed
  Serial.println("Wi-Fi transmit power set");

  // Start the UDP
  udp.begin(udpPort);
  Serial.println("UDP started");
}


void loop() {
  while (serialRS485.available()) {
    decodeXYE(serialRS485, udp, udpPort);
  }
}
